using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Utilities;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;
using static XYDataLabs.OrderProcessingSystem.Application.Utilities.AppMasterConstant;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Payments.Commands;

public sealed class ConfirmPaymentStatusCommandHandler : ICommandHandler<ConfirmPaymentStatusCommand, Result<PaymentStatusDetailsDto>>
{
    private const int TransactionStatusHistoryNotesMaxLength = 255;
    private const int PaymentAttemptHistoryNotesMaxLength = 512;
    private const int PaymentAttemptLastErrorMaxLength = 512;

    private readonly IAppDbContext _context;
    private readonly IPaymentProviderGateway _paymentProviderGateway;
    private readonly IPaymentTelemetryTracker _paymentTelemetryTracker;
    private readonly ILogger<ConfirmPaymentStatusCommandHandler> _logger;
    private readonly ITenantPaymentProviderConfigurationResolver _paymentProviderConfigurationResolver;
    private readonly PaymentProvider _paymentProvider;
    private readonly ITenantProvider _tenantProvider;
    private readonly TimeProvider _timeProvider;

    public ConfirmPaymentStatusCommandHandler(
        IAppDbContext context,
        IPaymentProviderGateway paymentProviderGateway,
        IPaymentTelemetryTracker paymentTelemetryTracker,
        ILogger<ConfirmPaymentStatusCommandHandler> logger,
        ITenantPaymentProviderConfigurationResolver paymentProviderConfigurationResolver,
        ITenantPaymentProviderResolver paymentProviderResolver,
        ITenantProvider tenantProvider,
        TimeProvider timeProvider)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(paymentProviderGateway);
        ArgumentNullException.ThrowIfNull(paymentTelemetryTracker);
        ArgumentNullException.ThrowIfNull(logger);
        ArgumentNullException.ThrowIfNull(paymentProviderConfigurationResolver);
        ArgumentNullException.ThrowIfNull(paymentProviderResolver);
        ArgumentNullException.ThrowIfNull(tenantProvider);
        ArgumentNullException.ThrowIfNull(timeProvider);

        _context = context;
        _paymentProviderGateway = paymentProviderGateway;
        _paymentTelemetryTracker = paymentTelemetryTracker;
        _logger = logger;
        _paymentProviderConfigurationResolver = paymentProviderConfigurationResolver;
        _paymentProvider = paymentProviderResolver.ResolveCurrentTenantProvider();
        _tenantProvider = tenantProvider;
        _timeProvider = timeProvider;

        if (!string.Equals(_paymentProvider.ProviderType, _paymentProviderGateway.ProviderType, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(
                $"Configured payment provider '{_paymentProvider.ProviderType}' does not match the registered gateway '{_paymentProviderGateway.ProviderType}' for tenant payment reconciliation.");
        }
    }

