using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Inventory.Features.Queries;

public sealed record GetInventoryStatusQuery(string ProductSku) : IQuery<Result<InventoryStatusDto>>;

public sealed record InventoryStatusDto(string ProductSku, int AvailableQuantity, bool IsReservable);
