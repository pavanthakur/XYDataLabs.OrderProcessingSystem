using AutoMapper;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;

namespace XYDataLabs.OrderProcessingSystem.Application
{
    public class MapperConfigurationProfile : Profile
    {
        public MapperConfigurationProfile()
        {
            CreateMap<CustomerWithCardPaymentRequestDto, BillingCustomer>()
            .ForMember(dest => dest.Name, opt => opt.MapFrom(src => src.Name))
            .ForMember(dest => dest.Email, opt => opt.MapFrom(src => src.Email));
            //.ForMember(dest => dest.PhoneNumber, opt => opt.MapFrom(src => src.PhoneNumber));//todo: we can utilize later

            CreateMap<CreateCustomerRequestDto, Customer>();
            CreateMap<UpdateCustomerRequestDto, Customer>();
            CreateMap<Customer, CustomerDto>().ForMember(dest => dest.OrderDtos, opt => opt.MapFrom(src => src.Orders));
            CreateMap<Product, ProductDto>();
            CreateMap<Order, OrderDto>();
            CreateMap<OrderProduct, OrderProductDto>();
        }
    }
}
