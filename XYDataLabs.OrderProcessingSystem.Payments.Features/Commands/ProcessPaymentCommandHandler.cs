using System.Diagnostics;
using System.Globalization;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Mappings;
using XYDataLabs.OrderProcessingSystem.Application.Utilities;
using XYDataLabs.OrderProcessingSystem.SharedKernel;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;
using XYDataLabs.OrderProcessingSystem.Orders.Contracts;
using static XYDataLabs.OrderProcessingSystem.Application.Utilities.AppMasterConstant;
using PaymentAttempt = global::XYDataLabs.OrderProcessingSystem.Domain.Entities.PaymentAttempt;
using PaymentAttemptStatus = global::XYDataLabs.OrderProcessingSystem.Domain.Entities.PaymentAttemptStatus;
using PaymentProvider = global::XYDataLabs.OrderProcessingSystem.Domain.Entities.PaymentProvider;
using PaymentMethod = global::XYDataLabs.OrderProcessingSystem.Domain.Entities.PaymentMethod;
using PaymentAttemptHistory = global::XYDataLabs.OrderProcessingSystem.Domain.Entities.PaymentAttemptHistory;
using CardTransaction = global::XYDataLabs.OrderProcessingSystem.Domain.Entities.CardTransaction;
using TransactionStatusHistory = global::XYDataLabs.OrderProcessingSystem.Domain.Entities.TransactionStatusHistory;
using PayinLog = global::XYDataLabs.OrderProcessingSystem.Domain.Entities.PayinLog;
using PayinLogDetails = global::XYDataLabs.OrderProcessingSystem.Domain.Entities.PayinLogDetails;
using BillingCustomerKeyInfo = global::XYDataLabs.OrderProcessingSystem.Domain.Entities.BillingCustomerKeyInfo;

namespace XYDataLabs.OrderProcessingSystem.Payments.Features.Commands;

public sealed class ProcessPaymentCommandHandler : ICommandHandler<ProcessPaymentCommand, Result<PaymentDto>>
{
    private readonly IPaymentProviderGateway _paymentProviderGateway;
    private readonly IPaymentTelemetryTracker _paymentTelemetryTracker;
    private readonly ILogger<ProcessPaymentCommandHandler> _logger;
    private readonly string _redirectUrl;
    private readonly string _defaultDeviceSessionId;
    private readonly IAppDbContext _context;
    private readonly PaymentProvider _paymentProvider;
    private readonly TimeProvider _timeProvider;
    private readonly ITenantProvider _tenantProvider;
    private readonly IOrderModuleApi _orderModuleApi;
    private bool UsesProviderHostedCheckout =>
        string.Equals(_paymentProvider.ProviderType, PaymentProviderTypes.Razorpay, StringComparison.OrdinalIgnoreCase);

