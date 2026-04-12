using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Openpay.Entities;
using XYDataLabs.OpenPayAdapter;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Utilities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;
using static XYDataLabs.OrderProcessingSystem.Application.Utilities.AppMasterConstant;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Payments.Commands;

public sealed class ConfirmPaymentStatusCommandHandler : ICommandHandler<ConfirmPaymentStatusCommand, Result<PaymentStatusDetailsDto>>
{
    private readonly IAppDbContext _context;
    private readonly IOpenPayAdapterService _openPayAdapterService;
    private readonly ILogger<ConfirmPaymentStatusCommandHandler> _logger;
    private readonly TimeProvider _timeProvider;

    public ConfirmPaymentStatusCommandHandler(
        IAppDbContext context,
        IOpenPayAdapterService openPayAdapterService,
        ILogger<ConfirmPaymentStatusCommandHandler> logger,
        TimeProvider timeProvider)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(openPayAdapterService);
        ArgumentNullException.ThrowIfNull(logger);
        ArgumentNullException.ThrowIfNull(timeProvider);

        _context = context;
        _openPayAdapterService = openPayAdapterService;
        _logger = logger;
        _timeProvider = timeProvider;
    }

    public async Task<Result<PaymentStatusDetailsDto>> HandleAsync(ConfirmPaymentStatusCommand command, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(command);

        if (string.IsNullOrWhiteSpace(command.PaymentId))
        {
            return Error.Create("Validation", "PaymentId is required.");
        }

        _logger.LogInformation(
            "Reconciling payment callback for payment {PaymentId} and attempt order {AttemptOrderId}",
            command.PaymentId,
            command.AttemptOrderId);

        var transaction = await _context.CardTransactions
            .OrderByDescending(item => item.Id)
            .FirstOrDefaultAsync(
                item => item.TransactionId == command.PaymentId
                    || (!string.IsNullOrWhiteSpace(command.AttemptOrderId) && item.AttemptOrderId == command.AttemptOrderId),
                cancellationToken);

        if (transaction is null)
        {
            _logger.LogWarning(
                "No local CardTransaction was found for payment {PaymentId} and order {OrderId}",
                command.PaymentId,
                command.AttemptOrderId);

            return Error.NotFound;
        }

        var payinLog = await _context.PayinLogs
            .OrderByDescending(item => item.Id)
            .FirstOrDefaultAsync(
                item => item.OpenPayChargeId == command.PaymentId
                    || (!string.IsNullOrWhiteSpace(command.AttemptOrderId) && item.AttemptOrderId == command.AttemptOrderId),
                cancellationToken);

        Charge? remoteCharge = null;
        var remoteStatusConfirmed = false;
        var callbackPayloadReceived = (command.CallbackParameters?.Count ?? 0) > 0
            || !string.IsNullOrWhiteSpace(command.CallbackStatus)
            || !string.IsNullOrWhiteSpace(command.ErrorMessage);

        try
        {
            remoteCharge = await _openPayAdapterService.GetChargeAsync(command.PaymentId, transaction.TransactionCustomerId);
            remoteStatusConfirmed = true;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Remote OpenPay status lookup failed for payment {PaymentId}", command.PaymentId);
        }

        var resolvedStatus = NormalizeStatus(remoteCharge?.Status)
            ?? NormalizeStatus(command.CallbackStatus)
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

        return new PaymentStatusDetailsDto
        {
            PaymentId = command.PaymentId,
            CustomerOrderId = transaction.CustomerOrderId,
            Status = resolvedStatus,
            StatusCategory = EnumHelper.ToStatusCategory(resolvedStatus),
            StatusMessage = EnumHelper.ToStatusMessage(resolvedStatus, remoteStatusConfirmed),
            IsSuccess = EnumHelper.IsSuccessStatus(resolvedStatus),
            IsPending = EnumHelper.IsPendingStatus(resolvedStatus),
            IsFailure = EnumHelper.IsFailureStatus(resolvedStatus),
            IsFinal = EnumHelper.IsFinalStatus(resolvedStatus),
            CallbackRecorded = callbackRecorded,
            RemoteStatusConfirmed = remoteStatusConfirmed,
            StatusSource = remoteStatusConfirmed ? "openpay" : "database",
            ErrorMessage = resolvedErrorMessage,
            TransactionReferenceId = FirstNonEmpty(remoteCharge?.Authorization, transaction.TransactionReferenceId),
            TransactionDate = NormalizeToUtc(remoteCharge?.CreationDate) ?? transaction.TransactionDate,
            ThreeDSecureUrl = FirstNonEmpty(remoteCharge?.PaymentMethod?.Url, transaction.RedirectUrl),
            IsThreeDSecureEnabled = transaction.IsThreeDSecureEnabled,
            ThreeDSecureStage = resolvedThreeDSecureStage
        };
    }

    private async Task<bool> ReconcilePersistenceAsync(
        ConfirmPaymentStatusCommand command,
        Domain.Entities.CardTransaction transaction,
        Domain.Entities.PayinLog? payinLog,
        Charge? remoteCharge,
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
        var callbackStatus = NormalizeStatus(command.CallbackStatus) ?? transaction.TransactionStatus;
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

        transaction.TransactionStatus = resolvedStatus;
        transaction.IsTransactionSuccess = EnumHelper.IsSuccessStatus(resolvedStatus);
        transaction.TransactionMessage = resolvedErrorMessage ?? BuildAuditMessage(command, remoteCharge, resolvedStatus, resolvedThreeDSecureStage, transaction.PaymentTraceId);
        transaction.TransactionReferenceId = FirstNonEmpty(remoteCharge?.Authorization, transaction.TransactionReferenceId);
        transaction.TransactionDate = NormalizeToUtc(remoteCharge?.CreationDate) ?? transaction.TransactionDate;
        transaction.RedirectUrl = FirstNonEmpty(remoteCharge?.PaymentMethod?.Url, transaction.RedirectUrl);
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
                Notes = $"Browser callback payload received for trace {transaction.PaymentTraceId}",
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
                Notes = BuildAuditMessage(command, remoteCharge, resolvedStatus, resolvedThreeDSecureStage, transaction.PaymentTraceId),
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
                    AdditionalInfo = BuildAuditMessage(command, remoteCharge, resolvedStatus, resolvedThreeDSecureStage, transaction.PaymentTraceId),
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

    private static string BuildAuditMessage(ConfirmPaymentStatusCommand command, Charge? remoteCharge, string resolvedStatus, string resolvedThreeDSecureStage, string paymentTraceId)
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
            messageParts.Add($"OpenPay status '{remoteCharge.Status}'");
        }

        if (!string.IsNullOrWhiteSpace(command.ErrorMessage))
        {
            messageParts.Add($"callback message '{command.ErrorMessage}'");
        }

        if (!string.IsNullOrWhiteSpace(remoteCharge?.ErrorMessage))
        {
            messageParts.Add($"OpenPay message '{remoteCharge.ErrorMessage}'");
        }

        return string.Join("; ", messageParts);
    }

    private static string? NormalizeStatus(string? status)
        => EnumHelper.NormalizeOpenPayStatus(status);

    private static string? FirstNonEmpty(params string?[] values)
    {
        return values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value));
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