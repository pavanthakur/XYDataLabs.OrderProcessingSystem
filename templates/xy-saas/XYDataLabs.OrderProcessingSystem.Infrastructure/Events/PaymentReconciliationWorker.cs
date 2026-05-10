using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using XYDataLabs.OrderProcessingSystem.PaymentGateway;
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

            await ProcessTenantPaymentsAsync(tenantContext, cancellationToken);
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
            var paymentGatewayService = tenantScope.ServiceProvider.GetRequiredService<IPaymentGatewayService>();

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

            foreach (var attempt in stalledAttempts)
            {
                _logger.LogInformation("Reconciling PaymentAttempt {AttemptId} for Order {AttemptOrderId}", attempt.Id, attempt.AttemptOrderId);

                try
                {
                    if (!string.IsNullOrWhiteSpace(attempt.ProviderChargeId))
                    {
                        var charge = await paymentGatewayService.GetChargeAsync(attempt.ProviderChargeId);

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
                    else
                    {
                        _logger.LogWarning("Attempt {AttemptOrderId} has no ProviderChargeId. Cannot reconcile through the configured payment gateway lookup.", attempt.AttemptOrderId);
                        attempt.LastErrorMessage = "Missing ProviderChargeId for SDK Lookup. Requires REST OrderId Search Implementation.";
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error calling payment gateway adapter for Attempt {AttemptOrderId}", attempt.AttemptOrderId);
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
}