    public ProcessPaymentCommandHandler(
        IPaymentProviderGateway paymentProviderGateway,
        IOptions<PaymentGatewayRequestDefaults> paymentGatewayRequestDefaults,
        IPaymentTelemetryTracker paymentTelemetryTracker,
        ILogger<ProcessPaymentCommandHandler> logger,
        IAppDbContext context,
        IOrderModuleApi orderModuleApi,
        ITenantPaymentProviderResolver paymentProviderResolver,
        TimeProvider timeProvider,
        ITenantProvider tenantProvider)
    {
        ArgumentNullException.ThrowIfNull(paymentProviderGateway);
        ArgumentNullException.ThrowIfNull(paymentGatewayRequestDefaults);
        ArgumentNullException.ThrowIfNull(paymentTelemetryTracker);
        ArgumentNullException.ThrowIfNull(logger);
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(orderModuleApi);
        ArgumentNullException.ThrowIfNull(paymentProviderResolver);
        ArgumentNullException.ThrowIfNull(timeProvider);
        ArgumentNullException.ThrowIfNull(tenantProvider);

        _paymentProviderGateway = paymentProviderGateway;
        _paymentTelemetryTracker = paymentTelemetryTracker;
        _logger = logger;
        var requestDefaults = paymentGatewayRequestDefaults.Value;
        _redirectUrl = requestDefaults.RedirectUrl;
        _defaultDeviceSessionId = requestDefaults.DeviceSessionId;
        _context = context;
        _orderModuleApi = orderModuleApi;
        _timeProvider = timeProvider;

        _tenantProvider = tenantProvider;
        _paymentProvider = paymentProviderResolver.ResolveCurrentTenantProvider();

        if (!string.Equals(_paymentProvider.ProviderType, _paymentProviderGateway.ProviderType, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(
                $"Configured payment provider '{_paymentProvider.ProviderType}' does not match the registered gateway '{_paymentProviderGateway.ProviderType}' for tenant {_tenantProvider.TenantId}.");
        }
    }

    public async Task<Result<PaymentDto>> HandleAsync(ProcessPaymentCommand command, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(command);

        using var activity = PaymentActivitySource.Source.StartActivity("ProcessPayment");
        var startedAt = Stopwatch.GetTimestamp();

        PaymentMethod? paymentMethod = null;
        PaymentAttempt? paymentAttempt = null;
        try
        {
            _logger.LogInformation("Starting combined customer, card, and payment process");

            var requestedCustomerOrderId = ResolveCustomerOrderId(command.CustomerOrderId);
            var paymentTerms = await ResolveOrderPaymentTermsAsync(
                requestedCustomerOrderId,
                command.OrderReferenceId,
                cancellationToken);
            var customerOrderId = paymentTerms.CustomerOrderId;
            var paymentTraceId = GeneratePaymentTraceId();
            var attemptNumber = await GetNextAttemptNumberAsync(customerOrderId, cancellationToken);
            var attemptOrderId = GenerateAttemptOrderId(customerOrderId, attemptNumber);
            var isThreeDSecureEnabled = _paymentProvider.Use3DSecure;

            activity?.SetTag("payment.customer_order_id", customerOrderId);
            activity?.SetTag("payment.attempt_order_id", attemptOrderId);
            activity?.SetTag("payment.trace_id", paymentTraceId);

            var resolvedDeviceSessionId = string.IsNullOrWhiteSpace(command.DeviceSessionId)
                ? _defaultDeviceSessionId
                : command.DeviceSessionId;

            // Build DTO for mapper compatibility
            var request = new CustomerWithCardPaymentRequestDto
            {
                Name = command.Name,
                Email = command.Email,
                DeviceSessionId = resolvedDeviceSessionId,
                CardNumber = command.CardNumber,
                ExpirationYear = command.ExpirationYear,
                ExpirationMonth = command.ExpirationMonth,
                Cvv2 = command.Cvv2,
                CustomerOrderId = customerOrderId,
                ClientCallbackOrigin = command.ClientCallbackOrigin
            };

            _logger.LogInformation(
                "Generated payment attempt order id {AttemptOrderId} and payment trace id {PaymentTraceId} from customer order id {CustomerOrderId}",
                attemptOrderId,
                paymentTraceId,
                customerOrderId);

            var tenantCode = _tenantProvider.TenantCode;
            var redirectUrl = BuildRedirectUrl(_redirectUrl, tenantCode, command.ClientCallbackOrigin);

            paymentMethod = await CreatePaymentMethodAsync(cancellationToken);
            paymentAttempt = await CreatePaymentAttemptAsync(customerOrderId, attemptOrderId, paymentTraceId, attemptNumber, cancellationToken);
            _paymentTelemetryTracker.Track(new PaymentTelemetryEvent
            {
                EventName = PaymentTelemetryEventNames.AttemptCreated,
                TenantCode = tenantCode,
                CustomerOrderId = customerOrderId,
                AttemptOrderId = paymentAttempt.AttemptOrderId,
                PaymentTraceId = paymentAttempt.PaymentTraceId,
                ProviderType = _paymentProvider.ProviderType,
                IsThreeDSecureEnabled = isThreeDSecureEnabled,
            });

            var (paymentGatewayCustomer, billingCustomerId) = await CreateCustomerAsync(request, paymentMethod, cancellationToken);
            await UpdatePaymentMethodByBillingCustomerIdAsync(paymentMethod.Id, billingCustomerId, cancellationToken);
            var createdCard = await CreateCardTokenAsync(
                request,
                paymentGatewayCustomer,
                billingCustomerId,
                customerOrderId,
                attemptOrderId,
                paymentTraceId,
                paymentTerms,
                cancellationToken);
            var charge = await CreateChargeAsync(
                request,
                paymentGatewayCustomer,
                createdCard.Id,
                paymentMethod,
                billingCustomerId,
                customerOrderId,
                attemptOrderId,
                paymentTraceId,
                paymentTerms,
                isThreeDSecureEnabled,
                redirectUrl,
                cancellationToken);
            var normalizedChargeStatus = EnumHelper.NormalizeOpenPayStatus(charge.Status)
                ?? EnumHelper.GetEnumDescription(PaymentStatus.Unknown);
            var threeDSecureStage = ResolveChargeThreeDSecureStage(normalizedChargeStatus, isThreeDSecureEnabled, charge.RedirectUrl);

            await UpdatePaymentAttemptAfterChargeAsync(paymentAttempt, normalizedChargeStatus, charge, charge.ErrorMessage, cancellationToken);
            _paymentTelemetryTracker.Track(new PaymentTelemetryEvent
            {
                EventName = PaymentTelemetryEventNames.ChargeCreated,
                TenantCode = tenantCode,
                CustomerOrderId = customerOrderId,
                AttemptOrderId = paymentAttempt.AttemptOrderId,
                PaymentId = charge.Id,
                PaymentTraceId = paymentTraceId,
                ProviderType = _paymentProvider.ProviderType,
                PaymentStatus = normalizedChargeStatus,
                StatusCategory = EnumHelper.ToStatusCategory(normalizedChargeStatus),
                ThreeDSecureStage = threeDSecureStage,
                IsThreeDSecureEnabled = isThreeDSecureEnabled,
                ErrorMessage = charge.ErrorMessage,
            });

            BusinessMetrics.RecordPaymentAttempt(
                outcome: "success",
                providerName: _paymentProvider.Name,
                isThreeDSecureEnabled: isThreeDSecureEnabled,
                paymentStatus: normalizedChargeStatus,
                duration: Stopwatch.GetElapsedTime(startedAt));

            return new PaymentDto
            {
                Id = charge.Id,
                CustomerOrderId = customerOrderId,
                OrderReferenceId = paymentTerms.OrderReferenceId,
                CustomerId = paymentGatewayCustomer.Id,
                Amount = paymentTerms.Amount,
                Currency = paymentTerms.CurrencyCode,
                Status = normalizedChargeStatus,
                CreatedAt = charge.CreatedAt ?? _timeProvider.GetUtcNow().UtcDateTime,
                TransactionId = charge.Authorization,
                ThreeDSecureUrl = charge.RedirectUrl,
                ErrorMessage = charge.ErrorMessage,
                IsThreeDSecureEnabled = isThreeDSecureEnabled,
                ThreeDSecureStage = threeDSecureStage
            };
        }
        catch (Exception ex)
        {
            if (paymentAttempt is not null && paymentAttempt.Status == PaymentAttemptStatus.PendingProviderCall)
            {
                if (ex is PaymentProviderCustomerActionException)
                {
                    // Terminal customer-action failure (declined, insufficient funds, expired card, etc.).
                    // The provider definitively rejected the charge — no retry and no reconciliation needed.
                    await MarkAttemptFailedAsync(paymentAttempt, ex.Message, cancellationToken);
                }
                else if (ex is PaymentProviderIntegrationNotEnabledException)
                {
                    // Provider integration feature not enabled (e.g. Razorpay S2S not activated).
                    // This is a setup/configuration issue, not a card error. Mark as failed with a
                    // clear operator-actionable message; retrying would not help until the feature is enabled.
                    await MarkAttemptFailedAsync(paymentAttempt, ex.Message, cancellationToken);
                }
                else
                {
                    await MarkAttemptUnknownForReconciliationAsync(paymentAttempt, ex.Message, cancellationToken);
                }
            }

            BusinessMetrics.RecordPaymentAttempt(
                outcome: "failure",
                providerName: _paymentProvider.Name,
                isThreeDSecureEnabled: _paymentProvider.Use3DSecure,
                paymentStatus: "exception",
                duration: Stopwatch.GetElapsedTime(startedAt));

            _logger.LogError(ex, "Error in combined payment process: {Message}", ex.Message);
            if (paymentMethod is not null)
            {
                try
                {
                    paymentMethod.Status = false;
                    paymentMethod.UpdatedDate = _timeProvider.GetUtcNow().UtcDateTime;
                    _context.PaymentMethods.Update(paymentMethod);
                    await _context.SaveChangesAsync(CancellationToken.None);
                    _logger.LogInformation("Deactivated orphaned PaymentMethod {PaymentMethodId} after payment failure", paymentMethod.Id);
                }
                catch (Exception cleanupEx)
                {
                    _logger.LogWarning(cleanupEx, "Failed to deactivate orphaned PaymentMethod {PaymentMethodId}", paymentMethod.Id);
                }
            }
            throw new InvalidOperationException("Payment processing failed during customer, card, or charge creation.", ex);
        }
    }

    private async Task<OrderPaymentTerms> ResolveOrderPaymentTermsAsync(
        string customerOrderId,
        Guid? orderReferenceId,
        CancellationToken cancellationToken)
    {
        var linkedOrderReferenceId = orderReferenceId.GetValueOrDefault();
        var hasLinkedOrderReferenceId = linkedOrderReferenceId != Guid.Empty;
        OrderPaymentContextDto? paymentContext = null;
        if (hasLinkedOrderReferenceId)
        {
            paymentContext = await _orderModuleApi.GetPaymentContextByOrderReferenceAsync(linkedOrderReferenceId, cancellationToken);
        }

        paymentContext ??= await _orderModuleApi.GetPaymentContextAsync(customerOrderId, cancellationToken);
        if (paymentContext is null)
        {
            throw new InvalidOperationException(
                hasLinkedOrderReferenceId
                    ? $"Persisted order reference '{linkedOrderReferenceId}' was not found for the active tenant."
                    : $"Persisted order '{customerOrderId}' was not found for the active tenant.");
        }

        if (paymentContext.Amount <= 0m
            || string.IsNullOrWhiteSpace(paymentContext.CurrencyCode))
        {
            throw new InvalidOperationException(
                $"Persisted order '{customerOrderId}' has invalid payment terms.");
        }

        return new OrderPaymentTerms(
            paymentContext.CustomerOrderId,
            paymentContext.Amount,
            paymentContext.CurrencyCode.Trim().ToUpperInvariant(),
            paymentContext.OrderReferenceId,
            paymentContext.Status,
            paymentContext.ConcurrencyToken);
    }

    private async Task<int> GetNextAttemptNumberAsync(string customerOrderId, CancellationToken cancellationToken)
    {
        var currentMaxAttemptNumber = await _context.PaymentAttempts
            .Where(attempt => attempt.TenantId == _tenantProvider.TenantId && attempt.CustomerOrderId == customerOrderId)
            .Select(attempt => (int?)attempt.AttemptNumber)
            .MaxAsync(cancellationToken)
            ?? 0;

        return currentMaxAttemptNumber + 1;
    }

    private async Task<PaymentAttempt> CreatePaymentAttemptAsync(
        string customerOrderId,
        string attemptOrderId,
        string paymentTraceId,
        int attemptNumber,
        CancellationToken cancellationToken)
    {
        var now = _timeProvider.GetUtcNow().UtcDateTime;
        var paymentAttempt = new PaymentAttempt
        {
            CustomerOrderId = customerOrderId,
            AttemptOrderId = attemptOrderId,
            PaymentTraceId = paymentTraceId,
            AttemptNumber = attemptNumber,
            Status = PaymentAttemptStatus.PendingProviderCall,
            PaymentProviderName = _paymentProvider.Name,
            TenantId = _tenantProvider.TenantId,
            CreatedDate = now,
        };

        _context.PaymentAttempts.Add(paymentAttempt);
        _context.PaymentAttemptHistories.Add(new PaymentAttemptHistory
        {
            PaymentAttempt = paymentAttempt,
            AttemptOrderId = attemptOrderId,
            Status = PaymentAttemptStatus.PendingProviderCall,
            PaymentTraceId = paymentTraceId,
            Notes = "Payment attempt persisted before provider charge call.",
            TenantId = _tenantProvider.TenantId,
            CreatedDate = now,
        });

        await _context.SaveChangesAsync(cancellationToken);
        return paymentAttempt;
    }

    private async Task UpdatePaymentAttemptAfterChargeAsync(
        PaymentAttempt paymentAttempt,
        string normalizedChargeStatus,
        PaymentGatewayChargeResult charge,
        string? errorMessage,
        CancellationToken cancellationToken)
    {
        var targetStatus = ResolvePaymentAttemptStatus(normalizedChargeStatus);
        var now = _timeProvider.GetUtcNow().UtcDateTime;

        paymentAttempt.Status = targetStatus;
        paymentAttempt.ProviderStatus = normalizedChargeStatus;
        paymentAttempt.ProviderChargeId = charge.Id;
        paymentAttempt.ProviderReferenceId = charge.Authorization;
        paymentAttempt.LastErrorMessage = errorMessage;
        paymentAttempt.UpdatedDate = now;

        _context.PaymentAttempts.Update(paymentAttempt);
        _context.PaymentAttemptHistories.Add(new PaymentAttemptHistory
        {
            PaymentAttemptId = paymentAttempt.Id,
            AttemptOrderId = paymentAttempt.AttemptOrderId,
            Status = targetStatus,
            PaymentTraceId = paymentAttempt.PaymentTraceId,
            ProviderStatus = normalizedChargeStatus,
            Notes = $"Charge response mapped to payment attempt status '{targetStatus}'.",
            TenantId = _tenantProvider.TenantId,
            CreatedDate = now,
        });

        await _context.SaveChangesAsync(cancellationToken);
    }

    private async Task MarkAttemptUnknownForReconciliationAsync(
        PaymentAttempt paymentAttempt,
        string errorMessage,
        CancellationToken cancellationToken)
    {
        var now = _timeProvider.GetUtcNow().UtcDateTime;
        paymentAttempt.Status = PaymentAttemptStatus.UnknownNeedsReconciliation;
        paymentAttempt.LastErrorMessage = errorMessage;
        paymentAttempt.UpdatedDate = now;

        _context.PaymentAttempts.Update(paymentAttempt);
        _context.PaymentAttemptHistories.Add(new PaymentAttemptHistory
        {
            PaymentAttemptId = paymentAttempt.Id,
            AttemptOrderId = paymentAttempt.AttemptOrderId,
            Status = PaymentAttemptStatus.UnknownNeedsReconciliation,
            PaymentTraceId = paymentAttempt.PaymentTraceId,
            ProviderStatus = paymentAttempt.ProviderStatus,
            Notes = "Charge execution failed after attempt persistence; reconciliation required.",
            TenantId = _tenantProvider.TenantId,
            CreatedDate = now,
        });

        await _context.SaveChangesAsync(cancellationToken);
    }

    private async Task MarkAttemptFailedAsync(
        PaymentAttempt paymentAttempt,
        string errorMessage,
        CancellationToken cancellationToken)
    {
        var now = _timeProvider.GetUtcNow().UtcDateTime;
        paymentAttempt.Status = PaymentAttemptStatus.Failed;
        paymentAttempt.LastErrorMessage = errorMessage;
        paymentAttempt.UpdatedDate = now;

        _context.PaymentAttempts.Update(paymentAttempt);
        _context.PaymentAttemptHistories.Add(new PaymentAttemptHistory
        {
            PaymentAttemptId = paymentAttempt.Id,
            AttemptOrderId = paymentAttempt.AttemptOrderId,
            Status = PaymentAttemptStatus.Failed,
            PaymentTraceId = paymentAttempt.PaymentTraceId,
            ProviderStatus = paymentAttempt.ProviderStatus,
            Notes = "Customer-action failure (declined, insufficient funds, or similar terminal outcome). No retry or reconciliation.",
            TenantId = _tenantProvider.TenantId,
            CreatedDate = now,
        });

        await _context.SaveChangesAsync(cancellationToken);
    }

    private async Task<PaymentMethod> CreatePaymentMethodAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Creating PaymentMethod...");

        // Resolve the PaymentProviderId from the request-scoped context, which routes to the
        // tenant's actual DB (dedicated or shared pool). The scoped AppMasterData also reads
        // from this context, but uses the Id for config lookups only (Use3DSecure, Name).
        // The FK-safe Id must come from the DB that owns the PaymentMethods row.
        // Phase 8.6 (ADR-019): IsActive is no longer the routing authority — routing is driven
        // by Tenant.PaymentProviderCode. All PaymentProvider rows are seeded with IsActive=false.
        // Filter by ProviderType only; the query filter on the context already scopes to this tenant.
        var providerIdInTenantDb = await _context.PaymentProviders
            .Where(p => p.ProviderType == _paymentProvider.ProviderType)
            .Select(p => p.Id)
            .FirstOrDefaultAsync(cancellationToken);

        if (providerIdInTenantDb == 0)
        {
            throw new InvalidOperationException(
                $"No PaymentProvider row found for provider type '{_paymentProvider.ProviderType}' " +
                $"in the tenant DB. Ensure all migration and seed steps have been applied.");
        }

        var openPayMethod = new PaymentMethod
        {
            Token = Guid.NewGuid().ToString("N"),
            Status = true,
            PaymentProviderId = providerIdInTenantDb,
            CreatedDate = _timeProvider.GetUtcNow().UtcDateTime
        };
        _context.PaymentMethods.Add(openPayMethod);
        await _context.SaveChangesAsync(cancellationToken);
        _logger.LogInformation("PaymentMethod created with ID: {PaymentMethodId}", openPayMethod.Id);
        return openPayMethod;
    }

