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
            StatusCategory = ToStatusCategory(resolvedStatus),
            StatusMessage = ToStatusMessage(resolvedStatus, remoteStatusConfirmed),
            IsSuccess = IsSuccessStatus(resolvedStatus),
            IsPending = IsPendingStatus(resolvedStatus),
            IsFailure = IsFailureStatus(resolvedStatus),
            IsFinal = IsFinalStatus(resolvedStatus),
            CallbackRecorded = callbackRecorded,
            RemoteStatusConfirmed = remoteStatusConfirmed,
            StatusSource = remoteStatusConfirmed ? "openpay" : "database",
            ErrorMessage = resolvedErrorMessage,
            TransactionReferenceId = FirstNonEmpty(remoteCharge?.Authorization, transaction.TransactionReferenceId),
            TransactionDate = remoteCharge?.CreationDate ?? transaction.TransactionDate,
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

        transaction.TransactionStatus = resolvedStatus;
        transaction.IsTransactionSuccess = IsSuccessStatus(resolvedStatus);
        transaction.TransactionMessage = resolvedErrorMessage ?? BuildAuditMessage(command, remoteCharge, resolvedStatus, resolvedThreeDSecureStage, transaction.PaymentTraceId);
        transaction.TransactionReferenceId = FirstNonEmpty(remoteCharge?.Authorization, transaction.TransactionReferenceId);
        transaction.TransactionDate = remoteCharge?.CreationDate ?? transaction.TransactionDate;
        transaction.RedirectUrl = FirstNonEmpty(remoteCharge?.PaymentMethod?.Url, transaction.RedirectUrl);
        transaction.ThreeDSecureStage = resolvedThreeDSecureStage;
        transaction.UpdatedBy = transaction.CustomerId;
        transaction.UpdatedDate = now;

        if (callbackPayloadReceived)
        {
            _context.TransactionStatusHistories.Add(new Domain.Entities.TransactionStatusHistory
            {
                TransactionId = transaction.Id,
                AttemptOrderId = transaction.AttemptOrderId,
                Status = NormalizeStatus(command.CallbackStatus) ?? transaction.TransactionStatus,
                Notes = $"Browser callback payload received for trace {transaction.PaymentTraceId}",
                PaymentTraceId = transaction.PaymentTraceId,
                ThreeDSecureStage = EnumHelper.GetEnumDescription(ThreeDSecureStage.CallbackReceived),
                CreatedBy = transaction.CustomerId,
                CreatedDate = now
            });
        }

        _context.TransactionStatusHistories.Add(new Domain.Entities.TransactionStatusHistory
        {
            TransactionId = transaction.Id,
            AttemptOrderId = transaction.AttemptOrderId,
            Status = resolvedStatus,
            Notes = BuildAuditMessage(command, remoteCharge, resolvedStatus, resolvedThreeDSecureStage, transaction.PaymentTraceId),
            PaymentTraceId = transaction.PaymentTraceId,
            ThreeDSecureStage = resolvedThreeDSecureStage,
            CreatedBy = transaction.CustomerId,
            CreatedDate = now
        });

        if (payinLog is not null)
        {
            payinLog.PaymentTraceId = transaction.PaymentTraceId;
            payinLog.Result = EnumHelper.GetEnumIdFromDescription<PaymentStatus>(resolvedStatus) ?? (int)PaymentStatus.Unknown;
            payinLog.AmountFromAPI = remoteCharge?.Amount ?? payinLog.AmountFromAPI;
            payinLog.OpenPayAuthorizationId = FirstNonEmpty(remoteCharge?.Authorization, payinLog.OpenPayAuthorizationId);
            payinLog.IsThreeDSecureEnabled = transaction.IsThreeDSecureEnabled;
            payinLog.ThreeDSecureStage = resolvedThreeDSecureStage;
            payinLog.UpdatedBy = transaction.CustomerId;
            payinLog.UpdatedDate = now;

            _context.PayinLogDetails.Add(new Domain.Entities.PayinLogDetails
            {
                PayinLogId = payinLog.Id,
                PostInfo = callbackPayloadReceived ? JsonSerializer.Serialize(command.CallbackParameters) : null,
                RespInfo = remoteCharge is not null ? JsonSerializer.Serialize(remoteCharge) : null,
                AdditionalInfo = BuildAuditMessage(command, remoteCharge, resolvedStatus, resolvedThreeDSecureStage, transaction.PaymentTraceId),
                PaymentTraceId = transaction.PaymentTraceId,
                ThreeDSecureStage = resolvedThreeDSecureStage,
                CreatedBy = transaction.CustomerId,
                CreatedDate = now
            });
        }

        await _context.SaveChangesAsync(cancellationToken);
        return true;
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
    {
        if (string.IsNullOrWhiteSpace(status))
        {
            return null;
        }

        var normalizedStatus = status.Trim().ToUpperInvariant();

        return normalizedStatus switch
        {
            "COMPLETED" or "SUCCESS" or "PAID" => "completed",
            "CHARGE_PENDING" or "PENDING" or "IN_PROGRESS" => "charge_pending",
            "FAILED" or "DECLINED" or "ERROR" => "failed",
            "CANCELLED" or "CANCELED" => "cancelled",
            _ => normalizedStatus
        };
    }

    private static string ToStatusCategory(string status)
    {
        return status switch
        {
            "completed" => "success",
            "charge_pending" => "warning",
            "failed" => "danger",
            "cancelled" => "secondary",
            _ => "info"
        };
    }

    private static string ToStatusMessage(string status, bool remoteStatusConfirmed)
    {
        return status switch
        {
            "completed" => remoteStatusConfirmed
                ? "Payment completed successfully and the final status was confirmed with OpenPay."
                : "Payment completed successfully based on the latest local record.",
            "charge_pending" => remoteStatusConfirmed
                ? "Payment is still pending issuer or 3D Secure completion according to OpenPay."
                : "Payment is still pending confirmation based on the latest local record.",
            "failed" => remoteStatusConfirmed
                ? "Payment failed and the final status was confirmed with OpenPay."
                : "Payment failed based on the latest local record.",
            "cancelled" => remoteStatusConfirmed
                ? "Payment was cancelled and the final status was confirmed with OpenPay."
                : "Payment was cancelled based on the latest local record.",
            _ => remoteStatusConfirmed
                ? "Payment callback was received, but OpenPay returned a status that is not explicitly mapped yet."
                : "Payment callback was received, but the final status could not be confirmed remotely."
        };
    }

    private static bool IsSuccessStatus(string status) => string.Equals(status, "completed", StringComparison.Ordinal);

    private static bool IsPendingStatus(string status)
        => string.Equals(status, "charge_pending", StringComparison.Ordinal)
            || string.Equals(status, "pending", StringComparison.Ordinal);

    private static bool IsFailureStatus(string status)
        => string.Equals(status, "failed", StringComparison.Ordinal)
            || string.Equals(status, "cancelled", StringComparison.Ordinal);

    private static bool IsFinalStatus(string status) => IsSuccessStatus(status) || IsFailureStatus(status);

    private static string? FirstNonEmpty(params string?[] values)
    {
        return values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value));
    }

    private static string ResolveThreeDSecureStage(string resolvedStatus, bool isThreeDSecureEnabled, bool callbackPayloadReceived, bool remoteStatusConfirmed)
    {
        if (!isThreeDSecureEnabled)
        {
            return EnumHelper.GetEnumDescription(ThreeDSecureStage.NotApplicable);
        }

        if (IsSuccessStatus(resolvedStatus))
        {
            return EnumHelper.GetEnumDescription(ThreeDSecureStage.Completed);
        }

        if (string.Equals(resolvedStatus, "failed", StringComparison.Ordinal))
        {
            return EnumHelper.GetEnumDescription(ThreeDSecureStage.Failed);
        }

        if (string.Equals(resolvedStatus, "cancelled", StringComparison.Ordinal))
        {
            return EnumHelper.GetEnumDescription(ThreeDSecureStage.Cancelled);
        }

        if (remoteStatusConfirmed && IsPendingStatus(resolvedStatus))
        {
            return EnumHelper.GetEnumDescription(ThreeDSecureStage.PendingConfirmation);
        }

        if (callbackPayloadReceived)
        {
            return EnumHelper.GetEnumDescription(ThreeDSecureStage.CallbackReceived);
        }

        return EnumHelper.GetEnumDescription(ThreeDSecureStage.Unknown);
    }
}