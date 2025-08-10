using AutoMapper;
using Azure.Core;
using XYDataLabs.OpenPayAdapter;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Interfaces;
using XYDataLabs.OrderProcessingSystem.Application.Utilities;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Openpay;
using Openpay.Entities;
using Openpay.Entities.Request;
using static XYDataLabs.OrderProcessingSystem.Application.Utilities.AppMasterConstant;
using XYDataLabs.OrderProcessingSystem.Utilities;

namespace XYDataLabs.OrderProcessingSystem.Application.Services
{
    public class OpenPayService : IOpenPayService
    {
        private readonly IOpenPayAdapterService _openPayAdapterService;
        private readonly ILogger<OpenPayService> _logger;
        private readonly string _redirectUrl;
        private readonly OrderProcessingSystemDbContext _context;
        private readonly IMapper _mapper;
        private readonly AppMasterData _appMasterData;
        private readonly PaymentProvider _openPayProvider;
        private readonly IConfiguration _configuration;

        public OpenPayService(
            IOpenPayAdapterService openPayAdapterService,
            IConfiguration configuration,
            ILogger<OpenPayService> logger,
            OrderProcessingSystemDbContext context,
            IMapper mapper,
            AppMasterData appMasterData)
        {
            _openPayAdapterService = openPayAdapterService;
            _logger = logger;
            _configuration = configuration;
            _redirectUrl = configuration[Constants.Configuration.OpenPayRedirectUrl]
                ?? throw new InvalidOperationException("RedirectUrl is not configured");
            _context = context;
            _mapper = mapper;
            _appMasterData = appMasterData;

            // Get OpenPay provider and method from master data
            _openPayProvider = _appMasterData.GetProviderByName("OpenPay")
                ?? throw new InvalidOperationException("OpenPay provider not found in master data");
        }