    private static string BuildRedirectUrl(string baseRedirectUrl, string? tenantCode, string? clientCallbackOrigin)
    {
        var builder = new UriBuilder(baseRedirectUrl);
        var queryParameters = new List<string>();

        if (!string.IsNullOrWhiteSpace(builder.Query))
        {
            queryParameters.Add(builder.Query.TrimStart('?'));
        }

        if (!string.IsNullOrWhiteSpace(tenantCode))
        {
            queryParameters.Add($"tenantCode={Uri.EscapeDataString(tenantCode)}");
        }

        if (!string.IsNullOrWhiteSpace(clientCallbackOrigin))
        {
            queryParameters.Add($"clientCallbackOrigin={Uri.EscapeDataString(clientCallbackOrigin)}");
        }

        builder.Query = string.Join("&", queryParameters.Where(static value => !string.IsNullOrWhiteSpace(value)));
        return builder.Uri.ToString();
    }

    private async Task UpdatePaymentMethodByBillingCustomerIdAsync(int paymentMethodId, int billingCustomerId, CancellationToken cancellationToken)
    {
        _logger.LogInformation("Updating PaymentMethod for BillingCustomerId: {BillingCustomerId}", billingCustomerId);

        var paymentMethod = await _context.PaymentMethods.FindAsync([paymentMethodId], cancellationToken);
        if (paymentMethod is null)
            throw new InvalidOperationException($"PaymentMethod with ID: {paymentMethodId} not found");

        paymentMethod.CreatedBy = billingCustomerId;
        paymentMethod.UpdatedBy = billingCustomerId;
        paymentMethod.UpdatedDate = _timeProvider.GetUtcNow().UtcDateTime;
        _context.PaymentMethods.Update(paymentMethod);
        await _context.SaveChangesAsync(cancellationToken);

        _logger.LogInformation("PaymentMethod updated for BillingCustomerId: {BillingCustomerId}", billingCustomerId);
    }

