using AutoMapper;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Openpay.Entities;
using Openpay.Entities.Request;
using XYDataLabs.OpenPayAdapter;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Utilities;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;
using static XYDataLabs.OrderProcessingSystem.Application.Utilities.AppMasterConstant;
using OpenPayCustomer = Openpay.Entities.Customer;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Payments.Commands;

public sealed class ProcessPaymentCommandHandler : ICommandHandler<ProcessPaymentCommand, Result<PaymentDto>>
{
    private readonly IOpenPayAdapterService _openPayAdapterService;
    private readonly ILogger<ProcessPaymentCommandHandler> _logger;
    private readonly string _redirectUrl;
    private readonly IAppDbContext _context;
    private readonly IMapper _mapper;
    private readonly AppMasterData _appMasterData;
    private readonly PaymentProvider _openPayProvider;
    private readonly IConfiguration _configuration;
    private readonly TimeProvider _timeProvider;

    public ProcessPaymentCommandHandler(
        IOpenPayAdapterService openPayAdapterService,
        IConfiguration configuration,
        ILogger<ProcessPaymentCommandHandler> logger,
        IAppDbContext context,
        IMapper mapper,
        AppMasterData appMasterData,
        TimeProvider timeProvider)
    {
        _openPayAdapterService = openPayAdapterService;
        _logger = logger;
        _configuration = configuration;
        _redirectUrl = configuration[Constants.Configuration.OpenPayRedirectUrl]
            ?? throw new InvalidOperationException("RedirectUrl is not configured");
        _context = context;
        _mapper = mapper;
        _appMasterData = appMasterData;
        _timeProvider = timeProvider;

        _openPayProvider = _appMasterData.GetProviderByName("OpenPay")
            ?? throw new InvalidOperationException("OpenPay provider not found in master data");
    }

    public async Task<Result<PaymentDto>> HandleAsync(ProcessPaymentCommand command, CancellationToken cancellationToken = default)
    {
        using var activity = PaymentActivitySource.Source.StartActivity("ProcessPayment");
        activity?.SetTag("payment.order_id", command.OrderId);

        try
        {
            _logger.LogInformation("Starting combined customer, card, and payment process");

            var deviceSessionId = _configuration[Constants.Configuration.OpenPayDeviceSessionId];
            var resolvedDeviceSessionId = string.IsNullOrWhiteSpace(command.DeviceSessionId)
                ? deviceSessionId ?? throw new InvalidOperationException("DeviceSessionId is not configured")
                : command.DeviceSessionId;

            // Build DTO for mapper compatibility
            var request = new CustomerWithCardPaymentRequestDto
            {
                Name = command.Name,
                Email = command.Email,
                DeviceSessionId = resolvedDeviceSessionId,
                CardNumber = command.CardNumber,
                ExpirationYear = command.ExpirationYear,
                ExpirationMonth = command.ExpirationMonth,
                Cvv2 = command.Cvv2,
                OrderId = command.OrderId
            };

            var paymentMethod = await CreatePaymentMethodAsync(cancellationToken);
            var (openpayCustomer, billingCustomerId) = await CreateCustomerAsync(request, paymentMethod, cancellationToken);
            await UpdatePaymentMethodByBillingCustomerIdAsync(paymentMethod.Id, billingCustomerId, cancellationToken);
            var createdCard = await CreateCardTokenAsync(request, openpayCustomer, billingCustomerId, cancellationToken);
            var charge = await CreateChargeAsync(request, openpayCustomer, createdCard.Id, paymentMethod, billingCustomerId, cancellationToken);

            return new PaymentDto
            {
                Id = charge.Id,
                OrderId = request.OrderId,
                CustomerId = openpayCustomer.Id,
                Amount = new decimal(100.00),
                Currency = AppMasterConstant.DefaultCurrencyCode,
                Status = charge.Status ?? "unknown",
                CreatedAt = charge.CreationDate ?? _timeProvider.GetUtcNow().UtcDateTime,
                TransactionId = charge.Authorization,
                ThreeDSecureUrl = charge.PaymentMethod?.Url,
                ErrorMessage = charge.ErrorMessage
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in combined payment process: {Message}", ex.Message);
            throw;
        }
    }

    private async Task<Domain.Entities.PaymentMethod> CreatePaymentMethodAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Creating PaymentMethod...");
        var openPayMethod = new Domain.Entities.PaymentMethod
        {
            Token = Guid.NewGuid().ToString("N"),
            Status = true,
            PaymentProviderId = _openPayProvider.Id,
            CreatedDate = _timeProvider.GetUtcNow().UtcDateTime
        };
        _context.PaymentMethods.Add(openPayMethod);
        await _context.SaveChangesAsync(cancellationToken);
        _logger.LogInformation("PaymentMethod created with ID: {PaymentMethodId}", openPayMethod.Id);
        return openPayMethod;
    }

