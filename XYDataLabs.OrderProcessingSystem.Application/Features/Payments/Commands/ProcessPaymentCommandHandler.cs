using AutoMapper;
using System.Globalization;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Openpay.Entities;
using Openpay.Entities.Request;
using XYDataLabs.OpenPayAdapter;
using XYDataLabs.OpenPayAdapter.Configuration;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Utilities;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;
using static XYDataLabs.OrderProcessingSystem.Application.Utilities.AppMasterConstant;
using OpenPayCustomer = Openpay.Entities.Customer;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Payments.Commands;

public sealed class ProcessPaymentCommandHandler : ICommandHandler<ProcessPaymentCommand, Result<PaymentDto>>
{
    private readonly IOpenPayAdapterService _openPayAdapterService;
    private readonly ILogger<ProcessPaymentCommandHandler> _logger;
    private readonly string _redirectUrl;
    private readonly IAppDbContext _context;
    private readonly IMapper _mapper;
    private readonly PaymentProvider _openPayProvider;
    private readonly OpenPayConfig _openPayConfig;
    private readonly TimeProvider _timeProvider;

    public ProcessPaymentCommandHandler(
        IOpenPayAdapterService openPayAdapterService,
        IOptions<OpenPayConfig> openPayOptions,
        ILogger<ProcessPaymentCommandHandler> logger,
        IAppDbContext context,
        IMapper mapper,
        AppMasterData appMasterData,
        TimeProvider timeProvider)
    {
        ArgumentNullException.ThrowIfNull(openPayAdapterService);
        ArgumentNullException.ThrowIfNull(openPayOptions);
        ArgumentNullException.ThrowIfNull(logger);
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(mapper);
        ArgumentNullException.ThrowIfNull(appMasterData);
        ArgumentNullException.ThrowIfNull(timeProvider);

        _openPayAdapterService = openPayAdapterService;
        _logger = logger;
        _openPayConfig = openPayOptions.Value;
        _redirectUrl = _openPayConfig.RedirectUrl;
        _context = context;
        _mapper = mapper;
        _timeProvider = timeProvider;

        _openPayProvider = appMasterData.GetProviderByName("OpenPay")
            ?? throw new InvalidOperationException("OpenPay provider not found in master data");
    }

    public async Task<Result<PaymentDto>> HandleAsync(ProcessPaymentCommand command, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(command);

        using var activity = PaymentActivitySource.Source.StartActivity("ProcessPayment");

        try
        {
            _logger.LogInformation("Starting combined customer, card, and payment process");

            var customerOrderId = ResolveCustomerOrderId(command.CustomerOrderId);
            var paymentTraceId = GeneratePaymentTraceId();
            var attemptOrderId = GenerateAttemptOrderId(customerOrderId);
            var isThreeDSecureEnabled = _openPayConfig.Use3DSecure;

            activity?.SetTag("payment.customer_order_id", customerOrderId);
            activity?.SetTag("payment.attempt_order_id", attemptOrderId);
            activity?.SetTag("payment.trace_id", paymentTraceId);

            var resolvedDeviceSessionId = string.IsNullOrWhiteSpace(command.DeviceSessionId)
                ? _openPayConfig.DeviceSessionId
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
                CustomerOrderId = customerOrderId
            };

            _logger.LogInformation(
                "Generated payment attempt order id {AttemptOrderId} and payment trace id {PaymentTraceId} from customer order id {CustomerOrderId}",
                attemptOrderId,
                paymentTraceId,
                customerOrderId);

            var paymentMethod = await CreatePaymentMethodAsync(cancellationToken);
            var (openpayCustomer, billingCustomerId) = await CreateCustomerAsync(request, paymentMethod, cancellationToken);
            await UpdatePaymentMethodByBillingCustomerIdAsync(paymentMethod.Id, billingCustomerId, cancellationToken);
            var createdCard = await CreateCardTokenAsync(request, openpayCustomer, billingCustomerId, customerOrderId, attemptOrderId, paymentTraceId, cancellationToken);
            var charge = await CreateChargeAsync(request, openpayCustomer, createdCard.Id, paymentMethod, billingCustomerId, customerOrderId, attemptOrderId, paymentTraceId, isThreeDSecureEnabled, cancellationToken);
            var threeDSecureStage = ResolveChargeThreeDSecureStage(charge.Status, isThreeDSecureEnabled, charge.PaymentMethod?.Url);

            return new PaymentDto
            {
                Id = charge.Id,
                CustomerOrderId = customerOrderId,
                AttemptOrderId = attemptOrderId,
                CustomerId = openpayCustomer.Id,
                Amount = new decimal(100.00),
                Currency = AppMasterConstant.DefaultCurrencyCode,
                Status = charge.Status ?? "unknown",
                CreatedAt = charge.CreationDate ?? _timeProvider.GetUtcNow().UtcDateTime,
                TransactionId = charge.Authorization,
                ThreeDSecureUrl = charge.PaymentMethod?.Url,
                ErrorMessage = charge.ErrorMessage,
                IsThreeDSecureEnabled = isThreeDSecureEnabled,
                ThreeDSecureStage = threeDSecureStage
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in combined payment process: {Message}", ex.Message);
            throw new InvalidOperationException("Payment processing failed during customer, card, or charge creation.", ex);
        }
    }