    private async Task<(PaymentGatewayCustomer Customer, int BillingCustomerId)> CreateCustomerAsync(
        CustomerWithCardPaymentRequestDto request,
        PaymentMethod paymentMethod,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation("Creating customer in {PaymentProvider}...", _paymentProvider.Name);
        var existingCustomer = await _context.BillingCustomers
            .FirstOrDefaultAsync(c => c.Name == request.Name && c.Email == request.Email, cancellationToken);

        if (existingCustomer is not null)
        {
            _logger.LogInformation("Existing customer found with ID: {CustomerId}", existingCustomer.APICustomerId);
            return (new PaymentGatewayCustomer(existingCustomer.APICustomerId, existingCustomer.Name, existingCustomer.Email), existingCustomer.Id);
        }

        var paymentGatewayCustomer = await _paymentProviderGateway.CreateCustomerAsync(
            new PaymentGatewayCreateCustomerRequest(request.Name, request.Email),
            cancellationToken);

        _logger.LogInformation("Customer created with ID: {CustomerId}", paymentGatewayCustomer.Id);

        var billingCustomer = request.ToBillingCustomer();
        billingCustomer.APICustomerId = paymentGatewayCustomer.Id;
        billingCustomer.TwoLetterIsoCode = AppMasterConstant.DefaultCountryCode;
        billingCustomer.PaymentMethodId = paymentMethod.Id;
        billingCustomer.CreatedDate = _timeProvider.GetUtcNow().UtcDateTime;
        _context.BillingCustomers.Add(billingCustomer);
        await _context.SaveChangesAsync(cancellationToken);

        // Id is now assigned by the database — backfill the audit column in the same batch as the key info insert
        billingCustomer.CreatedBy = billingCustomer.Id;
        _context.BillingCustomers.Update(billingCustomer);

        var keyInfo = new BillingCustomerKeyInfo
        {
            BillingCustomerId = billingCustomer.Id,
            KeyName = "CreationDate",
            KeyValue = billingCustomer.CreatedDate?.ToString("O", System.Globalization.CultureInfo.InvariantCulture) ?? string.Empty,
            CreatedBy = billingCustomer.Id,
            CreatedDate = billingCustomer.CreatedDate
        };

        _context.BillingCustomerKeyInfos.Add(keyInfo);
        await _context.SaveChangesAsync(cancellationToken);

        return (paymentGatewayCustomer, billingCustomer.Id);
    }