    private async Task UpdatePaymentMethodByBillingCustomerIdAsync(int paymentMethodId, int billingCustomerId, CancellationToken cancellationToken)
    {
        _logger.LogInformation("Updating PaymentMethod for BillingCustomerId: {BillingCustomerId}", billingCustomerId);

        var paymentMethod = await _context.PaymentMethods.FindAsync([paymentMethodId], cancellationToken);
        if (paymentMethod is null)
            throw new InvalidOperationException($"PaymentMethod with ID: {paymentMethodId} not found");

        paymentMethod.CreatedBy = billingCustomerId;
        paymentMethod.UpdatedBy = billingCustomerId;
        paymentMethod.UpdatedDate = _timeProvider.GetUtcNow().UtcDateTime;
        _context.PaymentMethods.Update(paymentMethod);
        await _context.SaveChangesAsync(cancellationToken);

        _logger.LogInformation("PaymentMethod updated for BillingCustomerId: {BillingCustomerId}", billingCustomerId);
    }

    private async Task<(OpenPayCustomer openpayCustomer, int BillingCustomerId)> CreateCustomerAsync(
        CustomerWithCardPaymentRequestDto request,
        Domain.Entities.PaymentMethod paymentMethod,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation("Creating customer in OpenPay...");
        var existingCustomer = await _context.BillingCustomers
            .FirstOrDefaultAsync(c => c.Name == request.Name && c.Email == request.Email, cancellationToken);

        if (existingCustomer is not null)
        {
            _logger.LogInformation("Existing customer found with ID: {CustomerId}", existingCustomer.APICustomerId);
            return (new OpenPayCustomer
            {
                Name = existingCustomer.Name,
                Email = existingCustomer.Email,
                RequiresAccount = false,
                Id = existingCustomer.APICustomerId
            }, existingCustomer.Id);
        }

        var openpayCustomer = await _openPayAdapterService.CreateCustomerAsync(new OpenPayCustomer
        {
            Name = request.Name,
            Email = request.Email,
            RequiresAccount = false
        });

        _logger.LogInformation("Customer created with ID: {CustomerId}", openpayCustomer.Id);

        var billingCustomer = _mapper.Map<BillingCustomer>(request);
        billingCustomer.APICustomerId = openpayCustomer.Id;
        billingCustomer.TwoLetterIsoCode = AppMasterConstant.DefaultCountryCode;
        billingCustomer.PaymentMethodId = paymentMethod.Id;
        billingCustomer.CreatedDate = _timeProvider.GetUtcNow().UtcDateTime;
        _context.BillingCustomers.Add(billingCustomer);
        await _context.SaveChangesAsync(cancellationToken);

        var keyInfo = new BillingCustomerKeyInfo
        {
            BillingCustomerId = billingCustomer.Id,
            KeyName = "CreationDate",
            KeyValue = Convert.ToString(billingCustomer.CreatedDate)
        };

        _context.BillingCustomerKeyInfos.Add(keyInfo);
        await _context.SaveChangesAsync(cancellationToken);

        return (openpayCustomer, billingCustomer.Id);
    }

    private async Task<Card> CreateCardTokenAsync(
        CustomerWithCardPaymentRequestDto request,
        OpenPayCustomer openpayCustomerEntity,
        int billingCustomerId,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation("Creating card token in OpenPay...");

        var card = new Card
        {
            CardNumber = request.CardNumber,
            HolderName = request.Name,
            ExpirationYear = request.ExpirationYear,
            ExpirationMonth = request.ExpirationMonth,
            Cvv2 = request.Cvv2,
            DeviceSessionId = request.DeviceSessionId
        };

        var createdCard = await _openPayAdapterService.CreateCardTokenAsync(card);
        _logger.LogInformation("Card created with ID: {CardId}", createdCard.Id);

        var cardTransaction = new CardTransaction
        {
            CustomerId = billingCustomerId,
            TransactionCustomerId = openpayCustomerEntity.Id,
            TransactionId = createdCard.Id,
            PaymentMethod = EnumHelper.GetEnumDescription(PaymentMethodType.Card),
            TransactionType = EnumHelper.GetEnumDescription(TransactionType.Tokenization),
            OrderId = request.OrderId,
            TransactionStatus = EnumHelper.GetEnumDescription(OpenPayTransactionStatus.Completed),
            TransactionDate = createdCard.CreationDate,
            CurrencyCode = AppMasterConstant.DefaultCurrencyCode,
            Amount = new decimal(100.00),
            CreditCardOwnerName = request.Name,
            CreditCardExpireYear = int.Parse(request.ExpirationYear),
            CreditCardExpireMonth = int.Parse(request.ExpirationMonth),
            CreditCardNumber = request.CardNumber,
            CreditCardCvv2 = request.Cvv2,
            TransactionMessage = $"Card created with ID: {createdCard.Id}",
            IsTransactionSuccess = true,
            CreatedBy = billingCustomerId,
            CreatedDate = _timeProvider.GetUtcNow().UtcDateTime
        };

        _context.CardTransactions.Add(cardTransaction);
        await _context.SaveChangesAsync(cancellationToken);

        var statusHistory = new TransactionStatusHistory
        {
            TransactionId = cardTransaction.Id,
            Status = EnumHelper.GetEnumDescription(OpenPayTransactionStatus.Completed),
            Notes = "Card tokenization successful",
            CreatedBy = billingCustomerId,
            CreatedDate = _timeProvider.GetUtcNow().UtcDateTime
        };

        _context.TransactionStatusHistories.Add(statusHistory);
        await _context.SaveChangesAsync(cancellationToken);

        return createdCard;
    }

