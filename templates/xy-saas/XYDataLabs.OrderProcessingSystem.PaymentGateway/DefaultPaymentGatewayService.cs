using System.Collections.Concurrent;
using Microsoft.Extensions.Options;
using Serilog;
using XYDataLabs.OrderProcessingSystem.PaymentGateway.Configuration;

namespace XYDataLabs.OrderProcessingSystem.PaymentGateway;

internal sealed class DefaultPaymentGatewayService : IPaymentGatewayService
{
    private readonly ILogger _logger;
    private readonly PaymentGatewayOptions _options;
    private readonly ConcurrentDictionary<string, PaymentGatewayCustomer> _customers = new(StringComparer.OrdinalIgnoreCase);
    private readonly ConcurrentDictionary<string, PaymentGatewayCharge> _charges = new(StringComparer.OrdinalIgnoreCase);

    public DefaultPaymentGatewayService(
        IOptions<PaymentGatewayOptions> options,
        ILogger logger)
    {
        _logger = logger;
        _options = options.Value;

        _logger.Warning(
            "Using the default in-memory payment gateway provider '{ProviderName}'. Replace IPaymentGatewayService with a real provider before production deployment.",
            _options.ProviderName);
    }

    public async Task<PaymentGatewayCustomer> CreateCustomerAsync(PaymentGatewayCustomer customer)
    {
        var maskedEmail = MaskEmail(customer.Email);
        _logger.Information("Creating payment gateway customer for email: {Email}", maskedEmail);

        try
        {
            var createdCustomer = new PaymentGatewayCustomer
            {
                Id = string.IsNullOrWhiteSpace(customer.Id) ? CreateIdentifier("cust") : customer.Id,
                Name = customer.Name,
                Email = customer.Email,
                RequiresAccount = customer.RequiresAccount,
            };

            _customers[createdCustomer.Id] = createdCustomer;

            _logger.Information("Successfully created payment gateway customer with ID: {CustomerId}", createdCustomer.Id);
            return await Task.FromResult(createdCustomer);
        }
        catch (Exception ex)
        {
            _logger.Error(ex, "Failed to create payment gateway customer for email: {Email}", maskedEmail);
            throw;
        }
    }

    public async Task<PaymentGatewayCardToken> CreateCardTokenAsync(PaymentGatewayCardTokenRequest card)
    {
        var maskedHolderName = MaskHolder(card.HolderName);
        _logger.Information("Creating payment gateway card token for holder: {HolderName}", maskedHolderName);

        try
        {
            var createdToken = new PaymentGatewayCardToken
            {
                Id = CreateIdentifier("card"),
                CreationDate = DateTime.UtcNow,
            };

            _logger.Information("Successfully created payment gateway card token with ID: {TokenId}", createdToken.Id);
            return await Task.FromResult(createdToken);
        }
        catch (Exception ex)
        {
            _logger.Error(ex, "Failed to create payment gateway card token for holder: {HolderName}", maskedHolderName);
            throw;
        }
    }

    public async Task<PaymentGatewayCharge> CreateChargeAsync(PaymentGatewayChargeRequest request)
    {
        _logger.Information("Creating payment gateway charge for amount: {Amount} {Currency}", request.Amount, request.Currency);

        try
        {
            var charge = new PaymentGatewayCharge
            {
                Id = CreateIdentifier("charge"),
                Status = "completed",
                Amount = request.Amount,
                CreationDate = DateTime.UtcNow,
                Authorization = CreateIdentifier("auth"),
                ErrorMessage = null,
                PaymentMethod = null,
            };

            _charges[charge.Id] = charge;

            _logger.Information("Successfully created payment gateway charge with ID: {ChargeId}", charge.Id);
            return await Task.FromResult(charge);
        }
        catch (Exception ex)
        {
            _logger.Error(ex, "Failed to create payment gateway charge for amount: {Amount} {Currency}", request.Amount, request.Currency);
            throw;
        }
    }

    public async Task<PaymentGatewayCharge> GetChargeAsync(string chargeId, string? customerId = null)
    {
        _logger.Information("Retrieving payment gateway charge {ChargeId}", chargeId);

        try
        {
            if (_charges.TryGetValue(chargeId, out var charge))
            {
                _logger.Information("Successfully retrieved payment gateway charge {ChargeId} with status {Status}", chargeId, charge.Status);
                return await Task.FromResult(charge);
            }

            throw new InvalidOperationException(
                $"Payment gateway charge '{chargeId}' was not found in the default in-memory provider state. Replace {nameof(DefaultPaymentGatewayService)} with a persistent provider before relying on remote reconciliation.");
        }
        catch (Exception ex)
        {
            _logger.Error(ex, "Failed to retrieve payment gateway charge {ChargeId}", chargeId);
            throw;
        }
    }

    private static string CreateIdentifier(string prefix)
        => $"{prefix}_{Guid.NewGuid():N}";

    private static string MaskEmail(string? email)
    {
        if (string.IsNullOrWhiteSpace(email))
        {
            return "[empty]";
        }

        var atIndex = email.IndexOf('@');
        if (atIndex <= 1)
        {
            return "***@***";
        }

        return $"{email[0]}***{email[atIndex..]}";
    }

    private static string MaskHolder(string? name)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            return "[empty]";
        }

        return $"{name[0]}{new string('*', Math.Max(name.Length - 1, 2))}";
    }
}