    private async Task<PaymentGatewayCardToken> CreateCardTokenAsync(
        CustomerWithCardPaymentRequestDto request,
        PaymentGatewayCustomer paymentGatewayCustomer,
        int billingCustomerId,
        string customerOrderId,
        string attemptOrderId,
        string paymentTraceId,
        OrderPaymentTerms paymentTerms,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation("Creating card token in {PaymentProvider}...", _paymentProvider.Name);

        var createdCard = await _paymentProviderGateway.CreateCardTokenAsync(
            new PaymentGatewayCreateCardTokenRequest(
                request.CardNumber,
                request.Name,
                request.ExpirationYear,
                request.ExpirationMonth,
                request.Cvv2,
                request.DeviceSessionId),
            cancellationToken);
        _logger.LogInformation("Card created with ID: {CardId}", createdCard.Id);

        var cardTransaction = new CardTransaction
        {
            BillingCustomerId = billingCustomerId,
            TransactionCustomerId = paymentGatewayCustomer.Id,
            TransactionId = createdCard.Id,
            PaymentTraceId = paymentTraceId,
            PaymentMethod = EnumHelper.GetEnumDescription(PaymentMethodType.Card),
            TransactionType = EnumHelper.GetEnumDescription(TransactionType.Tokenization),
            CustomerOrderId = customerOrderId,
            AttemptOrderId = attemptOrderId,
            TransactionStatus = EnumHelper.GetEnumDescription(OpenPayTransactionStatus.Completed),
            TransactionDate = NormalizeToUtc(createdCard.CreatedAt),
            CurrencyCode = paymentTerms.CurrencyCode,
            Amount = paymentTerms.Amount,
            CreditCardOwnerName = request.Name,
            CreditCardExpireYear = ResolveCardExpiryComponent(request.ExpirationYear),
            CreditCardExpireMonth = ResolveCardExpiryComponent(request.ExpirationMonth),
            MaskedCardNumber = ResolveMaskedCardNumber(request.CardNumber),
            TransactionMessage = $"Card created with ID: {createdCard.Id}",
            IsTransactionSuccess = true,
            IsThreeDSecureEnabled = false,
            ThreeDSecureStage = EnumHelper.GetEnumDescription(ThreeDSecureStage.TokenizationCompleted),
            CreatedBy = billingCustomerId,
            CreatedDate = _timeProvider.GetUtcNow().UtcDateTime
        };

        _context.CardTransactions.Add(cardTransaction);
        await _context.SaveChangesAsync(cancellationToken);

        var statusHistory = new TransactionStatusHistory
        {
            TransactionId = cardTransaction.Id,
            Status = EnumHelper.GetEnumDescription(OpenPayTransactionStatus.Completed),
            AttemptOrderId = attemptOrderId,
            Notes = "Card tokenization successful",
            PaymentTraceId = paymentTraceId,
            ThreeDSecureStage = EnumHelper.GetEnumDescription(ThreeDSecureStage.TokenizationCompleted),
            IsThreeDSecureEnabled = false,
            CreatedBy = billingCustomerId,
            CreatedDate = _timeProvider.GetUtcNow().UtcDateTime
        };

        _context.TransactionStatusHistories.Add(statusHistory);
        await _context.SaveChangesAsync(cancellationToken);

        return createdCard;
    }