    private async Task<Charge> CreateChargeAsync(
        CustomerWithCardPaymentRequestDto request,
        OpenPayCustomer customer,
        string sourceId,
        Domain.Entities.PaymentMethod paymentMethod,
        int billingCustomerId,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation("Creating charge in OpenPay...");

        var chargeRequest = new ChargeRequest
        {
            Method = EnumHelper.GetEnumDescription(PaymentMethodType.Card),
            SourceId = sourceId,
            Amount = new decimal(100.00),
            Currency = AppMasterConstant.DefaultCurrencyCode,
            Description = $"Order: {request.OrderId}",
            DeviceSessionId = request.DeviceSessionId,
            OrderId = request.OrderId,
            Use3DSecure = true,
            RedirectUrl = _redirectUrl,
            Customer = customer
        };

        var charge = await _openPayAdapterService.CreateChargeAsync(chargeRequest);
        _logger.LogInformation("Charge created with ID: {ChargeId}", charge.Id);

        var payinLog = new PayinLog
        {
            ReferenceNo = chargeRequest.OrderId,
            PaymentMethodId = paymentMethod.Id,
            PaymentMethodName = _openPayProvider.Name,
            PayinType = (int?)PayInType.Charge,
            APINO1 = charge.Id,
            Amount = chargeRequest.Amount,
            AmountFromAPI = charge.Amount,
            CardOwnerName = request.Name,
            LastFourCardNbr = request.CardNumber[^4..],
            Currency = AppMasterConstant.DefaultCurrencyCode,
            Result = EnumHelper.GetEnumIdFromDescription<PaymentStatus>(charge.Status) ?? (int)PaymentStatus.Unknown,
            CreatedBy = billingCustomerId,
            CreatedDate = _timeProvider.GetUtcNow().UtcDateTime
        };

        _context.PayinLogs.Add(payinLog);
        await _context.SaveChangesAsync(cancellationToken);

        var payinLogDetails = new PayinLogDetails
        {
            PayinLogId = payinLog.Id,
            PostInfo = System.Text.Json.JsonSerializer.Serialize(chargeRequest),
            RespInfo = System.Text.Json.JsonSerializer.Serialize(charge),
            CreatedBy = billingCustomerId,
            CreatedDate = _timeProvider.GetUtcNow().UtcDateTime
        };

        _context.PayinLogDetails.Add(payinLogDetails);

        var cardTransaction = new CardTransaction
        {
            CustomerId = billingCustomerId,
            TransactionCustomerId = customer.Id,
            TransactionId = charge.Id,
            PaymentMethod = EnumHelper.GetEnumDescription(PaymentMethodType.Card),
            TransactionType = EnumHelper.GetEnumDescription(TransactionType.Charge),
            OrderId = chargeRequest.OrderId,
            TransactionStatus = charge.Status,
            TransactionDate = charge.CreationDate,
            Amount = charge.Amount,
            CurrencyCode = AppMasterConstant.DefaultCurrencyCode,
            IsTransactionSuccess = string.Equals(charge.Status, "completed", StringComparison.OrdinalIgnoreCase),
            RedirectUrl = charge.PaymentMethod?.Url,
            CreditCardOwnerName = request.Name,
            CreditCardExpireYear = int.Parse(request.ExpirationYear),
            CreditCardExpireMonth = int.Parse(request.ExpirationMonth),
            CreditCardNumber = request.CardNumber,
            CreditCardCvv2 = request.Cvv2,
            TransactionMessage = charge.ErrorMessage,
            CreatedBy = billingCustomerId,
            CreatedDate = _timeProvider.GetUtcNow().UtcDateTime
        };

        _context.CardTransactions.Add(cardTransaction);
        await _context.SaveChangesAsync(cancellationToken);

        var statusHistory = new TransactionStatusHistory
        {
            TransactionId = cardTransaction.Id,
            Status = charge.Status,
            Notes = charge.ErrorMessage,
            CreatedBy = billingCustomerId,
            CreatedDate = _timeProvider.GetUtcNow().UtcDateTime
        };

        _context.TransactionStatusHistories.Add(statusHistory);
        await _context.SaveChangesAsync(cancellationToken);

        return charge;
    }
}