    private async Task<Domain.Entities.PaymentMethod> CreatePaymentMethodAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Creating PaymentMethod...");
        var openPayMethod = new Domain.Entities.PaymentMethod
        {
            Token = Guid.NewGuid().ToString("N"),
            Status = true,
            PaymentProviderId = _openPayProvider.Id,
            CreatedDate = _timeProvider.GetUtcNow().UtcDateTime
        };
        _context.PaymentMethods.Add(openPayMethod);
        await _context.SaveChangesAsync(cancellationToken);
        _logger.LogInformation("PaymentMethod created with ID: {PaymentMethodId}", openPayMethod.Id);
        return openPayMethod;
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

    private async Task<(OpenPayCustomer openpayCustomer, int BillingCustomerId)> CreateCustomerAsync(
        CustomerWithCardPaymentRequestDto request,
        Domain.Entities.PaymentMethod paymentMethod,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation("Creating customer in OpenPay...");
        var existingCustomer = await _context.BillingCustomers
            .FirstOrDefaultAsync(c => c.Name == request.Name && c.Email == request.Email, cancellationToken);

        if (existingCustomer is not null)
        {
            _logger.LogInformation("Existing customer found with ID: {CustomerId}", existingCustomer.APICustomerId);
            return (new OpenPayCustomer
            {
                Name = existingCustomer.Name,
                Email = existingCustomer.Email,
                RequiresAccount = false,
                Id = existingCustomer.APICustomerId
            }, existingCustomer.Id);
        }

        var openpayCustomer = await _openPayAdapterService.CreateCustomerAsync(new OpenPayCustomer
        {
            Name = request.Name,
            Email = request.Email,
            RequiresAccount = false
        });

        _logger.LogInformation("Customer created with ID: {CustomerId}", openpayCustomer.Id);

        var billingCustomer = _mapper.Map<BillingCustomer>(request);
        billingCustomer.APICustomerId = openpayCustomer.Id;
        billingCustomer.TwoLetterIsoCode = AppMasterConstant.DefaultCountryCode;
        billingCustomer.PaymentMethodId = paymentMethod.Id;
        billingCustomer.CreatedDate = _timeProvider.GetUtcNow().UtcDateTime;
        _context.BillingCustomers.Add(billingCustomer);
        await _context.SaveChangesAsync(cancellationToken);

        var keyInfo = new BillingCustomerKeyInfo
        {
            BillingCustomerId = billingCustomer.Id,
            KeyName = "CreationDate",
            KeyValue = billingCustomer.CreatedDate?.ToString("O", System.Globalization.CultureInfo.InvariantCulture) ?? string.Empty
        };

        _context.BillingCustomerKeyInfos.Add(keyInfo);
        await _context.SaveChangesAsync(cancellationToken);

        return (openpayCustomer, billingCustomer.Id);
    }

