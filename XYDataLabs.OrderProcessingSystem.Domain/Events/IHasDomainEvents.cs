using System.Collections.ObjectModel;

namespace XYDataLabs.OrderProcessingSystem.Domain.Events
{
    public interface IHasDomainEvents
    {
        ReadOnlyCollection<object> DomainEvents { get; }
        void ClearDomainEvents();
    }
}