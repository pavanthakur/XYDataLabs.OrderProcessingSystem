using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using XYDataLabs.OpenPayAdapter;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

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
        // Create a scope to resolve scoped EF context and Tenant Provider correctly
        using var scope = _serviceProvider.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<IAppDbContext>();
        
        // Polling attempts stuck in UnknownNeedsReconciliation state
        var stalledAttempts = await dbContext.PaymentAttempts
            .Where(x => x.Status == PaymentAttemptStatus.UnknownNeedsReconciliation)
            .OrderBy(x => x.CreatedDate)
            .Take(50)
            .ToListAsync(cancellationToken);

        if (stalledAttempts.Count == 0)
        {
            return;
        }

        var openPayService = scope.ServiceProvider.GetRequiredService<IOpenPayAdapterService>();

        foreach (var attempt in stalledAttempts)
        {
            _logger.LogInformation("Reconciling PaymentAttempt {AttemptId} for Order {AttemptOrderId}", attempt.Id, attempt.AttemptOrderId);

            try
            {
                // In OpenPay, if we managed to get the ProviderChargeId before a crash, we can look it up directly.
                // Otherwise, a custom REST Search endpoint by OrderId will be required here since the OpenPay SDK 
                // does not natively unmask Charge Search by OrderId.
                if (!string.IsNullOrWhiteSpace(attempt.ProviderChargeId))
                {
                    var charge = await openPayService.GetChargeAsync(attempt.ProviderChargeId);
                    
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
                    _logger.LogWarning("Attempt {AttemptOrderId} has no ProviderChargeId. Cannot reconcile natively through OpenPay SDK GetChargeAsync.", attempt.AttemptOrderId);
                    attempt.LastErrorMessage = "Missing ProviderChargeId for SDK Lookup. Requires REST OrderId Search Implementation.";
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error calling OpenPay adapter for Attempt {AttemptOrderId}", attempt.AttemptOrderId);
                attempt.LastErrorMessage = ex.Message.Length > 500 ? ex.Message.Substring(0, 500) : ex.Message;
            }
            finally
            {
                attempt.UpdatedDate = DateTime.UtcNow;
            }
        }

        await dbContext.SaveChangesAsync(cancellationToken);
    }
}