    private async Task<Card> CreateCardTokenAsync(
        CustomerWithCardPaymentRequestDto request,
        OpenPayCustomer openpayCustomerEntity,
        int billingCustomerId,
        string customerOrderId,
        string attemptOrderId,
        string paymentTraceId,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation("Creating card token in OpenPay...");

        var card = new Card
        {
            CardNumber = request.CardNumber,
            HolderName = request.Name,
            ExpirationYear = request.ExpirationYear,
            ExpirationMonth = request.ExpirationMonth,
            Cvv2 = request.Cvv2,
            DeviceSessionId = request.DeviceSessionId
        };

        var createdCard = await _openPayAdapterService.CreateCardTokenAsync(card);
        _logger.LogInformation("Card created with ID: {CardId}", createdCard.Id);

        var cardTransaction = new CardTransaction
        {
            CustomerId = billingCustomerId,
            TransactionCustomerId = openpayCustomerEntity.Id,
            TransactionId = createdCard.Id,
            PaymentTraceId = paymentTraceId,
            PaymentMethod = EnumHelper.GetEnumDescription(PaymentMethodType.Card),
            TransactionType = EnumHelper.GetEnumDescription(TransactionType.Tokenization),
            CustomerOrderId = customerOrderId,
            AttemptOrderId = attemptOrderId,
            TransactionStatus = EnumHelper.GetEnumDescription(OpenPayTransactionStatus.Completed),
            TransactionDate = createdCard.CreationDate,
            CurrencyCode = AppMasterConstant.DefaultCurrencyCode,
            Amount = new decimal(100.00),
            CreditCardOwnerName = request.Name,
            CreditCardExpireYear = int.Parse(request.ExpirationYear, CultureInfo.InvariantCulture),
            CreditCardExpireMonth = int.Parse(request.ExpirationMonth, CultureInfo.InvariantCulture),
            CreditCardNumber = request.CardNumber,
            CreditCardCvv2 = request.Cvv2,
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
            CreatedBy = billingCustomerId,
            CreatedDate = _timeProvider.GetUtcNow().UtcDateTime
        };

        _context.TransactionStatusHistories.Add(statusHistory);
        await _context.SaveChangesAsync(cancellationToken);

        return createdCard;
    }

    private async Task<Charge> CreateChargeAsync(
        CustomerWithCardPaymentRequestDto request,
        OpenPayCustomer customer,
        string sourceId,
        Domain.Entities.PaymentMethod paymentMethod,
        int billingCustomerId,
        string customerOrderId,
        string attemptOrderId,
        string paymentTraceId,
        bool isThreeDSecureEnabled,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation(
            "Creating charge in OpenPay for payment trace {PaymentTraceId}, customer order {CustomerOrderId}, attempt order {AttemptOrderId}, 3DS enabled {IsThreeDSecureEnabled}",
            paymentTraceId,
            customerOrderId,
            attemptOrderId,
            isThreeDSecureEnabled);

        var chargeRequest = new ChargeRequest
        {
            Method = EnumHelper.GetEnumDescription(PaymentMethodType.Card),
            SourceId = sourceId,
            Amount = new decimal(100.00),
            Currency = AppMasterConstant.DefaultCurrencyCode,
            Description = $"CustomerOrder: {customerOrderId}; AttemptOrder: {attemptOrderId}",
            DeviceSessionId = request.DeviceSessionId,
            OrderId = attemptOrderId,
            Use3DSecure = isThreeDSecureEnabled,
            RedirectUrl = _redirectUrl,
            Customer = customer
        };

        var charge = await _openPayAdapterService.CreateChargeAsync(chargeRequest);
        _logger.LogInformation("Charge created with ID: {ChargeId}", charge.Id);
        var threeDSecureStage = ResolveChargeThreeDSecureStage(charge.Status, isThreeDSecureEnabled, charge.PaymentMethod?.Url);

        var payinLog = new PayinLog
        {
            AttemptOrderId = chargeRequest.OrderId,
            CustomerOrderId = customerOrderId,
            PaymentMethodId = paymentMethod.Id,
            PaymentMethodName = _openPayProvider.Name,
            PayinType = (int?)PayInType.Charge,
            OpenPayChargeId = charge.Id,
            PaymentTraceId = paymentTraceId,
            Amount = chargeRequest.Amount,
            AmountFromAPI = charge.Amount,
            CardOwnerName = request.Name,
            LastFourCardNbr = request.CardNumber[^4..],
            Currency = AppMasterConstant.DefaultCurrencyCode,
            IsThreeDSecureEnabled = isThreeDSecureEnabled,
            ThreeDSecureStage = threeDSecureStage,
            Result = EnumHelper.GetEnumIdFromDescription<PaymentStatus>(charge.Status) ?? (int)PaymentStatus.Unknown,
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
            AdditionalInfo = BuildTrackingInfo(paymentTraceId, customerOrderId, chargeRequest.OrderId, threeDSecureStage, "Charge created in OpenPay"),
            PaymentTraceId = paymentTraceId,
            ThreeDSecureStage = threeDSecureStage,
            CreatedBy = billingCustomerId,
            CreatedDate = _timeProvider.GetUtcNow().UtcDateTime
        };

        _context.PayinLogDetails.Add(payinLogDetails);

        var cardTransaction = new CardTransaction
        {
            CustomerId = billingCustomerId,
            TransactionCustomerId = customer.Id,
            TransactionId = charge.Id,
            PaymentTraceId = paymentTraceId,
            PaymentMethod = EnumHelper.GetEnumDescription(PaymentMethodType.Card),
            TransactionType = EnumHelper.GetEnumDescription(TransactionType.Charge),
            CustomerOrderId = customerOrderId,
            AttemptOrderId = chargeRequest.OrderId,
            TransactionStatus = charge.Status,
            TransactionDate = charge.CreationDate,
            Amount = charge.Amount,
            CurrencyCode = AppMasterConstant.DefaultCurrencyCode,
            IsTransactionSuccess = string.Equals(charge.Status, "completed", StringComparison.OrdinalIgnoreCase),
            IsThreeDSecureEnabled = isThreeDSecureEnabled,
            ThreeDSecureStage = threeDSecureStage,
            RedirectUrl = charge.PaymentMethod?.Url,
            CreditCardOwnerName = request.Name,
            CreditCardExpireYear = int.Parse(request.ExpirationYear, CultureInfo.InvariantCulture),
            CreditCardExpireMonth = int.Parse(request.ExpirationMonth, CultureInfo.InvariantCulture),
            CreditCardNumber = request.CardNumber,
            CreditCardCvv2 = request.Cvv2,
            TransactionMessage = charge.ErrorMessage,
            CreatedBy = billingCustomerId,
            CreatedDate = _timeProvider.GetUtcNow().UtcDateTime
        };

        _context.CardTransactions.Add(cardTransaction);
        await _context.SaveChangesAsync(cancellationToken);

        var statusHistory = new TransactionStatusHistory
        {
            TransactionId = cardTransaction.Id,
            AttemptOrderId = chargeRequest.OrderId,
            Status = charge.Status,
            Notes = charge.ErrorMessage,
            PaymentTraceId = paymentTraceId,
            ThreeDSecureStage = threeDSecureStage,
            CreatedBy = billingCustomerId,
            CreatedDate = _timeProvider.GetUtcNow().UtcDateTime
        };

        _context.TransactionStatusHistories.Add(statusHistory);
        await _context.SaveChangesAsync(cancellationToken);

        return charge;
    }