        public async Task<PaymentDto> ProcessPaymentAsync(CustomerWithCardPaymentRequestDto request)
        {
            try
            {
                _logger.LogInformation("Starting combined customer, card, and payment process");

                var deviceSessionId = _configuration[Constants.Configuration.OpenPayDeviceSessionId];

                request.DeviceSessionId = string.IsNullOrWhiteSpace(request.DeviceSessionId) ?
                    deviceSessionId ?? throw new InvalidOperationException("DeviceSessionId is not configured") : request.DeviceSessionId;

                // Create paymentMethod
                var paymentMethod = await CreatePaymentMethodAndGetPaymentMethodIdAsync();

                // Create customer
                var (openpayCustomer, billingCustomerId) = await CreateCustomerAsync(request, paymentMethod);

                // Update paymentMethod with billingCustomerId
                await UpdatePaymentMethodByBillingCustomerIdAsync(paymentMethod.Id, billingCustomerId);

                // Create card
                var createdCard = await CreateCardTokenAsync(request, openpayCustomer, billingCustomerId);

                // Create charge request
                var charge = await CreateChargeAsync(request, openpayCustomer, createdCard.Id, paymentMethod, billingCustomerId);

                return new PaymentDto
                {
                    Id = charge.Id,
                    OrderId = request.OrderId,
                    CustomerId = openpayCustomer.Id,
                    Amount = new Decimal(100.00),//Convert.ToDecimal(request.Amount),//todo: we can utilize later
                    Currency = AppMasterConstant.DefaultCurrencyCode,//request.Currency,//todo: we can utilize later
                    Status = charge.Status ?? "unknown",
                    CreatedAt = charge.CreationDate ?? DateTime.UtcNow,
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

        private async Task<Domain.Entities.PaymentMethod> CreatePaymentMethodAndGetPaymentMethodIdAsync()
        {
            try
            {
                _logger.LogInformation("Creating PaymentMethod...");
                // Add OpenPay Payment Method
                var openPayMethod = new Domain.Entities.PaymentMethod
                {
                    Token = Guid.NewGuid().ToString("N"), // Generate a new GUID without hyphens
                    Status = true, // Active
                    PaymentProviderId = _openPayProvider.Id, // Set the foreign key reference
                    CreatedDate = DateTime.UtcNow
                };
                _context.PaymentMethods.Add(openPayMethod);
                await _context.SaveChangesAsync();
                _logger.LogInformation("PaymentMethod created with ID: {PaymentMethodId}", openPayMethod.Id);
                return openPayMethod;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error creating PaymentMethod");
                throw;
            }
        }

        private async Task UpdatePaymentMethodByBillingCustomerIdAsync(int paymentMethodId, int billingCustomerId)
        {
            try
            {
                _logger.LogInformation("Updating PaymentMethod for BillingCustomerId: {BillingCustomerId}", billingCustomerId);

                var paymentMethod = await _context.PaymentMethods.FindAsync(paymentMethodId);
                if (paymentMethod == null)
                {
                    _logger.LogWarning("PaymentMethod with ID: {PaymentMethodId} not found", paymentMethodId);
                    throw new InvalidOperationException($"PaymentMethod with ID: {paymentMethodId} not found");
                }

                paymentMethod.CreatedBy = billingCustomerId;
                paymentMethod.UpdatedBy = billingCustomerId;
                paymentMethod.UpdatedDate = DateTime.UtcNow;
                _context.PaymentMethods.Update(paymentMethod);
                await _context.SaveChangesAsync();

                _logger.LogInformation("PaymentMethod updated for BillingCustomerId: {BillingCustomerId}", billingCustomerId);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating PaymentMethod for BillingCustomerId: {BillingCustomerId}", billingCustomerId);
                throw;
            }
        }

        public async Task<(Openpay.Entities.Customer openpayCustomer, int BillingCustomerId)> CreateCustomerAsync(CustomerWithCardPaymentRequestDto request,
                    Domain.Entities.PaymentMethod paymentMethod)
        {
            try
            {
                _logger.LogInformation("Creating customer in OpenPay...");
                var existingCustomer = await _context.BillingCustomers
                    .FirstOrDefaultAsync(c => c.Name == request.Name && c.Email == request.Email);

                if (existingCustomer != null)
                {
                    _logger.LogInformation("Customer created with ID: {CustomerId}", existingCustomer.APICustomerId);

                    return (new Openpay.Entities.Customer
                    {
                        Name = existingCustomer.Name,
                        Email = existingCustomer.Email,
                        RequiresAccount = false,
                        Id = existingCustomer.APICustomerId
                    }, existingCustomer.Id);
                }

                // Create customer in OpenPay
                var openpayCustomer = await _openPayAdapterService.CreateCustomerAsync(new Openpay.Entities.Customer
                {
                    Name = request.Name,
                    Email = request.Email,
                    //PhoneNumber = request.PhoneNumber,//todo: we can utilize later
                    RequiresAccount = false
                });

                _logger.LogInformation("Customer created with ID: {CustomerId}", openpayCustomer.Id);

                // Update the customer entity with the Openpay customer ID
                var billingCustomer = _mapper.Map<Domain.Entities.BillingCustomer>(request);
                billingCustomer.APICustomerId = openpayCustomer.Id;
                billingCustomer.TwoLetterIsoCode = AppMasterConstant.DefaultCountryCode; // Default to Mexico for OpenPay
                billingCustomer.PaymentMethodId = paymentMethod.Id;
                billingCustomer.CreatedDate = DateTime.UtcNow;
                _context.BillingCustomers.Add(billingCustomer);
                await _context.SaveChangesAsync();

                // Store additional customer info
                var keyInfo = new BillingCustomerKeyInfo
                {
                    BillingCustomerId = billingCustomer.Id,
                    KeyName = "CreationDate",
                    KeyValue = Convert.ToString(billingCustomer.CreatedDate)
                };

                _context.BillingCustomerKeyInfos.Add(keyInfo);
                await _context.SaveChangesAsync();

                return (openpayCustomer, billingCustomer.Id);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error creating customer in OpenPay");
                throw;
            }
        }

        public async Task<Card> CreateCardTokenAsync(CustomerWithCardPaymentRequestDto request,
            Openpay.Entities.Customer openpayCustomerEntity,
            int billingCustomerId)
        {
            try
            {
                _logger.LogInformation("Creating card token in OpenPay...");

                var card = new Openpay.Entities.Card
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

                // Store card transaction
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
                    CurrencyCode = AppMasterConstant.DefaultCurrencyCode, // Default for OpenPay
                    Amount = new Decimal(100.00),//request.Amount,
                    CreditCardOwnerName = request.Name,
                    CreditCardExpireYear = int.Parse(request.ExpirationYear),
                    CreditCardExpireMonth = int.Parse(request.ExpirationMonth),
                    CreditCardNumber = request.CardNumber, // This will be masked
                    CreditCardCvv2 = request.Cvv2, // This will be masked
                    TransactionMessage = $"Card created with ID: {createdCard.Id}",
                    IsTransactionSuccess = true,
                    CreatedBy = billingCustomerId,
                    CreatedDate = DateTime.UtcNow
                };

                _context.CardTransactions.Add(cardTransaction);
                await _context.SaveChangesAsync();

                // Add status history
                var statusHistory = new TransactionStatusHistory
                {
                    TransactionId = cardTransaction.Id,
                    Status = EnumHelper.GetEnumDescription(OpenPayTransactionStatus.Completed),
                    Notes = "Card tokenization successful",
                    CreatedBy = billingCustomerId,
                    CreatedDate = DateTime.UtcNow
                };

                _context.TransactionStatusHistories.Add(statusHistory);
                await _context.SaveChangesAsync();

                return createdCard;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error creating card token in OpenPay");
                throw;
            }
        }

        public async Task<Charge> CreateChargeAsync(CustomerWithCardPaymentRequestDto request,
            Openpay.Entities.Customer customer,
            string sourceId,
            Domain.Entities.PaymentMethod paymentMethod,
            int billingCustomerId)
        {
            try
            {
                _logger.LogInformation("Creating charge in OpenPay...");

                var chargeRequest = new ChargeRequest
                {
                    Method = EnumHelper.GetEnumDescription(PaymentMethodType.Card),
                    SourceId = sourceId,
                    Amount = new Decimal(100.00),//request.Amount,
                    Currency = AppMasterConstant.DefaultCurrencyCode,//request.Currency,
                    Description = $"Order: {request.OrderId}",
                    DeviceSessionId = request.DeviceSessionId,
                    OrderId = request.OrderId,
                    Use3DSecure = true,
                    RedirectUrl = _redirectUrl,
                    Customer = customer
                };

                var charge = await _openPayAdapterService.CreateChargeAsync(chargeRequest);
                _logger.LogInformation("Charge created with ID: {ChargeId}", charge.Id);

                // Create PayinLog
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
                    LastFourCardNbr = request.CardNumber.Substring(request.CardNumber.Length - 4),
                    Currency = AppMasterConstant.DefaultCurrencyCode,
                    Result = EnumHelper.GetEnumIdFromDescription<PaymentStatus>(charge.Status) ?? (int)PaymentStatus.Unknown,
                    CreatedBy = billingCustomerId,
                    CreatedDate = DateTime.UtcNow
                };

                _context.PayinLogs.Add(payinLog);
                await _context.SaveChangesAsync();

                // Create PayinLogDetails
                var payinLogDetails = new PayinLogDetails
                {
                    PayinLogId = payinLog.Id,
                    PostInfo = System.Text.Json.JsonSerializer.Serialize(chargeRequest),
                    RespInfo = System.Text.Json.JsonSerializer.Serialize(charge),
                    CreatedBy = billingCustomerId,
                    CreatedDate = DateTime.UtcNow
                };

                _context.PayinLogDetails.Add(payinLogDetails);

                // Create CardTransaction
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
                    IsTransactionSuccess = charge.Status.ToLower() == "completed",
                    RedirectUrl = charge.PaymentMethod?.Url,
                    CreditCardOwnerName = request.Name,
                    CreditCardExpireYear = int.Parse(request.ExpirationYear),
                    CreditCardExpireMonth = int.Parse(request.ExpirationMonth),
                    CreditCardNumber = request.CardNumber, // This will be masked
                    CreditCardCvv2 = request.Cvv2, // This will be masked
                    TransactionMessage = charge.ErrorMessage,
                    CreatedBy = billingCustomerId,
                    CreatedDate = DateTime.UtcNow
                };

                _context.CardTransactions.Add(cardTransaction);
                await _context.SaveChangesAsync();

                // Add status history
                var statusHistory = new TransactionStatusHistory
                {
                    TransactionId = cardTransaction.Id,
                    Status = charge.Status,
                    Notes = charge.ErrorMessage,
                    CreatedBy = billingCustomerId,
                    CreatedDate = DateTime.UtcNow
                };

                _context.TransactionStatusHistories.Add(statusHistory);
                await _context.SaveChangesAsync();

                return charge;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error creating charge in OpenPay");
                throw;
            }
        }
    }
}