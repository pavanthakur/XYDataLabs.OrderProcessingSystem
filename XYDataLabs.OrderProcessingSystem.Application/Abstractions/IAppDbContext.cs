namespace XYDataLabs.OrderProcessingSystem.Application.Abstractions;

/// <summary>
/// Backward-compatible alias for the shared database context contract.
/// New module-level feature code should depend on
/// XYDataLabs.OrderProcessingSystem.SharedKernel.Abstractions.IAppDbContext instead.
/// </summary>
public interface IAppDbContext : XYDataLabs.OrderProcessingSystem.SharedKernel.Abstractions.IAppDbContext
{
}
