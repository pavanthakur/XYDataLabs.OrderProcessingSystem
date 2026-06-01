using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Events;

public class PaymentReconciliationWorker : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<PaymentReconciliationWorker> _logger;

    public PaymentReconciliationWorker(IServiceProvider serviceProvider, ILogger<PaymentReconciliationWorker> logger)
    {
        _serviceProvider = serviceProvider;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await ReconcilePaymentsAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "An error occurred while reconciling payments.");
            }

            // Run reconciliation every 60 seconds
            await Task.Delay(TimeSpan.FromSeconds(60), stoppingToken);
        }
    }

    private async Task ReconcilePaymentsAsync(CancellationToken cancellationToken)
    {
        using var registryScope = _serviceProvider.CreateScope();
        var tenantRegistryContext = registryScope.ServiceProvider.GetRequiredService<TenantRegistryDbContext>();
        var tenantResolver = registryScope.ServiceProvider.GetRequiredService<ITenantResolver>();
        var tenantCodes = await tenantRegistryContext.Tenants
            .AsNoTracking()
            .OrderBy(tenant => tenant.Id)
            .Select(tenant => tenant.Code)
            .ToListAsync(cancellationToken);

        if (tenantCodes.Count == 0)
        {
            return;
        }

        foreach (var tenantCode in tenantCodes)
        {
            var tenantContext = await tenantResolver.ResolveTenantAsync(tenantCode, cancellationToken);
            if (tenantContext is null)
            {
                _logger.LogWarning("Skipping payment reconciliation for tenant code {TenantCode} because tenant resolution failed.", tenantCode);
                continue;
            }

            try
            {
                await ProcessTenantPaymentsAsync(tenantContext, cancellationToken);
            }
            catch (Exception ex)
            {
                // Isolate per-tenant failures so a misconfigured dedicated tenant
                // cannot block reconciliation for all remaining tenants in the cycle.
                _logger.LogError(ex,
                    "Payment reconciliation failed for tenant {TenantCode} (Id={TenantId}). Skipping to next tenant.",
                    tenantCode, tenantContext.TenantId);
            }
        }
    }

    private async Task ProcessTenantPaymentsAsync(TenantContext tenantContext, CancellationToken cancellationToken)
    {
        using var tenantScope = _serviceProvider.CreateScope();
        var tenantContextAccessor = tenantScope.ServiceProvider.GetRequiredService<ScopedTenantContextAccessor>();
        tenantContextAccessor.Current = tenantContext;

        try
        {
            var dbContext = tenantScope.ServiceProvider.GetRequiredService<IAppDbContext>();

            // Polling attempts stuck in UnknownNeedsReconciliation state
            var stalledAttempts = await dbContext.PaymentAttempts
                .Where(x => x.Status == PaymentAttemptStatus.UnknownNeedsReconciliation && x.TenantId == tenantContext.TenantId)
                .OrderBy(x => x.CreatedDate)
                .Take(50)
                .ToListAsync(cancellationToken);

            if (stalledAttempts.Count == 0)
            {
                return;
            }

            // Resolve the payment gateway only when there are stalled attempts to
            // reconcile. This avoids throwing for tenants with no active provider
            // when there is nothing to reconcile.
            var paymentGateway = tenantScope.ServiceProvider.GetRequiredService<IPaymentProviderGateway>();

            foreach (var attempt in stalledAttempts)
            {
                _logger.LogInformation("Reconciling PaymentAttempt {AttemptId} for Order {AttemptOrderId}", attempt.Id, attempt.AttemptOrderId);

                try
                {
                    if (TryResolveChargeLookupId(paymentGateway, attempt, out var chargeLookupId, out var skipReason))
                    {
                        var charge = await paymentGateway.GetChargeAsync(chargeLookupId, cancellationToken: cancellationToken);

                        if (charge.Status == "completed")
                        {
                            attempt.Status = PaymentAttemptStatus.Succeeded;
                        }
                        else if (charge.Status == "failed")
                        {
                            attempt.Status = PaymentAttemptStatus.Failed;
                        }

                        attempt.ProviderStatus = charge.Status;
                        attempt.LastErrorMessage = "Reconciled successfully via Background Worker";
                    }
                    else if (!string.IsNullOrWhiteSpace(skipReason))
                    {
                        _logger.LogInformation(
                            "Skipping gateway reconciliation for attempt {AttemptOrderId}: {SkipReason}",
                            attempt.AttemptOrderId,
                            skipReason);

                        attempt.LastErrorMessage = skipReason;
                    }
                    else
                    {
                        _logger.LogWarning("Attempt {AttemptOrderId} has no ProviderChargeId. Cannot reconcile through the configured payment gateway lookup.", attempt.AttemptOrderId);
                        attempt.LastErrorMessage = "Missing ProviderChargeId for payment gateway lookup. Requires REST OrderId Search Implementation.";
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error calling {PaymentProviderType} gateway for Attempt {AttemptOrderId}", paymentGateway.ProviderType, attempt.AttemptOrderId);
                    attempt.LastErrorMessage = ex.Message.Length > 500 ? ex.Message.Substring(0, 500) : ex.Message;
                }
                finally
                {
                    attempt.UpdatedDate = DateTime.UtcNow;
                }
            }

            await dbContext.SaveChangesAsync(cancellationToken);
        }
        finally
        {
            tenantContextAccessor.Current = null;
        }
    }

    private static bool TryResolveChargeLookupId(
        IPaymentProviderGateway paymentGateway,
        PaymentAttempt attempt,
        out string chargeLookupId,
        out string? skipReason)
    {
        chargeLookupId = string.Empty;
        skipReason = null;

        if (string.IsNullOrWhiteSpace(attempt.ProviderChargeId))
        {
            return false;
        }

        if (!string.Equals(paymentGateway.ProviderType, PaymentProviderTypes.Razorpay, StringComparison.OrdinalIgnoreCase))
        {
            chargeLookupId = attempt.ProviderChargeId;
            return true;
        }

        if (attempt.ProviderChargeId.StartsWith("pay_", StringComparison.OrdinalIgnoreCase))
        {
            chargeLookupId = attempt.ProviderChargeId;
            return true;
        }

        skipReason = attempt.ProviderChargeId.StartsWith("order_", StringComparison.OrdinalIgnoreCase)
            ? "Razorpay reconciliation is waiting for the provider payment id from callback/webhook; the current order id cannot be used for charge lookup yet."
            : $"Razorpay reconciliation requires a payment id starting with 'pay_'. Current ProviderChargeId '{attempt.ProviderChargeId}' is not a valid charge lookup id.";

        return false;
    }
}