    public async Task<Result<PaymentStatusDetailsDto>> HandleAsync(ConfirmPaymentStatusCommand command, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(command);

        if (string.IsNullOrWhiteSpace(command.PaymentId))
        {
            return Error.Create("Validation", "PaymentId is required.");
        }

        var payinLog = await _context.PayinLogs
            .OrderByDescending(item => item.Id)
            .FirstOrDefaultAsync(
                item => item.OpenPayChargeId == command.PaymentId
                    || (!string.IsNullOrWhiteSpace(command.AttemptOrderId) && item.AttemptOrderId == command.AttemptOrderId),
                cancellationToken);

        if (payinLog is null && !string.IsNullOrWhiteSpace(command.AttemptOrderId))
        {
            payinLog = await _context.PayinLogs
                .OrderByDescending(item => item.Id)
                .FirstOrDefaultAsync(
                    item => item.OpenPayChargeId == command.AttemptOrderId,
                    cancellationToken);
        }

        var localAttemptOrderId = FirstNonEmpty(payinLog?.AttemptOrderId, command.AttemptOrderId);

        _logger.LogInformation(
            "Reconciling payment callback for payment {PaymentId}, callback order {CallbackOrderId}, and local attempt order {LocalAttemptOrderId}",
            command.PaymentId,
            command.AttemptOrderId,
            localAttemptOrderId);

        var transaction = await _context.CardTransactions
            .OrderByDescending(item => item.Id)
            .FirstOrDefaultAsync(
                item => item.TransactionId == command.PaymentId
                    || (!string.IsNullOrWhiteSpace(command.AttemptOrderId) && item.TransactionId == command.AttemptOrderId)
                    || (!string.IsNullOrWhiteSpace(localAttemptOrderId) && item.AttemptOrderId == localAttemptOrderId),
                cancellationToken);

        if (transaction is null)
        {
            _logger.LogWarning(
                "No local CardTransaction was found for payment {PaymentId}, callback order {CallbackOrderId}, and local attempt order {LocalAttemptOrderId}",
                command.PaymentId,
                command.AttemptOrderId,
                localAttemptOrderId);

            return Error.NotFound;
        }

        PaymentGatewayChargeResult? remoteCharge = null;
        var remoteStatusConfirmed = false;
        var callbackPayloadReceived = (command.CallbackParameters?.Count ?? 0) > 0
            || !string.IsNullOrWhiteSpace(command.CallbackStatus)
            || !string.IsNullOrWhiteSpace(command.ErrorMessage);

        try
        {
            remoteCharge = await _paymentProviderGateway.GetChargeAsync(command.PaymentId, transaction.TransactionCustomerId, cancellationToken);
            remoteStatusConfirmed = true;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Remote {PaymentProviderName} status lookup failed for payment {PaymentId}", _paymentProvider.Name, command.PaymentId);
        }

        var resolvedStatus = NormalizeStatus(remoteCharge?.Status)
            ?? NormalizeStatus(command.CallbackStatus)
            ?? InferStatusFromCallbackError(command.ErrorMessage)
            ?? NormalizeStatus(transaction.TransactionStatus)
            ?? "unknown";

        var resolvedErrorMessage = FirstNonEmpty(
            remoteCharge?.ErrorMessage,
            command.ErrorMessage,
            transaction.TransactionMessage);
        var resolvedThreeDSecureStage = ResolveThreeDSecureStage(
            resolvedStatus,
            transaction.IsThreeDSecureEnabled,
            callbackPayloadReceived,
            remoteStatusConfirmed);

        var signatureValidationError = ValidateRazorpaySignatureIfRequired(command, transaction, payinLog, resolvedStatus);
        if (signatureValidationError is not null)
        {
            return signatureValidationError;
        }

        var now = _timeProvider.GetUtcNow().UtcDateTime;
        var callbackRecorded = await ReconcilePersistenceAsync(
            command,
            transaction,
            payinLog,
            remoteCharge,
            remoteStatusConfirmed,
            callbackPayloadReceived,
            resolvedStatus,
            resolvedThreeDSecureStage,
            resolvedErrorMessage,
            now,
            cancellationToken);

        _logger.LogInformation(
            "Payment callback reconciliation completed for payment {PaymentId}. Status {Status}, remote confirmed: {RemoteStatusConfirmed}, callback recorded: {CallbackRecorded}",
            command.PaymentId,
            resolvedStatus,
            remoteStatusConfirmed,
            callbackRecorded);

        var paymentStatusDetails = new PaymentStatusDetailsDto
        {
            PaymentId = command.PaymentId,
            CustomerOrderId = transaction.CustomerOrderId,
            Status = resolvedStatus,
            StatusCategory = EnumHelper.ToStatusCategory(resolvedStatus),
            StatusMessage = EnumHelper.ToStatusMessage(resolvedStatus, remoteStatusConfirmed, _paymentProvider.Name),
            IsSuccess = EnumHelper.IsSuccessStatus(resolvedStatus),
            IsPending = EnumHelper.IsPendingStatus(resolvedStatus),
            IsFailure = EnumHelper.IsFailureStatus(resolvedStatus),
            IsFinal = EnumHelper.IsFinalStatus(resolvedStatus),
            CallbackRecorded = callbackRecorded,
            RemoteStatusConfirmed = remoteStatusConfirmed,
            StatusSource = remoteStatusConfirmed ? ResolveStatusSource(_paymentProvider.ProviderType) : "database",
            ErrorMessage = resolvedErrorMessage,
            TransactionReferenceId = FirstNonEmpty(remoteCharge?.Authorization, transaction.TransactionReferenceId),
            TransactionDate = NormalizeToUtc(remoteCharge?.CreatedAt) ?? transaction.TransactionDate,
            ThreeDSecureUrl = FirstNonEmpty(remoteCharge?.RedirectUrl, transaction.RedirectUrl),
            IsThreeDSecureEnabled = transaction.IsThreeDSecureEnabled,
            ThreeDSecureStage = resolvedThreeDSecureStage
        };

        _paymentTelemetryTracker.Track(new PaymentTelemetryEvent
        {
            EventName = PaymentTelemetryEventNames.CallbackReconciled,
            TenantCode = _tenantProvider.TenantCode,
            CustomerOrderId = transaction.CustomerOrderId,
            AttemptOrderId = FirstNonEmpty(command.AttemptOrderId, transaction.AttemptOrderId),
            PaymentId = command.PaymentId,
            PaymentTraceId = transaction.PaymentTraceId,
            ProviderType = _paymentProvider.ProviderType,
            PaymentStatus = paymentStatusDetails.Status,
            StatusCategory = paymentStatusDetails.StatusCategory,
            StatusSource = paymentStatusDetails.StatusSource,
            ThreeDSecureStage = paymentStatusDetails.ThreeDSecureStage,
            RemoteStatusConfirmed = remoteStatusConfirmed,
            CallbackRecorded = callbackRecorded,
            IsThreeDSecureEnabled = paymentStatusDetails.IsThreeDSecureEnabled,
            ErrorMessage = paymentStatusDetails.ErrorMessage,
        });

        return paymentStatusDetails;
    }