    private async Task<PaymentGatewayChargeResult> CreateChargeAsync(
        CustomerWithCardPaymentRequestDto request,
        PaymentGatewayCustomer customer,
        string sourceId,
        PaymentMethod paymentMethod,
        int billingCustomerId,
        string customerOrderId,
        string attemptOrderId,
        string paymentTraceId,
        OrderPaymentTerms paymentTerms,
        bool isThreeDSecureEnabled,
        string redirectUrl,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation(
            "Creating charge in {PaymentProvider} for payment trace {PaymentTraceId}, customer order {CustomerOrderId}, attempt order {AttemptOrderId}, 3DS enabled {IsThreeDSecureEnabled}",
            _paymentProvider.Name,
            paymentTraceId,
            customerOrderId,
            attemptOrderId,
            isThreeDSecureEnabled);

        var chargeRequest = new PaymentGatewayCreateChargeRequest(
            sourceId,
            paymentTerms.Amount,
            paymentTerms.CurrencyCode,
            $"CustomerOrder: {customerOrderId}; AttemptOrder: {attemptOrderId}",
            request.DeviceSessionId,
            attemptOrderId,
            isThreeDSecureEnabled,
            redirectUrl,
            customer,
            CardDetails: new PaymentGatewayCardDetails(
                request.CardNumber,
                request.Name,
                request.ExpirationYear,
                request.ExpirationMonth,
                request.Cvv2),
            ProviderOrderId: paymentTraceId);

        var charge = await _paymentProviderGateway.CreateChargeAsync(chargeRequest, cancellationToken);
        _logger.LogInformation("Charge created with ID: {ChargeId}", charge.Id);
        var normalizedChargeStatus = EnumHelper.NormalizeOpenPayStatus(charge.Status)
            ?? EnumHelper.GetEnumDescription(PaymentStatus.Unknown);
        var threeDSecureStage = ResolveChargeThreeDSecureStage(normalizedChargeStatus, isThreeDSecureEnabled, charge.RedirectUrl);

        var payinLog = new PayinLog
        {
            AttemptOrderId = chargeRequest.AttemptOrderId,
            CustomerOrderId = customerOrderId,
            PaymentMethodId = paymentMethod.Id,
            PaymentMethodName = _paymentProvider.Name,
            PayinType = (int?)PayInType.Charge,
            OpenPayChargeId = charge.Id,
            PaymentTraceId = paymentTraceId,
            Amount = chargeRequest.Amount,
            AmountFromAPI = charge.Amount,
            CardOwnerName = request.Name,
            LastFourCardNbr = ResolveLastFourCardDigits(request.CardNumber),
            Currency = chargeRequest.Currency,
            IsThreeDSecureEnabled = isThreeDSecureEnabled,
            ThreeDSecureStage = threeDSecureStage,
            Result = EnumHelper.GetEnumIdFromDescription<PaymentStatus>(normalizedChargeStatus) ?? (int)PaymentStatus.Unknown,
            CreatedBy = billingCustomerId,
            CreatedDate = _timeProvider.GetUtcNow().UtcDateTime
        };

        _context.PayinLogs.Add(payinLog);
        await _context.SaveChangesAsync(cancellationToken);

        var payinLogDetails = new PayinLogDetails
        {
            PayinLogId = payinLog.Id,
            PostInfo = System.Text.Json.JsonSerializer.Serialize(chargeRequest),
            RespInfo = System.Text.Json.JsonSerializer.Serialize(charge),
            AdditionalInfo = BuildTrackingInfo(paymentTraceId, customerOrderId, chargeRequest.AttemptOrderId, threeDSecureStage, "Charge created in OpenPay"),
            PaymentTraceId = paymentTraceId,
            ThreeDSecureStage = threeDSecureStage,
            CreatedBy = billingCustomerId,
            CreatedDate = _timeProvider.GetUtcNow().UtcDateTime
        };

        _context.PayinLogDetails.Add(payinLogDetails);

        var cardTransaction = new CardTransaction
        {
            BillingCustomerId = billingCustomerId,
            TransactionCustomerId = customer.Id,
            TransactionId = charge.Id,
            PaymentTraceId = paymentTraceId,
            PaymentMethod = EnumHelper.GetEnumDescription(PaymentMethodType.Card),
            TransactionType = EnumHelper.GetEnumDescription(TransactionType.Charge),
            CustomerOrderId = customerOrderId,
            AttemptOrderId = chargeRequest.AttemptOrderId,
            Description = chargeRequest.Description,
            TransactionStatus = normalizedChargeStatus,
            TransactionDate = NormalizeToUtc(charge.CreatedAt),
            Amount = charge.Amount,
            CurrencyCode = chargeRequest.Currency,
            IsTransactionSuccess = EnumHelper.IsSuccessStatus(normalizedChargeStatus),
            IsThreeDSecureEnabled = isThreeDSecureEnabled,
            ThreeDSecureStage = threeDSecureStage,
            TransactionReferenceId = charge.Authorization,
            RedirectUrl = charge.RedirectUrl,
            CreditCardOwnerName = request.Name,
            CreditCardExpireYear = ResolveCardExpiryComponent(request.ExpirationYear),
            CreditCardExpireMonth = ResolveCardExpiryComponent(request.ExpirationMonth),
            MaskedCardNumber = ResolveMaskedCardNumber(request.CardNumber),
            TransactionMessage = charge.ErrorMessage,
            CreatedBy = billingCustomerId,
            CreatedDate = _timeProvider.GetUtcNow().UtcDateTime
        };

        _context.CardTransactions.Add(cardTransaction);
        await _context.SaveChangesAsync(cancellationToken);

        var statusHistory = new TransactionStatusHistory
        {
            TransactionId = cardTransaction.Id,
            AttemptOrderId = chargeRequest.AttemptOrderId,
            Status = normalizedChargeStatus,
            Notes = charge.ErrorMessage,
            PaymentTraceId = paymentTraceId,
            ThreeDSecureStage = threeDSecureStage,
            IsThreeDSecureEnabled = isThreeDSecureEnabled,
            TransactionReferenceId = charge.Authorization,
            CreatedBy = billingCustomerId,
            CreatedDate = _timeProvider.GetUtcNow().UtcDateTime
        };

        _context.TransactionStatusHistories.Add(statusHistory);
        await _context.SaveChangesAsync(cancellationToken);

        return charge;
    }