    private string GenerateAttemptOrderId(string baseOrderId)
    {
        var normalizedBaseOrderId = string.IsNullOrWhiteSpace(baseOrderId)
            ? $"ORD-{Guid.NewGuid():N}"
            : baseOrderId.Trim();

        return $"{normalizedBaseOrderId}-{_timeProvider.GetUtcNow():yyyyMMddHHmmssfff}";
    }

    private static string GeneratePaymentTraceId()
    {
        return Guid.NewGuid().ToString("N", CultureInfo.InvariantCulture);
    }

    private static string ResolveCustomerOrderId(string? customerOrderId)
    {
        return string.IsNullOrWhiteSpace(customerOrderId)
            ? $"ORD-{Guid.NewGuid():N}"
            : customerOrderId.Trim();
    }

    private static string ResolveChargeThreeDSecureStage(string? status, bool isThreeDSecureEnabled, string? redirectUrl)
    {
        if (!isThreeDSecureEnabled)
        {
            return EnumHelper.GetEnumDescription(ThreeDSecureStage.NotApplicable);
        }

        var normalizedStatus = status?.Trim().ToUpperInvariant();
        if (string.Equals(normalizedStatus, "COMPLETED", StringComparison.Ordinal))
        {
            return EnumHelper.GetEnumDescription(ThreeDSecureStage.Completed);
        }

        if (string.Equals(normalizedStatus, "FAILED", StringComparison.Ordinal)
            || string.Equals(normalizedStatus, "DECLINED", StringComparison.Ordinal)
            || string.Equals(normalizedStatus, "ERROR", StringComparison.Ordinal))
        {
            return EnumHelper.GetEnumDescription(ThreeDSecureStage.Failed);
        }

        if (!string.IsNullOrWhiteSpace(redirectUrl))
        {
            return EnumHelper.GetEnumDescription(ThreeDSecureStage.RedirectIssued);
        }

        return EnumHelper.GetEnumDescription(ThreeDSecureStage.ChargeRequested);
    }

    private static string BuildTrackingInfo(string paymentTraceId, string customerOrderId, string attemptOrderId, string threeDSecureStage, string message)
    {
        return $"PaymentTraceId={paymentTraceId}; CustomerOrderId={customerOrderId}; AttemptOrderId={attemptOrderId}; ThreeDSecureStage={threeDSecureStage}; {message}";
    }
}
