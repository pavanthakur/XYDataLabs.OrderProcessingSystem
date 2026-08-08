namespace XYDataLabs.OrderProcessingSystem.Application.Events;

// Backward-compatible bridge while event contracts move to a lightweight eventing seam.
public interface IIntegrationEvent : XYDataLabs.OrderProcessingSystem.Eventing.Abstractions.IIntegrationEvent
{
}