    private static PaymentAttemptStatus ResolvePaymentAttemptStatus(string normalizedChargeStatus)
    {
        if (EnumHelper.IsSuccessStatus(normalizedChargeStatus))
        {
            return PaymentAttemptStatus.Succeeded;
        }

        if (EnumHelper.IsFailureStatus(normalizedChargeStatus) || EnumHelper.IsCancelledStatus(normalizedChargeStatus))
        {
            return PaymentAttemptStatus.Failed;
        }

        if (EnumHelper.IsPendingStatus(normalizedChargeStatus))
        {
            return PaymentAttemptStatus.ProviderAccepted;
        }

        return PaymentAttemptStatus.UnknownNeedsReconciliation;
    }

    private static string GenerateAttemptOrderId(string baseOrderId, int attemptNumber)
    {
        var normalizedBaseOrderId = string.IsNullOrWhiteSpace(baseOrderId)
            ? $"ORD-{Guid.NewGuid():N}"
            : baseOrderId.Trim();

        return $"{normalizedBaseOrderId}-{attemptNumber}";
    }

    private static string GeneratePaymentTraceId()
    {
        return Guid.NewGuid().ToString("N", CultureInfo.InvariantCulture);
    }

    private int ResolveCardExpiryComponent(string value)
    {
        if (int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsedValue))
        {
            return parsedValue;
        }

