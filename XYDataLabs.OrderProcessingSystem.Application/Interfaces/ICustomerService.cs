using XYDataLabs.OrderProcessingSystem.Application.DTO;

namespace XYDataLabs.OrderProcessingSystem.Application.Interfaces
{
    public interface ICustomerService
    {
        Task<int> CreateCustomerAsync(CreateCustomerRequestDto customerDto);
        Task<CustomerDto?> GetCustomerByIdAsync(int customerId);
        Task<IEnumerable<CustomerDto>> GetAllCustomersAsync();
        Task<IEnumerable<CustomerDto>> GetAllCustomersByNameAsync(string name, int pageNumber, int pageSize);
        Task<CustomerDto> GetCustomerWithOrdersAsync(int customerId);
        void VerifyExceptionLoggedInService();
        Task<int> UpdateCustomerAsync(int customerId, UpdateCustomerRequestDto customerDto);
        Task DeleteCustomerAsync(int customerId);
    }
}