    private Result<PaymentStatusDetailsDto>? ValidateRazorpaySignatureIfRequired(
        ConfirmPaymentStatusCommand command,
        Domain.Entities.CardTransaction transaction,
        Domain.Entities.PayinLog? payinLog,
        string resolvedStatus)
    {
        if (!string.Equals(_paymentProvider.ProviderType, PaymentProviderTypes.Razorpay, StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        if (!EnumHelper.IsSuccessStatus(resolvedStatus))
        {
            return null;
        }

        if (command.CallbackParameters is null || !HasAnyCallbackValue(command.CallbackParameters, "razorpay_payment_id", "razorpay_order_id", "razorpay_signature"))
        {
            return null;
        }

        var callbackSignature = GetCallbackValue(command.CallbackParameters, "razorpay_signature");
        if (string.IsNullOrWhiteSpace(callbackSignature))
        {
            return Error.Create("Validation", "Razorpay signature is required for successful payment confirmation.");
        }

        var storedOrderId = ResolveStoredRazorpayOrderId(transaction, payinLog);
        if (string.IsNullOrWhiteSpace(storedOrderId))
        {
            return Error.Create("Validation", "Stored Razorpay order id is unavailable for signature verification.");
        }

        var callbackOrderId = GetCallbackValue(command.CallbackParameters, "razorpay_order_id");
        if (!string.IsNullOrWhiteSpace(callbackOrderId)
            && !string.Equals(callbackOrderId, storedOrderId, StringComparison.Ordinal))
        {
            return Error.Create("Validation", "Razorpay callback order id does not match the stored order id.");
        }

        var providerConfiguration = _paymentProviderConfigurationResolver.ResolveCurrentTenantConfiguration();
        var generatedSignature = ComputeRazorpaySignature(storedOrderId, command.PaymentId, providerConfiguration.PrivateKey);
        if (!FixedTimeEquals(generatedSignature, callbackSignature))
        {
            return Error.Create("Validation", "Razorpay signature verification failed.");
        }

        return null;
    }

    private async Task<bool> ReconcilePersistenceAsync(
        ConfirmPaymentStatusCommand command,
        Domain.Entities.CardTransaction transaction,
        Domain.Entities.PayinLog? payinLog,
        PaymentGatewayChargeResult? remoteCharge,
        bool remoteStatusConfirmed,
        bool callbackPayloadReceived,
        string resolvedStatus,
        string resolvedThreeDSecureStage,
        string? resolvedErrorMessage,
        DateTime now,
        CancellationToken cancellationToken)
    {
        var shouldWriteAuditRecord = callbackPayloadReceived || remoteStatusConfirmed;
        if (!shouldWriteAuditRecord)
        {
            return false;
        }

        var isDirectStatusEntry = IsDirectStatusEntry(command.CallbackParameters);
        var shouldRecordCallbackStage = callbackPayloadReceived
            && transaction.IsThreeDSecureEnabled
            && !isDirectStatusEntry;
        var callbackStage = EnumHelper.GetEnumDescription(ThreeDSecureStage.CallbackReceived);
        var callbackStatus = NormalizeStatus(command.CallbackStatus)
            ?? InferStatusFromCallbackError(command.ErrorMessage)
            ?? transaction.TransactionStatus;
        var callbackMatchesResolvedStage = shouldRecordCallbackStage
            && string.Equals(callbackStage, resolvedThreeDSecureStage, StringComparison.OrdinalIgnoreCase)
            && string.Equals(callbackStatus, resolvedStatus, StringComparison.OrdinalIgnoreCase);

        var existingHistoryEntries = await _context.TransactionStatusHistories
            .Where(item => item.TransactionId == transaction.Id)
            .ToListAsync(cancellationToken);

        var callbackHistoryExists = shouldRecordCallbackStage
            && HasHistoryEntry(existingHistoryEntries, transaction.AttemptOrderId, callbackStatus, callbackStage);
        var resolvedHistoryExists = HasHistoryEntry(
            existingHistoryEntries,
            transaction.AttemptOrderId,
            resolvedStatus,
            resolvedThreeDSecureStage);
        var attemptOrderId = FirstNonEmpty(payinLog?.AttemptOrderId, command.AttemptOrderId, transaction.AttemptOrderId);
        var paymentAttempt = !string.IsNullOrWhiteSpace(attemptOrderId)
            ? await _context.PaymentAttempts
                .FirstOrDefaultAsync(item => item.AttemptOrderId == attemptOrderId, cancellationToken)
            : null;
        var paymentAttemptHistories = paymentAttempt is not null
            ? await _context.PaymentAttemptHistories
                .Where(item => item.PaymentAttemptId == paymentAttempt.Id)
                .ToListAsync(cancellationToken)
            : [];
        var resolvedAttemptStatus = ResolvePaymentAttemptStatus(resolvedStatus, remoteStatusConfirmed);
        var auditMessage = BuildAuditMessage(command, remoteCharge, resolvedStatus, resolvedThreeDSecureStage, transaction.PaymentTraceId, _paymentProvider.Name);
        var transactionStatusHistoryNotes = TruncateForPersistence(auditMessage, TransactionStatusHistoryNotesMaxLength);
        var paymentAttemptHistoryNotes = TruncateForPersistence(auditMessage, PaymentAttemptHistoryNotesMaxLength);
        var paymentAttemptHistoryExists = paymentAttempt is not null
            && HasPaymentAttemptHistoryEntry(paymentAttemptHistories, resolvedAttemptStatus, resolvedStatus);

        transaction.TransactionStatus = resolvedStatus;
        transaction.IsTransactionSuccess = EnumHelper.IsSuccessStatus(resolvedStatus);
        transaction.TransactionMessage = resolvedErrorMessage ?? auditMessage;
        transaction.TransactionReferenceId = FirstNonEmpty(remoteCharge?.Authorization, transaction.TransactionReferenceId);
        transaction.TransactionDate = NormalizeToUtc(remoteCharge?.CreatedAt) ?? transaction.TransactionDate;
        transaction.RedirectUrl = FirstNonEmpty(remoteCharge?.RedirectUrl, transaction.RedirectUrl);
        transaction.ThreeDSecureStage = resolvedThreeDSecureStage;
        transaction.UpdatedBy = transaction.BillingCustomerId;
        transaction.UpdatedDate = now;

        var callbackHistoryAdded = false;
        if (shouldRecordCallbackStage && !callbackHistoryExists)
        {
            _context.TransactionStatusHistories.Add(new Domain.Entities.TransactionStatusHistory
            {
                TransactionId = transaction.Id,
                AttemptOrderId = transaction.AttemptOrderId,
                Status = callbackStatus,
                Notes = TruncateForPersistence($"Browser callback payload received for trace {transaction.PaymentTraceId}", TransactionStatusHistoryNotesMaxLength),
                PaymentTraceId = transaction.PaymentTraceId,
                ThreeDSecureStage = callbackStage,
                IsThreeDSecureEnabled = transaction.IsThreeDSecureEnabled,
                TransactionReferenceId = transaction.TransactionReferenceId,
                CreatedBy = transaction.BillingCustomerId,
                CreatedDate = now
            });

            callbackHistoryAdded = true;
        }

        var resolvedHistoryAdded = false;
        if (!resolvedHistoryExists && !callbackMatchesResolvedStage)
        {
            _context.TransactionStatusHistories.Add(new Domain.Entities.TransactionStatusHistory
            {
                TransactionId = transaction.Id,
                AttemptOrderId = transaction.AttemptOrderId,
                Status = resolvedStatus,
                Notes = transactionStatusHistoryNotes,
                PaymentTraceId = transaction.PaymentTraceId,
                ThreeDSecureStage = resolvedThreeDSecureStage,
                IsThreeDSecureEnabled = transaction.IsThreeDSecureEnabled,
                TransactionReferenceId = transaction.TransactionReferenceId,
                CreatedBy = transaction.BillingCustomerId,
                CreatedDate = now
            });

            resolvedHistoryAdded = true;
        }

        var finalAuditRecorded = resolvedHistoryAdded || (callbackHistoryAdded && callbackMatchesResolvedStage);

        if (paymentAttempt is not null)
        {
            paymentAttempt.Status = resolvedAttemptStatus;
            paymentAttempt.ProviderStatus = resolvedStatus;
            paymentAttempt.ProviderChargeId = FirstNonEmpty(remoteCharge?.Id, paymentAttempt.ProviderChargeId, command.PaymentId);
            paymentAttempt.ProviderReferenceId = FirstNonEmpty(remoteCharge?.Authorization, paymentAttempt.ProviderReferenceId);
            paymentAttempt.LastErrorMessage = TruncateForPersistence(resolvedErrorMessage, PaymentAttemptLastErrorMaxLength);
            paymentAttempt.UpdatedDate = now;

            if (!paymentAttemptHistoryExists)
            {
                _context.PaymentAttemptHistories.Add(new Domain.Entities.PaymentAttemptHistory
                {
                    PaymentAttemptId = paymentAttempt.Id,
                    AttemptOrderId = paymentAttempt.AttemptOrderId,
                    Status = resolvedAttemptStatus,
                    PaymentTraceId = paymentAttempt.PaymentTraceId,
                    ProviderStatus = resolvedStatus,
                    Notes = paymentAttemptHistoryNotes,
                    TenantId = paymentAttempt.TenantId,
                    CreatedDate = now,
                });
            }
        }

        if (payinLog is not null)
        {
            payinLog.PaymentTraceId = transaction.PaymentTraceId;
            payinLog.Result = EnumHelper.GetEnumIdFromDescription<PaymentStatus>(resolvedStatus) ?? (int)PaymentStatus.Unknown;
            payinLog.AmountFromAPI = remoteCharge?.Amount ?? payinLog.AmountFromAPI;
            payinLog.OpenPayAuthorizationId = FirstNonEmpty(remoteCharge?.Authorization, payinLog.OpenPayAuthorizationId);
            payinLog.IsThreeDSecureEnabled = transaction.IsThreeDSecureEnabled;
            payinLog.ThreeDSecureStage = resolvedThreeDSecureStage;
            payinLog.UpdatedBy = transaction.BillingCustomerId;
            payinLog.UpdatedDate = now;

            if (finalAuditRecorded)
            {
                _context.PayinLogDetails.Add(new Domain.Entities.PayinLogDetails
                {
                    PayinLogId = payinLog.Id,
                    PostInfo = callbackPayloadReceived ? JsonSerializer.Serialize(command.CallbackParameters) : null,
                    RespInfo = remoteCharge is not null ? JsonSerializer.Serialize(remoteCharge) : null,
                    AdditionalInfo = auditMessage,
                    PaymentTraceId = transaction.PaymentTraceId,
                    ThreeDSecureStage = resolvedThreeDSecureStage,
                    CreatedBy = transaction.BillingCustomerId,
                    CreatedDate = now
                });
            }
        }

        await _context.SaveChangesAsync(cancellationToken);
        return shouldRecordCallbackStage && (callbackHistoryExists || callbackHistoryAdded);
    }

    private static string BuildAuditMessage(ConfirmPaymentStatusCommand command, PaymentGatewayChargeResult? remoteCharge, string resolvedStatus, string resolvedThreeDSecureStage, string paymentTraceId, string providerDisplayName)
    {
        var messageParts = new List<string>
        {
            $"PaymentTraceId '{paymentTraceId}'",
            $"callback processed with resolved status '{resolvedStatus}'",
            $"3DS stage '{resolvedThreeDSecureStage}'"
        };

        if (!string.IsNullOrWhiteSpace(command.CallbackStatus))
        {
            messageParts.Add($"callback status '{command.CallbackStatus}'");
        }

        if (!string.IsNullOrWhiteSpace(remoteCharge?.Status))
        {
            messageParts.Add($"{providerDisplayName} status '{remoteCharge.Status}'");
        }

        if (!string.IsNullOrWhiteSpace(command.ErrorMessage))
        {
            messageParts.Add($"callback message '{command.ErrorMessage}'");
        }

        if (!string.IsNullOrWhiteSpace(remoteCharge?.ErrorMessage))
        {
            messageParts.Add($"{providerDisplayName} message '{remoteCharge.ErrorMessage}'");
        }

        return string.Join("; ", messageParts);
    }

    private static string? NormalizeStatus(string? status)
        => EnumHelper.NormalizeOpenPayStatus(status);

    private static string? InferStatusFromCallbackError(string? errorMessage)
    {
        return string.IsNullOrWhiteSpace(errorMessage)
            ? null
            : EnumHelper.GetEnumDescription(PaymentStatus.Failed);
    }

    private static string? FirstNonEmpty(params string?[] values)
    {
        return values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value));
    }