        return UsesProviderHostedCheckout ? 0 : throw new FormatException("Card expiry value is required for direct card providers.");
    }

    private string? ResolveMaskedCardNumber(string cardNumber)
    {
        if (string.IsNullOrWhiteSpace(cardNumber))
        {
            return UsesProviderHostedCheckout ? null : MaskCardNumber(cardNumber);
        }

        return MaskCardNumber(cardNumber);
    }

    private static string? ResolveLastFourCardDigits(string cardNumber)
    {
        if (string.IsNullOrWhiteSpace(cardNumber) || cardNumber.Length < 4)
        {
            return null;
        }

        return cardNumber[^4..];
    }

    private static string MaskCardNumber(string cardNumber)
    {
        if (string.IsNullOrWhiteSpace(cardNumber) || cardNumber.Length < 10)
            return "******";

        var bin = cardNumber[..6];
        var lastFour = cardNumber[^4..];
        var masked = new string('*', cardNumber.Length - 10);
        return $"{bin}{masked}{lastFour}";
    }

    private static string ResolveCustomerOrderId(string? customerOrderId)
    {
        return string.IsNullOrWhiteSpace(customerOrderId)
            ? $"ORD-{Guid.NewGuid():N}"
            : customerOrderId.Trim();
    }

    private static string ResolveChargeThreeDSecureStage(string? normalizedStatus, bool isThreeDSecureEnabled, string? redirectUrl)
    {
        if (!isThreeDSecureEnabled)
            return EnumHelper.GetEnumDescription(ThreeDSecureStage.NotApplicable);

        if (EnumHelper.IsSuccessStatus(normalizedStatus))
            return EnumHelper.GetEnumDescription(ThreeDSecureStage.Completed);

        if (EnumHelper.IsFailedStatus(normalizedStatus))
            return EnumHelper.GetEnumDescription(ThreeDSecureStage.Failed);

        if (EnumHelper.IsCancelledStatus(normalizedStatus))
            return EnumHelper.GetEnumDescription(ThreeDSecureStage.Cancelled);

        if (!string.IsNullOrWhiteSpace(redirectUrl))
            return EnumHelper.GetEnumDescription(ThreeDSecureStage.RedirectIssued);

        return EnumHelper.GetEnumDescription(ThreeDSecureStage.ChargeRequested);
    }

    private static string BuildTrackingInfo(string paymentTraceId, string customerOrderId, string attemptOrderId, string threeDSecureStage, string message)
    {
        return $"PaymentTraceId={paymentTraceId}; CustomerOrderId={customerOrderId}; AttemptOrderId={attemptOrderId}; ThreeDSecureStage={threeDSecureStage}; {message}";
    }

    private static DateTime? NormalizeToUtc(DateTime? dateTime)
    {
        if (!dateTime.HasValue) return null;
        return dateTime.Value.Kind == DateTimeKind.Utc
            ? dateTime.Value
            : DateTime.SpecifyKind(dateTime.Value, DateTimeKind.Local).ToUniversalTime();
    }

    private sealed record OrderPaymentTerms(
        string CustomerOrderId,
        decimal Amount,
        string CurrencyCode,
        Guid OrderReferenceId,
        string OrderStatus,
        string ConcurrencyToken);
}
