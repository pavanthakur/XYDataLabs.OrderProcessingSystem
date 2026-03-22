using AutoMapper;
using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Queries;

public sealed class GetCustomersByNameQueryHandler : IQueryHandler<GetCustomersByNameQuery, Result<IEnumerable<CustomerDto>>>
{
    private readonly IAppDbContext _context;
    private readonly IMapper _mapper;

    public GetCustomersByNameQueryHandler(IAppDbContext context, IMapper mapper)
    {
        _context = context;
        _mapper = mapper;
    }

    public async Task<Result<IEnumerable<CustomerDto>>> HandleAsync(GetCustomersByNameQuery query, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(query);

        // Server-side filtering (fixed from original client-side ToListAsync → filter)
        IQueryable<Customer> customersQuery = _context.Customers;

        if (!string.IsNullOrEmpty(query.Name))
        {
            customersQuery = customersQuery.Where(c => c.Name.Contains(query.Name));
        }

        var customers = await customersQuery
            .OrderBy(c => c.CustomerId)
            .Skip((query.PageNumber - 1) * query.PageSize)
            .Take(query.PageSize)
            .ToListAsync(cancellationToken);

        return _mapper.Map<IEnumerable<CustomerDto>>(customers).ToList();
    }
}