    private static string? GetCallbackValue(IReadOnlyDictionary<string, string>? callbackParameters, params string[] keys)
    {
        if (callbackParameters is null)
        {
            return null;
        }

        foreach (var key in keys)
        {
            if (callbackParameters.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value))
            {
                return value;
            }
        }

        return null;
    }

    private static bool HasAnyCallbackValue(IReadOnlyDictionary<string, string>? callbackParameters, params string[] keys)
    {
        return GetCallbackValue(callbackParameters, keys) is not null;
    }

    private static string? ResolveStoredRazorpayOrderId(Domain.Entities.CardTransaction transaction, Domain.Entities.PayinLog? payinLog)
    {
        foreach (var candidate in new[] { payinLog?.OpenPayChargeId, transaction.TransactionId })
        {
            if (!string.IsNullOrWhiteSpace(candidate)
                && candidate.StartsWith("order_", StringComparison.OrdinalIgnoreCase))
            {
                return candidate;
            }
        }

        return null;
    }

    private static string ComputeRazorpaySignature(string orderId, string paymentId, string secret)
    {
        var payload = $"{orderId}|{paymentId}";
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(secret));
        var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(payload));
        return Convert.ToHexString(hash);
    }

    private static bool FixedTimeEquals(string expectedSignature, string actualSignature)
    {
        var expectedBytes = Encoding.UTF8.GetBytes(expectedSignature.Trim().ToUpperInvariant());
        var actualBytes = Encoding.UTF8.GetBytes(actualSignature.Trim().ToUpperInvariant());

        return expectedBytes.Length == actualBytes.Length
            && CryptographicOperations.FixedTimeEquals(expectedBytes, actualBytes);
    }

    private static string? TruncateForPersistence(string? value, int maxLength)
    {
        if (string.IsNullOrEmpty(value) || value.Length <= maxLength)
        {
            return value;
        }

        return value[..maxLength];
    }

    private static string ResolveStatusSource(string providerType)
    {
        if (string.Equals(providerType, PaymentProviderTypes.OpenPay, StringComparison.OrdinalIgnoreCase))
        {
            return "openpay";
        }

        return providerType;
    }

    private static string ResolveThreeDSecureStage(string resolvedStatus, bool isThreeDSecureEnabled, bool callbackPayloadReceived, bool remoteStatusConfirmed)
    {
        if (!isThreeDSecureEnabled)
            return EnumHelper.GetEnumDescription(ThreeDSecureStage.NotApplicable);

        if (EnumHelper.IsSuccessStatus(resolvedStatus))
            return EnumHelper.GetEnumDescription(ThreeDSecureStage.Completed);

        if (EnumHelper.IsFailedStatus(resolvedStatus))
            return EnumHelper.GetEnumDescription(ThreeDSecureStage.Failed);

        if (EnumHelper.IsCancelledStatus(resolvedStatus))
            return EnumHelper.GetEnumDescription(ThreeDSecureStage.Cancelled);

        if (remoteStatusConfirmed && EnumHelper.IsPendingStatus(resolvedStatus))
            return EnumHelper.GetEnumDescription(ThreeDSecureStage.PendingConfirmation);

        if (callbackPayloadReceived)
            return EnumHelper.GetEnumDescription(ThreeDSecureStage.CallbackReceived);

        return EnumHelper.GetEnumDescription(ThreeDSecureStage.Unknown);
    }

    private static bool HasHistoryEntry(
        IEnumerable<Domain.Entities.TransactionStatusHistory> historyEntries,
        string? attemptOrderId,
        string status,
        string stage)
    {
        return historyEntries.Any(entry =>
            string.Equals(entry.AttemptOrderId, attemptOrderId, StringComparison.OrdinalIgnoreCase)
            && string.Equals(entry.Status, status, StringComparison.OrdinalIgnoreCase)
            && string.Equals(entry.ThreeDSecureStage, stage, StringComparison.OrdinalIgnoreCase));
    }

    private static bool HasPaymentAttemptHistoryEntry(
        IEnumerable<Domain.Entities.PaymentAttemptHistory> historyEntries,
        PaymentAttemptStatus status,
        string providerStatus)
    {
        return historyEntries.Any(entry =>
            entry.Status == status
            && string.Equals(entry.ProviderStatus, providerStatus, StringComparison.OrdinalIgnoreCase));
    }

    private static PaymentAttemptStatus ResolvePaymentAttemptStatus(string resolvedStatus, bool remoteStatusConfirmed)
    {
        if (EnumHelper.IsSuccessStatus(resolvedStatus))
        {
            return PaymentAttemptStatus.Succeeded;
        }

        if (EnumHelper.IsFailureStatus(resolvedStatus) || EnumHelper.IsCancelledStatus(resolvedStatus))
        {
            return PaymentAttemptStatus.Failed;
        }

        if (remoteStatusConfirmed && EnumHelper.IsPendingStatus(resolvedStatus))
        {
            return PaymentAttemptStatus.ProviderAccepted;
        }

        return PaymentAttemptStatus.UnknownNeedsReconciliation;
    }

    private static bool IsDirectStatusEntry(IReadOnlyDictionary<string, string>? callbackParameters)
    {
        if (callbackParameters is null)
        {
            return false;
        }

        return callbackParameters.TryGetValue("source", out var source)
            && string.Equals(source, "direct", StringComparison.OrdinalIgnoreCase);
    }

    private static DateTime? NormalizeToUtc(DateTime? dateTime)
    {
        if (!dateTime.HasValue) return null;
        return dateTime.Value.Kind == DateTimeKind.Utc
            ? dateTime.Value
            : DateTime.SpecifyKind(dateTime.Value, DateTimeKind.Local).ToUniversalTime();
    }
}