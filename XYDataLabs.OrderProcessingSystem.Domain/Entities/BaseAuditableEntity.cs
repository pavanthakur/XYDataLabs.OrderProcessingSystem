using System.Collections.ObjectModel;
using XYDataLabs.OrderProcessingSystem.Domain.Events;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public abstract class BaseAuditableEntity : IHasDomainEvents
    {
        private readonly List<object> _domainEvents = new();

        public int TenantId { get; set; }
        public int? CreatedBy { get; set; }
        public DateTime? CreatedDate { get; set; }
        public int? UpdatedBy { get; set; }
        public DateTime? UpdatedDate { get; set; }

        public ReadOnlyCollection<object> DomainEvents => _domainEvents.AsReadOnly();

        protected void RaiseDomainEvent(object domainEvent)
        {
            ArgumentNullException.ThrowIfNull(domainEvent);
            _domainEvents.Add(domainEvent);
        }

        public void ClearDomainEvents()
        {
            _domainEvents.Clear();
        }
    }
}
