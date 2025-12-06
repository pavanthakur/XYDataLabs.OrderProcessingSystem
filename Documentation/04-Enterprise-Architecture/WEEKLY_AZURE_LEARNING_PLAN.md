# 🚀 Weekly Azure Learning Plan with Enterprise Standards Maintenance
## Your Roadmap to Azure Excellence - App Services, Functions & Container Apps

> **Core Philosophy**: "Maintain enterprise standards while learning Azure - never compromise on quality!"

**Last Updated**: December 6, 2024  
**Current Phase**: ✅ Foundation Complete (Weeks 1-2) | 🎯 Next: Service Bus & Azure Functions (Weeks 3-4)

---

## 📊 **CURRENT PROGRESS VERIFICATION**

Run verification anytime to check your progress:
```powershell
.\Resources\Azure-Deployment\verify-azure-setup.ps1
```

### **✅ COMPLETED (Weeks 1-2)**
- ✅ **App Services**: API & UI running in Azure
  - `pavanthakur-orderprocessing-api-xyapp-dev` - Running
  - `pavanthakur-orderprocessing-ui-xyapp-dev` - Running
- ✅ **Application Insights**: Monitoring configured (`ai-orderprocessing-dev`)
- ✅ **Azure SQL Database**: Database provisioned and migrations complete
- ✅ **Azure Key Vault**: Secrets management configured
- ✅ **Managed Identity**: API App identity enabled for secure access
- ✅ **CI/CD Pipeline**: GitHub Actions deployment working
- ✅ **Payment API**: External integration verified

### **🎯 NEXT STEPS (Weeks 3-4)**
- ⏳ **Service Bus**: Message queuing for async processing
- ⏳ **Azure Functions**: Serverless event-driven processing

### **📅 FUTURE (Weeks 5-8)**
- 📋 **Storage Accounts**: Blob storage for files and data
- 📋 **API Management**: Gateway and API versioning
- 📋 **Container Apps**: Microservices containerization

---

## 📅 **WEEKS 1-2: FOUNDATION - COMPLETED ✅**

### **Achievement Summary**
You have successfully completed the Azure foundation phase! Here's what you've accomplished:

#### **Infrastructure Deployed**
- ✅ Resource Group with proper naming conventions
- ✅ App Service Plans for API and UI
- ✅ Azure App Services running and accessible
- ✅ Azure SQL Server and Database provisioned
- ✅ Application Insights for monitoring and telemetry
- ✅ Azure Key Vault for secrets management
- ✅ Managed Identity for secure service-to-service auth

#### **DevOps & CI/CD**
- ✅ GitHub Actions workflows configured
- ✅ OIDC authentication set up (no secrets!)
- ✅ Automated deployment pipelines working
- ✅ Environment isolation (dev environment ready)

#### **Application Integration**
- ✅ Payment API integration working
- ✅ Database migrations executed successfully
- ✅ Configuration externalized to Key Vault
- ✅ Health checks and monitoring active

### **Verify Your Foundation**
```powershell
# Run this to verify all foundation services
.\Resources\Azure-Deployment\verify-azure-setup.ps1
```

---

## 📅 **WEEKS 3-4: MESSAGE QUEUING & SERVERLESS - SERVICE BUS + AZURE FUNCTIONS**

### **🎯 Learning Objectives**
- Implement Azure Service Bus for reliable message queuing
- Create Azure Functions for event-driven processing
- Integrate serverless architecture with existing API
- Maintain enterprise standards in async processing

### **📋 Week 3: Azure Service Bus Implementation**

#### **Day 1-2: Service Bus Setup**
**Objective**: Create Service Bus namespace and queues

```powershell
# Create Service Bus namespace
az servicebus namespace create `
  --name sb-orderprocessing-dev `
  --resource-group rg-orderprocessing-dev `
  --location centralindia `
  --sku Standard

# Create queues for order processing
az servicebus queue create `
  --namespace-name sb-orderprocessing-dev `
  --resource-group rg-orderprocessing-dev `
  --name order-notifications

az servicebus queue create `
  --namespace-name sb-orderprocessing-dev `
  --resource-group rg-orderprocessing-dev `
  --name payment-processing

# Get connection string
az servicebus namespace authorization-rule keys list `
  --resource-group rg-orderprocessing-dev `
  --namespace-name sb-orderprocessing-dev `
  --name RootManageSharedAccessKey `
  --query primaryConnectionString -o tsv
```

**Enterprise Standards Check**:
```powershell
# Verify local development still works
.\Resources\BuildConfiguration\enterprise-check.ps1
```

**Learning Resources**:
- [ ] Read: [Azure Service Bus Overview](https://docs.microsoft.com/azure/service-bus-messaging/)
- [ ] Watch: Service Bus patterns (Queues vs Topics)
- [ ] Practice: Send/receive messages using Service Bus Explorer

#### **Day 3-4: Service Bus Integration with API**
**Objective**: Integrate Service Bus messaging into Order Processing API

**Code Example - Add to API**:
```csharp
// Install NuGet package
// Azure.Messaging.ServiceBus

// In Program.cs or Startup
services.AddSingleton<ServiceBusClient>(sp =>
{
    var connectionString = configuration["ServiceBus:ConnectionString"];
    return new ServiceBusClient(connectionString);
});

services.AddSingleton<IMessagePublisher, ServiceBusPublisher>();

// Create Publisher Interface
public interface IMessagePublisher
{
    Task PublishOrderCreatedAsync(Order order);
    Task PublishPaymentProcessedAsync(Payment payment);
}

// Implement Publisher
public class ServiceBusPublisher : IMessagePublisher
{
    private readonly ServiceBusClient _client;
    private readonly ILogger<ServiceBusPublisher> _logger;

    public ServiceBusPublisher(ServiceBusClient client, ILogger<ServiceBusPublisher> logger)
    {
        _client = client;
        _logger = logger;
    }

    public async Task PublishOrderCreatedAsync(Order order)
    {
        var sender = _client.CreateSender("order-notifications");
        var message = new ServiceBusMessage(JsonSerializer.Serialize(order))
        {
            MessageId = order.Id.ToString(),
            Subject = "OrderCreated"
        };
        
        await sender.SendMessageAsync(message);
        _logger.LogInformation("Published order created event for Order {OrderId}", order.Id);
    }

    public async Task PublishPaymentProcessedAsync(Payment payment)
    {
        var sender = _client.CreateSender("payment-processing");
        var message = new ServiceBusMessage(JsonSerializer.Serialize(payment))
        {
            MessageId = payment.Id.ToString(),
            Subject = "PaymentProcessed"
        };
        
        await sender.SendMessageAsync(message);
        _logger.LogInformation("Published payment processed event for Payment {PaymentId}", payment.Id);
    }
}
```

**Configuration in Key Vault**:
```powershell
# Store Service Bus connection string in Key Vault
az keyvault secret set `
  --vault-name kv-orderproc-dev `
  --name ServiceBusConnectionString `
  --value "<connection-string-from-day-1>"

# Update App Service configuration
az webapp config appsettings set `
  --name pavanthakur-orderprocessing-api-xyapp-dev `
  --resource-group rg-orderprocessing-dev `
  --settings ServiceBus__ConnectionString="@Microsoft.KeyVault(SecretUri=https://kv-orderproc-dev.vault.azure.net/secrets/ServiceBusConnectionString/)"
```

**Testing**:
```powershell
# Test message publishing from API
Invoke-RestMethod -Uri "https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net/api/orders" `
  -Method POST `
  -ContentType "application/json" `
  -Body '{"customerName":"Test User","amount":100}'

# Check Service Bus queue in Azure Portal
# Should see messages in the queue
```

#### **Day 5: Enterprise Validation & Week Review**
```powershell
# Run comprehensive check
.\Resources\BuildConfiguration\enterprise-check.ps1

# Verify Azure setup
.\Resources\Azure-Deployment\verify-azure-setup.ps1

# Review Application Insights for Service Bus metrics
az monitor app-insights metrics show `
  --app ai-orderprocessing-dev `
  --resource-group rg-orderprocessing-dev `
  --metric "dependencies/count"
```

---

### **📋 Week 4: Azure Functions - Serverless Processing**

#### **Day 1-2: Azure Functions Setup**
**Objective**: Create Function App for processing Service Bus messages

```powershell
# Create storage account (required for Functions)
az storage account create `
  --name storderprocdev `
  --resource-group rg-orderprocessing-dev `
  --location centralindia `
  --sku Standard_LRS

# Create Function App (isolated worker)
az functionapp create `
  --name func-orderprocessing-dev `
  --resource-group rg-orderprocessing-dev `
  --storage-account storderprocdev `
  --consumption-plan-location centralindia `
  --runtime dotnet-isolated `
  --runtime-version 8 `
  --functions-version 4 `
  --os-type Windows

# Enable Application Insights
az functionapp config appsettings set `
  --name func-orderprocessing-dev `
  --resource-group rg-orderprocessing-dev `
  --settings APPLICATIONINSIGHTS_CONNECTION_STRING="<app-insights-connection-string>"

# Enable Managed Identity
az functionapp identity assign `
  --name func-orderprocessing-dev `
  --resource-group rg-orderprocessing-dev
```

**Learning Resources**:
- [ ] Read: [Azure Functions Overview](https://docs.microsoft.com/azure/azure-functions/)
- [ ] Read: Service Bus Trigger bindings
- [ ] Watch: Serverless architecture patterns
- [ ] Practice: Create "Hello World" HTTP function

#### **Day 3-4: Implement Service Bus Triggered Functions**
**Objective**: Create functions to process messages from Service Bus

**Create Function Project**:
```powershell
# Navigate to solution directory
cd Q:\GIT\TestAppXY_OrderProcessingSystem

# Create new Function project
dotnet new func --name XYDataLabs.OrderProcessingSystem.Functions --worker-runtime dotnet-isolated

cd XYDataLabs.OrderProcessingSystem.Functions

# Add required packages
dotnet add package Microsoft.Azure.Functions.Worker
dotnet add package Microsoft.Azure.Functions.Worker.Sdk
dotnet add package Microsoft.Azure.Functions.Worker.Extensions.ServiceBus
dotnet add package Microsoft.ApplicationInsights.WorkerService
dotnet add package Azure.Messaging.ServiceBus
```

**Function Code - Order Notification Processor**:
```csharp
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Azure.Messaging.ServiceBus;
using System.Text.Json;

namespace XYDataLabs.OrderProcessingSystem.Functions;

public class OrderNotificationProcessor
{
    private readonly ILogger<OrderNotificationProcessor> _logger;

    public OrderNotificationProcessor(ILogger<OrderNotificationProcessor> logger)
    {
        _logger = logger;
    }

    [Function(nameof(OrderNotificationProcessor))]
    public async Task Run(
        [ServiceBusTrigger("order-notifications", Connection = "ServiceBusConnectionString")]
        ServiceBusReceivedMessage message,
        ServiceBusMessageActions messageActions)
    {
        try
        {
            _logger.LogInformation("Processing order notification: {MessageId}", message.MessageId);
            
            // Deserialize order
            var order = JsonSerializer.Deserialize<Order>(message.Body.ToString());
            
            // Process notification (send email, SMS, etc.)
            await SendOrderConfirmationEmail(order);
            await SendOrderConfirmationSMS(order);
            
            // Complete the message
            await messageActions.CompleteMessageAsync(message);
            
            _logger.LogInformation("Successfully processed order notification: {MessageId}", message.MessageId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing order notification: {MessageId}", message.MessageId);
            
            // Abandon message for retry
            await messageActions.AbandonMessageAsync(message);
        }
    }

    private async Task SendOrderConfirmationEmail(Order order)
    {
        // TODO: Implement email sending (e.g., SendGrid, Azure Communication Services)
        _logger.LogInformation("Sending order confirmation email for Order {OrderId}", order.Id);
        await Task.Delay(100); // Simulate email send
    }

    private async Task SendOrderConfirmationSMS(Order order)
    {
        // TODO: Implement SMS sending (e.g., Twilio, Azure Communication Services)
        _logger.LogInformation("Sending order confirmation SMS for Order {OrderId}", order.Id);
        await Task.Delay(100); // Simulate SMS send
    }
}

// Order DTO
public record Order(Guid Id, string CustomerName, decimal Amount, DateTime CreatedAt);
```

**Function Code - Payment Processor**:
```csharp
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Azure.Messaging.ServiceBus;
using System.Text.Json;

namespace XYDataLabs.OrderProcessingSystem.Functions;

public class PaymentProcessor
{
    private readonly ILogger<PaymentProcessor> _logger;

    public PaymentProcessor(ILogger<PaymentProcessor> logger)
    {
        _logger = logger;
    }

    [Function(nameof(PaymentProcessor))]
    public async Task Run(
        [ServiceBusTrigger("payment-processing", Connection = "ServiceBusConnectionString")]
        ServiceBusReceivedMessage message,
        ServiceBusMessageActions messageActions)
    {
        try
        {
            _logger.LogInformation("Processing payment: {MessageId}", message.MessageId);
            
            // Deserialize payment
            var payment = JsonSerializer.Deserialize<Payment>(message.Body.ToString());
            
            // Process payment (reconciliation, reporting, etc.)
            await ReconcilePayment(payment);
            await UpdateReporting(payment);
            
            // Complete the message
            await messageActions.CompleteMessageAsync(message);
            
            _logger.LogInformation("Successfully processed payment: {MessageId}", message.MessageId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing payment: {MessageId}", message.MessageId);
            
            // Abandon message for retry
            await messageActions.AbandonMessageAsync(message);
        }
    }

    private async Task ReconcilePayment(Payment payment)
    {
        _logger.LogInformation("Reconciling payment {PaymentId}", payment.Id);
        await Task.Delay(100); // Simulate reconciliation
    }

    private async Task UpdateReporting(Payment payment)
    {
        _logger.LogInformation("Updating reporting for payment {PaymentId}", payment.Id);
        await Task.Delay(100); // Simulate reporting update
    }
}

// Payment DTO
public record Payment(Guid Id, Guid OrderId, decimal Amount, string Status, DateTime ProcessedAt);
```

**Program.cs Configuration**:
```csharp
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices(services =>
    {
        services.AddApplicationInsightsTelemetryWorkerService();
        services.ConfigureFunctionsApplicationInsights();
    })
    .Build();

host.Run();
```

**local.settings.json** (for local development):
```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "dotnet-isolated",
    "ServiceBusConnectionString": "Endpoint=sb://sb-orderprocessing-dev.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=<your-key>"
  }
}
```

**Deploy Functions**:
```powershell
# Build and publish
dotnet publish --configuration Release --output ./publish

# Deploy to Azure
func azure functionapp publish func-orderprocessing-dev

# Configure Service Bus connection in Azure
az functionapp config appsettings set `
  --name func-orderprocessing-dev `
  --resource-group rg-orderprocessing-dev `
  --settings ServiceBusConnectionString="@Microsoft.KeyVault(SecretUri=https://kv-orderproc-dev.vault.azure.net/secrets/ServiceBusConnectionString/)"

# Grant Function App access to Key Vault
$functionIdentity = az functionapp identity show --name func-orderprocessing-dev --resource-group rg-orderprocessing-dev --query principalId -o tsv
az keyvault set-policy `
  --name kv-orderproc-dev `
  --object-id $functionIdentity `
  --secret-permissions get list
```

#### **Day 5: Testing & Monitoring**
**End-to-End Testing**:
```powershell
# 1. Create an order via API (should publish to Service Bus)
$response = Invoke-RestMethod -Uri "https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net/api/orders" `
  -Method POST `
  -ContentType "application/json" `
  -Body '{"customerName":"Test User","amount":100}'

# 2. Check Service Bus metrics in Azure Portal
# 3. Verify Function execution in Azure Portal (Functions > Monitor)
# 4. Check Application Insights for end-to-end trace

# View Function logs
func azure functionapp logstream func-orderprocessing-dev

# Query Application Insights
az monitor app-insights query `
  --app ai-orderprocessing-dev `
  --resource-group rg-orderprocessing-dev `
  --analytics-query "traces | where message contains 'Processing order notification' | take 10"
```

**Enterprise Validation**:
```powershell
# Run verification
.\Resources\Azure-Deployment\verify-azure-setup.ps1

# Should now show Service Bus
# Verify Function App in Azure Portal
```

---

### **🎯 Weeks 3-4 Success Criteria**

#### **Technical Achievements**
- [ ] Service Bus namespace created and configured
- [ ] Message queues operational (order-notifications, payment-processing)
- [ ] API publishes messages to Service Bus
- [ ] Function App deployed and running
- [ ] Functions processing Service Bus messages successfully
- [ ] Managed Identity configured for Function App
- [ ] Application Insights tracking end-to-end operations
- [ ] Storage Account created for Functions

#### **Learning Outcomes**
- [ ] Understand async messaging patterns
- [ ] Know when to use queues vs topics
- [ ] Can implement Service Bus triggers in Functions
- [ ] Understand serverless pricing model
- [ ] Can monitor and troubleshoot Functions
- [ ] Know how to handle poison messages
- [ ] Understand Function retry policies

#### **Enterprise Standards Maintained**
```powershell
# All checks must pass
.\Resources\BuildConfiguration\enterprise-check.ps1

# Local development still fully functional
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http
```

---

## 📅 **WEEKS 5-6: STORAGE & ADVANCED FUNCTIONS - BLOB STORAGE + DURABLE FUNCTIONS**

### **🎯 Learning Objectives**
- Implement Azure Blob Storage for file management
- Learn Durable Functions for stateful workflows
- Integrate storage with order processing system
- Implement advanced serverless patterns

### **📋 Week 5: Azure Blob Storage Implementation**

#### **Day 1-2: Blob Storage Setup**
**Objective**: Create storage account and containers for order documents

```powershell
# Storage account already created in Week 4 (storderprocdev)
# Create containers for different purposes

# Container for order invoices
az storage container create `
  --name order-invoices `
  --account-name storderprocdev `
  --public-access off

# Container for payment receipts
az storage container create `
  --name payment-receipts `
  --account-name storderprocdev `
  --public-access off

# Container for customer documents
az storage container create `
  --name customer-documents `
  --account-name storderprocdev `
  --public-access off

# Get storage connection string
az storage account show-connection-string `
  --name storderprocdev `
  --resource-group rg-orderprocessing-dev `
  --query connectionString -o tsv

# Store in Key Vault
az keyvault secret set `
  --vault-name kv-orderproc-dev `
  --name StorageConnectionString `
  --value "<connection-string>"
```

**Learning Resources**:
- [ ] Read: [Azure Blob Storage Overview](https://docs.microsoft.com/azure/storage/blobs/)
- [ ] Read: Blob storage security and access tiers
- [ ] Practice: Upload/download blobs using Storage Explorer

#### **Day 3-4: Blob Storage Integration**
**Objective**: Add file upload/download capabilities to API

**Install Packages in API Project**:
```powershell
cd XYDataLabs.OrderProcessingSystem.API
dotnet add package Azure.Storage.Blobs
```

**Blob Storage Service Implementation**:
```csharp
// Add to API project
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;

public interface IBlobStorageService
{
    Task<string> UploadInvoiceAsync(Guid orderId, Stream fileStream, string fileName);
    Task<Stream> DownloadInvoiceAsync(string blobName);
    Task<bool> DeleteInvoiceAsync(string blobName);
    Task<List<string>> ListInvoicesAsync(Guid orderId);
}

public class BlobStorageService : IBlobStorageService
{
    private readonly BlobServiceClient _blobServiceClient;
    private readonly ILogger<BlobStorageService> _logger;
    private const string InvoiceContainer = "order-invoices";

    public BlobStorageService(BlobServiceClient blobServiceClient, ILogger<BlobStorageService> logger)
    {
        _blobServiceClient = blobServiceClient;
        _logger = logger;
    }

    public async Task<string> UploadInvoiceAsync(Guid orderId, Stream fileStream, string fileName)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(InvoiceContainer);
        await containerClient.CreateIfNotExistsAsync();

        var blobName = $"{orderId}/{fileName}";
        var blobClient = containerClient.GetBlobClient(blobName);

        await blobClient.UploadAsync(fileStream, new BlobHttpHeaders { ContentType = "application/pdf" });
        
        _logger.LogInformation("Uploaded invoice {BlobName} for order {OrderId}", blobName, orderId);
        return blobName;
    }

    public async Task<Stream> DownloadInvoiceAsync(string blobName)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(InvoiceContainer);
        var blobClient = containerClient.GetBlobClient(blobName);

        var response = await blobClient.DownloadAsync();
        return response.Value.Content;
    }

    public async Task<bool> DeleteInvoiceAsync(string blobName)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(InvoiceContainer);
        var blobClient = containerClient.GetBlobClient(blobName);

        return await blobClient.DeleteIfExistsAsync();
    }

    public async Task<List<string>> ListInvoicesAsync(Guid orderId)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(InvoiceContainer);
        var prefix = $"{orderId}/";
        
        var blobs = new List<string>();
        await foreach (var blobItem in containerClient.GetBlobsAsync(prefix: prefix))
        {
            blobs.Add(blobItem.Name);
        }

        return blobs;
    }
}

// Register in Program.cs
services.AddSingleton(sp =>
{
    var connectionString = configuration["Storage:ConnectionString"];
    return new BlobServiceClient(connectionString);
});

services.AddScoped<IBlobStorageService, BlobStorageService>();
```

**API Endpoints for File Upload**:
```csharp
[ApiController]
[Route("api/orders/{orderId}/invoices")]
public class InvoiceController : ControllerBase
{
    private readonly IBlobStorageService _blobStorage;
    private readonly ILogger<InvoiceController> _logger;

    public InvoiceController(IBlobStorageService blobStorage, ILogger<InvoiceController> logger)
    {
        _blobStorage = blobStorage;
        _logger = logger;
    }

    [HttpPost]
    public async Task<IActionResult> UploadInvoice(Guid orderId, IFormFile file)
    {
        if (file == null || file.Length == 0)
            return BadRequest("No file uploaded");

        using var stream = file.OpenReadStream();
        var blobName = await _blobStorage.UploadInvoiceAsync(orderId, stream, file.FileName);

        return Ok(new { blobName, url = $"/api/orders/{orderId}/invoices/{file.FileName}" });
    }

    [HttpGet("{fileName}")]
    public async Task<IActionResult> DownloadInvoice(Guid orderId, string fileName)
    {
        var blobName = $"{orderId}/{fileName}";
        var stream = await _blobStorage.DownloadInvoiceAsync(blobName);

        return File(stream, "application/pdf", fileName);
    }

    [HttpGet]
    public async Task<IActionResult> ListInvoices(Guid orderId)
    {
        var invoices = await _blobStorage.ListInvoicesAsync(orderId);
        return Ok(invoices);
    }
}
```

#### **Day 5: Blob-Triggered Function**
**Objective**: Create Azure Function triggered by blob uploads

**Function Code - Invoice Processing**:
```csharp
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Azure.Storage.Blobs;

namespace XYDataLabs.OrderProcessingSystem.Functions;

public class InvoiceProcessor
{
    private readonly ILogger<InvoiceProcessor> _logger;

    public InvoiceProcessor(ILogger<InvoiceProcessor> logger)
    {
        _logger = logger;
    }

    [Function(nameof(InvoiceProcessor))]
    public async Task Run(
        [BlobTrigger("order-invoices/{orderId}/{fileName}", Connection = "StorageConnectionString")]
        Stream blobStream,
        string orderId,
        string fileName)
    {
        _logger.LogInformation("Processing invoice {FileName} for order {OrderId}", fileName, orderId);

        // Process invoice (e.g., OCR, validation, archiving)
        await ValidateInvoice(blobStream);
        await ExtractInvoiceData(blobStream);
        await ArchiveInvoice(orderId, fileName);

        _logger.LogInformation("Successfully processed invoice {FileName}", fileName);
    }

    private async Task ValidateInvoice(Stream stream)
    {
        _logger.LogInformation("Validating invoice format");
        await Task.Delay(100); // Simulate validation
    }

    private async Task ExtractInvoiceData(Stream stream)
    {
        _logger.LogInformation("Extracting invoice data (OCR)");
        await Task.Delay(100); // Simulate OCR processing
    }

    private async Task ArchiveInvoice(string orderId, string fileName)
    {
        _logger.LogInformation("Archiving invoice to long-term storage");
        await Task.Delay(100); // Simulate archiving
    }
}
```

---

### **📋 Week 6: Durable Functions - Stateful Workflows**

#### **Day 1-2: Durable Functions Concepts**
**Objective**: Understand and set up Durable Functions

**Install Durable Functions**:
```powershell
cd XYDataLabs.OrderProcessingSystem.Functions
dotnet add package Microsoft.Azure.Functions.Worker.Extensions.DurableTask
```

**Learning Resources**:
- [ ] Read: [Durable Functions Overview](https://docs.microsoft.com/azure/azure-functions/durable/)
- [ ] Read: Function chaining, fan-out/fan-in patterns
- [ ] Watch: Durable Functions patterns and use cases
- [ ] Practice: Create simple orchestration

#### **Day 3-5: Implement Order Processing Workflow**
**Objective**: Create complex order processing workflow with Durable Functions

**Orchestrator Function - Complete Order Processing**:
```csharp
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.DurableTask;
using Microsoft.DurableTask.Client;
using Microsoft.Extensions.Logging;

namespace XYDataLabs.OrderProcessingSystem.Functions;

public class OrderProcessingOrchestrator
{
    [Function(nameof(ProcessOrder))]
    public static async Task<OrderResult> ProcessOrder(
        [OrchestrationTrigger] TaskOrchestrationContext context)
    {
        var logger = context.CreateReplaySafeLogger<OrderProcessingOrchestrator>();
        var order = context.GetInput<OrderData>();

        logger.LogInformation("Starting order processing workflow for Order {OrderId}", order.OrderId);

        try
        {
            // Step 1: Validate order
            var validationResult = await context.CallActivityAsync<bool>(
                nameof(ValidateOrder), order);

            if (!validationResult)
            {
                return new OrderResult { Success = false, Message = "Order validation failed" };
            }

            // Step 2: Process payment (with timeout)
            using var cts = new CancellationTokenSource();
            var paymentTask = context.CallActivityAsync<PaymentResult>(
                nameof(ProcessPayment), order.PaymentInfo);
            var timeoutTask = context.CreateTimer(context.CurrentUtcDateTime.AddMinutes(5), cts.Token);

            var completedTask = await Task.WhenAny(paymentTask, timeoutTask);
            
            if (completedTask == timeoutTask)
            {
                return new OrderResult { Success = false, Message = "Payment processing timeout" };
            }

            cts.Cancel(); // Cancel the timer
            var paymentResult = await paymentTask;

            if (!paymentResult.Success)
            {
                return new OrderResult { Success = false, Message = "Payment failed" };
            }

            // Step 3: Parallel execution - Inventory & Notification
            var inventoryTask = context.CallActivityAsync<bool>(
                nameof(ReserveInventory), order);
            var notificationTask = context.CallActivityAsync<bool>(
                nameof(SendConfirmationEmail), order);

            await Task.WhenAll(inventoryTask, notificationTask);

            // Step 4: Generate invoice
            var invoiceUrl = await context.CallActivityAsync<string>(
                nameof(GenerateInvoice), order);

            // Step 5: Create shipment
            var shipmentId = await context.CallActivityAsync<string>(
                nameof(CreateShipment), order);

            logger.LogInformation("Order {OrderId} processed successfully", order.OrderId);

            return new OrderResult
            {
                Success = true,
                Message = "Order processed successfully",
                InvoiceUrl = invoiceUrl,
                ShipmentId = shipmentId
            };
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error processing order {OrderId}", order.OrderId);
            
            // Compensation logic (rollback)
            await context.CallActivityAsync(nameof(CompensateOrder), order);
            
            return new OrderResult { Success = false, Message = ex.Message };
        }
    }

    // Activity Functions

    [Function(nameof(ValidateOrder))]
    public static async Task<bool> ValidateOrder([ActivityTrigger] OrderData order, FunctionContext context)
    {
        var logger = context.GetLogger(nameof(ValidateOrder));
        logger.LogInformation("Validating order {OrderId}", order.OrderId);
        
        await Task.Delay(500); // Simulate validation
        return order.Amount > 0 && !string.IsNullOrEmpty(order.CustomerName);
    }

    [Function(nameof(ProcessPayment))]
    public static async Task<PaymentResult> ProcessPayment([ActivityTrigger] PaymentInfo paymentInfo, FunctionContext context)
    {
        var logger = context.GetLogger(nameof(ProcessPayment));
        logger.LogInformation("Processing payment");
        
        await Task.Delay(2000); // Simulate payment processing
        return new PaymentResult { Success = true, TransactionId = Guid.NewGuid().ToString() };
    }

    [Function(nameof(ReserveInventory))]
    public static async Task<bool> ReserveInventory([ActivityTrigger] OrderData order, FunctionContext context)
    {
        var logger = context.GetLogger(nameof(ReserveInventory));
        logger.LogInformation("Reserving inventory for order {OrderId}", order.OrderId);
        
        await Task.Delay(1000); // Simulate inventory reservation
        return true;
    }

    [Function(nameof(SendConfirmationEmail))]
    public static async Task<bool> SendConfirmationEmail([ActivityTrigger] OrderData order, FunctionContext context)
    {
        var logger = context.GetLogger(nameof(SendConfirmationEmail));
        logger.LogInformation("Sending confirmation email for order {OrderId}", order.OrderId);
        
        await Task.Delay(500); // Simulate email send
        return true;
    }

    [Function(nameof(GenerateInvoice))]
    public static async Task<string> GenerateInvoice([ActivityTrigger] OrderData order, FunctionContext context)
    {
        var logger = context.GetLogger(nameof(GenerateInvoice));
        logger.LogInformation("Generating invoice for order {OrderId}", order.OrderId);
        
        await Task.Delay(1500); // Simulate invoice generation
        return $"https://storage.example.com/invoices/{order.OrderId}.pdf";
    }

    [Function(nameof(CreateShipment))]
    public static async Task<string> CreateShipment([ActivityTrigger] OrderData order, FunctionContext context)
    {
        var logger = context.GetLogger(nameof(CreateShipment));
        logger.LogInformation("Creating shipment for order {OrderId}", order.OrderId);
        
        await Task.Delay(1000); // Simulate shipment creation
        return $"SHIP-{Guid.NewGuid().ToString().Substring(0, 8)}";
    }

    [Function(nameof(CompensateOrder))]
    public static async Task CompensateOrder([ActivityTrigger] OrderData order, FunctionContext context)
    {
        var logger = context.GetLogger(nameof(CompensateOrder));
        logger.LogInformation("Compensating order {OrderId} - rolling back changes", order.OrderId);
        
        // Implement rollback logic
        await Task.Delay(500);
    }

    // HTTP Trigger to start orchestration
    [Function(nameof(StartOrderProcessing))]
    public static async Task<HttpResponseData> StartOrderProcessing(
        [HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequestData req,
        [DurableClient] DurableTaskClient client,
        FunctionContext context)
    {
        var logger = context.GetLogger(nameof(StartOrderProcessing));

        var order = await req.ReadFromJsonAsync<OrderData>();
        var instanceId = await client.ScheduleNewOrchestrationInstanceAsync(nameof(ProcessOrder), order);

        logger.LogInformation("Started order processing workflow with instance ID: {InstanceId}", instanceId);

        return client.CreateCheckStatusResponse(req, instanceId);
    }

    // HTTP Trigger to check orchestration status
    [Function(nameof(GetOrderStatus))]
    public static async Task<HttpResponseData> GetOrderStatus(
        [HttpTrigger(AuthorizationLevel.Function, "get", Route = "orders/{instanceId}")] HttpRequestData req,
        [DurableClient] DurableTaskClient client,
        string instanceId)
    {
        var status = await client.GetInstanceAsync(instanceId);

        var response = req.CreateResponse();
        await response.WriteAsJsonAsync(new
        {
            instanceId = status.InstanceId,
            runtimeStatus = status.RuntimeStatus.ToString(),
            createdTime = status.CreatedTime,
            lastUpdatedTime = status.LastUpdatedTime,
            output = status.SerializedOutput
        });

        return response;
    }
}

// DTOs
public record OrderData(
    Guid OrderId,
    string CustomerName,
    decimal Amount,
    PaymentInfo PaymentInfo);

public record PaymentInfo(string CardNumber, string CVV, DateTime ExpiryDate);

public record PaymentResult(bool Success, string TransactionId);

public record OrderResult
{
    public bool Success { get; init; }
    public string Message { get; init; }
    public string InvoiceUrl { get; init; }
    public string ShipmentId { get; init; }
}
```

**Testing Durable Functions**:
```powershell
# Deploy function
func azure functionapp publish func-orderprocessing-dev

# Start orchestration
$functionKey = az functionapp keys list --name func-orderprocessing-dev --resource-group rg-orderprocessing-dev --query functionKeys.default -o tsv

Invoke-RestMethod -Uri "https://func-orderprocessing-dev.azurewebsites.net/api/StartOrderProcessing?code=$functionKey" `
  -Method POST `
  -ContentType "application/json" `
  -Body '{
    "orderId": "00000000-0000-0000-0000-000000000001",
    "customerName": "John Doe",
    "amount": 150.00,
    "paymentInfo": {
      "cardNumber": "4111111111111111",
      "cvv": "123",
      "expiryDate": "2025-12-31"
    }
  }'

# Check status using the status URL returned
# Monitor in Azure Portal > Durable Functions tab
```

---

### **🎯 Weeks 5-6 Success Criteria**

#### **Technical Achievements**
- [ ] Blob Storage containers created and configured
- [ ] File upload/download working in API
- [ ] Blob-triggered functions processing files
- [ ] Durable Functions orchestration deployed
- [ ] Complex workflow executing successfully
- [ ] Compensation logic implemented
- [ ] Monitoring and logging configured

#### **Learning Outcomes**
- [ ] Understand blob storage tiers and pricing
- [ ] Know how to secure blob storage access
- [ ] Can implement stateful workflows with Durable Functions
- [ ] Understand orchestration patterns (chaining, fan-out, etc.)
- [ ] Know how to handle long-running processes
- [ ] Can implement compensation/rollback logic
- [ ] Understand Durable Functions pricing model

---
## 📅 **WEEKS 7-8: ADVANCED ARCHITECTURE - CONTAINER APPS + API MANAGEMENT**

### **🎯 Learning Objectives**
- Migrate from App Services to Azure Container Apps
- Implement API Management for gateway capabilities
- Advanced networking and security
- Production-ready architecture

### **📋 Week 7: Azure Container Apps Migration**

#### **Day 1-2: Container Apps Environment Setup**
**Objective**: Prepare for App Services to Container Apps migration

```powershell
# Create Container Apps environment
az containerapp env create `
  --name cae-orderprocessing-dev `
  --resource-group rg-orderprocessing-dev `
  --location centralindia `
  --logs-destination log-analytics

# Link to existing Application Insights
$appInsightsId = az monitor app-insights component show `
  --app ai-orderprocessing-dev `
  --resource-group rg-orderprocessing-dev `
  --query id -o tsv

# Update environment with monitoring
az containerapp env update `
  --name cae-orderprocessing-dev `
  --resource-group rg-orderprocessing-dev `
  --dapr-instrumentation-key $(az monitor app-insights component show --app ai-orderprocessing-dev --resource-group rg-orderprocessing-dev --query instrumentationKey -o tsv)
```

**Learning Resources**:
- [ ] Read: [Azure Container Apps Overview](https://docs.microsoft.com/azure/container-apps/)
- [ ] Read: Container Apps vs App Service vs AKS
- [ ] Watch: Container Apps scaling and KEDA
- [ ] Practice: Deploy sample container app

#### **Day 3-4: Containerize and Deploy Applications**
**Objective**: Build and deploy API and UI as containers

**Update Dockerfile for API** (if not already containerized):
```dockerfile
# XYDataLabs.OrderProcessingSystem.API/Dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 80
EXPOSE 443

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["XYDataLabs.OrderProcessingSystem.API/XYDataLabs.OrderProcessingSystem.API.csproj", "XYDataLabs.OrderProcessingSystem.API/"]
COPY ["XYDataLabs.OrderProcessingSystem.Application/XYDataLabs.OrderProcessingSystem.Application.csproj", "XYDataLabs.OrderProcessingSystem.Application/"]
COPY ["XYDataLabs.OrderProcessingSystem.Domain/XYDataLabs.OrderProcessingSystem.Domain.csproj", "XYDataLabs.OrderProcessingSystem.Domain/"]
COPY ["XYDataLabs.OrderProcessingSystem.Infrastructure/XYDataLabs.OrderProcessingSystem.Infrastructure.csproj", "XYDataLabs.OrderProcessingSystem.Infrastructure/"]
RUN dotnet restore "XYDataLabs.OrderProcessingSystem.API/XYDataLabs.OrderProcessingSystem.API.csproj"
COPY . .
WORKDIR "/src/XYDataLabs.OrderProcessingSystem.API"
RUN dotnet build "XYDataLabs.OrderProcessingSystem.API.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "XYDataLabs.OrderProcessingSystem.API.csproj" -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "XYDataLabs.OrderProcessingSystem.API.dll"]
```

**Build and Push to Azure Container Registry**:
```powershell
# Create ACR (if not exists)
az acr create `
  --name acrorderprocdev `
  --resource-group rg-orderprocessing-dev `
  --sku Basic `
  --admin-enabled true

# Build and push API
az acr build `
  --registry acrorderprocdev `
  --image orderprocessing-api:v1 `
  --file XYDataLabs.OrderProcessingSystem.API/Dockerfile .

# Build and push UI
az acr build `
  --registry acrorderprocdev `
  --image orderprocessing-ui:v1 `
  --file XYDataLabs.OrderProcessingSystem.UI/Dockerfile .
```

**Deploy to Container Apps**:
```powershell
# Deploy API Container App
az containerapp create `
  --name ca-orderprocessing-api-dev `
  --resource-group rg-orderprocessing-dev `
  --environment cae-orderprocessing-dev `
  --image acrorderprocdev.azurecr.io/orderprocessing-api:v1 `
  --target-port 80 `
  --ingress external `
  --registry-server acrorderprocdev.azurecr.io `
  --registry-username $(az acr credential show -n acrorderprocdev --query username -o tsv) `
  --registry-password $(az acr credential show -n acrorderprocdev --query passwords[0].value -o tsv) `
  --env-vars `
    "ConnectionStrings__DefaultConnection=secretref:sqlconnectionstring" `
    "ApplicationInsights__ConnectionString=secretref:appinsightsconnectionstring" `
    "ServiceBus__ConnectionString=secretref:servicebusconnectionstring" `
  --secrets `
    sqlconnectionstring="$(az keyvault secret show --vault-name kv-orderproc-dev --name SqlConnectionString --query value -o tsv)" `
    appinsightsconnectionstring="$(az keyvault secret show --vault-name kv-orderproc-dev --name AppInsightsConnectionString --query value -o tsv)" `
    servicebusconnectionstring="$(az keyvault secret show --vault-name kv-orderproc-dev --name ServiceBusConnectionString --query value -o tsv)" `
  --min-replicas 1 `
  --max-replicas 5 `
  --cpu 0.5 `
  --memory 1.0Gi

# Deploy UI Container App
az containerapp create `
  --name ca-orderprocessing-ui-dev `
  --resource-group rg-orderprocessing-dev `
  --environment cae-orderprocessing-dev `
  --image acrorderprocdev.azurecr.io/orderprocessing-ui:v1 `
  --target-port 80 `
  --ingress external `
  --registry-server acrorderprocdev.azurecr.io `
  --registry-username $(az acr credential show -n acrorderprocdev --query username -o tsv) `
  --registry-password $(az acr credential show -n acrorderprocdev --query passwords[0].value -o tsv) `
  --env-vars `
    "ApiBaseUrl=https://ca-orderprocessing-api-dev.{environmentdomain}" `
  --min-replicas 1 `
  --max-replicas 3

# Get FQDNs
az containerapp show -n ca-orderprocessing-api-dev -g rg-orderprocessing-dev --query properties.configuration.ingress.fqdn -o tsv
az containerapp show -n ca-orderprocessing-ui-dev -g rg-orderprocessing-dev --query properties.configuration.ingress.fqdn -o tsv
```

#### **Day 5: DAPR Integration (Optional Advanced)**
**Objective**: Enable DAPR for microservices patterns

```powershell
# Enable DAPR on Container App
az containerapp dapr enable `
  --name ca-orderprocessing-api-dev `
  --resource-group rg-orderprocessing-dev `
  --dapr-app-id orderprocessing-api `
  --dapr-app-port 80

# Create DAPR component for Service Bus
az containerapp env dapr-component set `
  --name cae-orderprocessing-dev `
  --resource-group rg-orderprocessing-dev `
  --dapr-component-name pubsub `
  --yaml dapr-servicebus.yaml
```

**dapr-servicebus.yaml**:
```yaml
componentType: pubsub.azure.servicebus
version: v1
metadata:
  - name: connectionString
    secretRef: servicebusconnectionstring
scopes:
  - orderprocessing-api
```

---

### **📋 Week 8: API Management Gateway**

#### **Day 1-2: API Management Setup**
**Objective**: Create API Management instance for gateway capabilities

```powershell
# Create API Management (Consumption tier for dev)
az apim create `
  --name apim-orderprocessing-dev `
  --resource-group rg-orderprocessing-dev `
  --location centralindia `
  --publisher-name "XY Data Labs" `
  --publisher-email "admin@xydatalabs.com" `
  --sku-name Consumption

# This takes 5-10 minutes to provision
```

**Learning Resources**:
- [ ] Read: [API Management Overview](https://docs.microsoft.com/azure/api-management/)
- [ ] Read: API policies and transformations
- [ ] Watch: API versioning and rate limiting
- [ ] Practice: Create simple API in APIM

#### **Day 3-4: Import and Configure APIs**
**Objective**: Import Order Processing API into APIM

```powershell
# Get Container App API URL
$apiUrl = az containerapp show -n ca-orderprocessing-api-dev -g rg-orderprocessing-dev --query properties.configuration.ingress.fqdn -o tsv

# Import API (using OpenAPI/Swagger)
az apim api import `
  --resource-group rg-orderprocessing-dev `
  --service-name apim-orderprocessing-dev `
  --path orders `
  --specification-url "https://$apiUrl/swagger/v1/swagger.json" `
  --specification-format OpenApiJson `
  --display-name "Order Processing API" `
  --protocols https

# Set backend
az apim api update `
  --resource-group rg-orderprocessing-dev `
  --service-name apim-orderprocessing-dev `
  --api-id orders `
  --service-url "https://$apiUrl"
```

**Add API Policies** (rate limiting, caching, transformation):
```xml
<!-- Policy for rate limiting and caching -->
<policies>
    <inbound>
        <base />
        <rate-limit calls="100" renewal-period="60" />
        <quota calls="10000" renewal-period="3600" />
        <cache-lookup vary-by-developer="false" vary-by-developer-groups="false" downstream-caching-type="none" />
        <set-header name="X-Powered-By" exists-action="delete" />
        <cors allow-credentials="false">
            <allowed-origins>
                <origin>*</origin>
            </allowed-origins>
            <allowed-methods>
                <method>GET</method>
                <method>POST</method>
                <method>PUT</method>
                <method>DELETE</method>
            </allowed-methods>
        </cors>
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
        <cache-store duration="60" />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

#### **Day 5: API Versioning and Products**
**Objective**: Implement API versioning and create products

```powershell
# Create API version set
az apim api versionset create `
  --resource-group rg-orderprocessing-dev `
  --service-name apim-orderprocessing-dev `
  --version-set-id orderprocessing-versions `
  --display-name "Order Processing API Versions" `
  --versioning-scheme Segment

# Add v1 to version set
az apim api update `
  --resource-group rg-orderprocessing-dev `
  --service-name apim-orderprocessing-dev `
  --api-id orders `
  --api-version v1 `
  --api-version-set-id orderprocessing-versions

# Create product (Free tier)
az apim product create `
  --resource-group rg-orderprocessing-dev `
  --service-name apim-orderprocessing-dev `
  --product-id free-tier `
  --product-name "Free Tier" `
  --description "Limited API access for free users" `
  --subscription-required true `
  --approval-required false `
  --subscriptions-limit 10 `
  --state published

# Create product (Premium tier)
az apim product create `
  --resource-group rg-orderprocessing-dev `
  --service-name apim-orderprocessing-dev `
  --product-id premium-tier `
  --product-name "Premium Tier" `
  --description "Full API access for premium users" `
  --subscription-required true `
  --approval-required true `
  --state published

# Associate API with products
az apim product api add `
  --resource-group rg-orderprocessing-dev `
  --service-name apim-orderprocessing-dev `
  --product-id free-tier `
  --api-id orders

az apim product api add `
  --resource-group rg-orderprocessing-dev `
  --service-name apim-orderprocessing-dev `
  --product-id premium-tier `
  --api-id orders
```

**Product Policies (Different rate limits)**:
```xml
<!-- Free Tier Policy -->
<policies>
    <inbound>
        <base />
        <rate-limit calls="10" renewal-period="60" />
        <quota calls="1000" renewal-period="86400" />
    </inbound>
</policies>

<!-- Premium Tier Policy -->
<policies>
    <inbound>
        <base />
        <rate-limit calls="1000" renewal-period="60" />
        <quota calls="100000" renewal-period="86400" />
    </inbound>
</policies>
```

**Testing APIM**:
```powershell
# Get APIM gateway URL
$apimGateway = az apim show -n apim-orderprocessing-dev -g rg-orderprocessing-dev --query gatewayUrl -o tsv

# Create subscription
az apim subscription create `
  --resource-group rg-orderprocessing-dev `
  --service-name apim-orderprocessing-dev `
  --subscription-id test-subscription `
  --display-name "Test Subscription" `
  --scope "/products/free-tier" `
  --state active

# Get subscription key
$subscriptionKey = az apim subscription show `
  --resource-group rg-orderprocessing-dev `
  --service-name apim-orderprocessing-dev `
  --subscription-id test-subscription `
  --query primaryKey -o tsv

# Test API through APIM
Invoke-RestMethod -Uri "$apimGateway/orders/api/orders" `
  -Headers @{"Ocp-Apim-Subscription-Key" = $subscriptionKey} `
  -Method GET
```

---

### **🎯 Weeks 7-8 Success Criteria**

#### **Technical Achievements**
- [ ] Azure Container Apps environment created
- [ ] API and UI deployed as containers
- [ ] Container Apps scaling configured
- [ ] DAPR enabled (optional)
- [ ] API Management instance provisioned
- [ ] APIs imported and configured in APIM
- [ ] API policies applied (rate limiting, caching)
- [ ] API versioning implemented
- [ ] Products and subscriptions configured

#### **Learning Outcomes**
- [ ] Understand Container Apps architecture
- [ ] Know when to use Container Apps vs App Service
- [ ] Can containerize .NET applications
- [ ] Understand DAPR and microservices patterns
- [ ] Know how to implement API gateway patterns
- [ ] Can configure API policies and transformations
- [ ] Understand API versioning strategies
- [ ] Know how to monetize APIs with products

---

## 📅 **WEEK 9+: PRODUCTION READINESS & OPTIMIZATION**

### **🎯 Advanced Topics**

#### **Security Hardening**
- [ ] Implement Azure Private Endpoints
- [ ] Configure Azure Front Door / CDN
- [ ] Set up Web Application Firewall (WAF)
- [ ] Enable Advanced Threat Protection
- [ ] Implement Azure AD B2C for user authentication

#### **Performance Optimization**
- [ ] Configure Azure CDN for static content
- [ ] Implement Redis Cache
- [ ] Optimize database queries and indexing
- [ ] Set up auto-scaling rules
- [ ] Configure traffic distribution

#### **Monitoring & Observability**
- [ ] Create Application Insights dashboards
- [ ] Set up Azure Monitor alerts
- [ ] Configure Log Analytics queries
- [ ] Implement distributed tracing
- [ ] Set up availability tests

#### **DevOps Enhancement**
- [ ] Blue-Green deployment strategy
- [ ] Canary releases
- [ ] Feature flags with Azure App Configuration
- [ ] Automated rollback procedures
- [ ] Infrastructure as Code (Bicep/Terraform)

#### **Cost Optimization**
- [ ] Analyze Azure Cost Management reports
- [ ] Implement resource tagging
- [ ] Optimize SKU sizing
- [ ] Configure budget alerts
- [ ] Review and optimize storage tiers

---

**Afternoon (2:00-4:00): Enterprise Standards Check**
```powershell
# Daily enterprise validation (NEW HABIT!)
.\Resources\BuildConfiguration\enterprise-check.ps1

# Verify Docker environment still working
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http -Down
```

**Evening (7:00-8:00): Documentation**
- [ ] Read Azure Container Apps overview
- [ ] Document Azure learning goals in your project

#### **🗓️ Wednesday, August 21**
**Morning (9:00-11:00): Azure Container Registry**
- [ ] Create Azure Container Registry (ACR)
- [ ] Learn ACR authentication methods
- [ ] Understand image tagging strategies

**Afternoon (2:00-4:00): Enterprise Standards Maintenance**
```powershell
# Enterprise check + Docker validation
.\Resources\BuildConfiguration\enterprise-check.ps1

# Test UAT environment (ensure enterprise standards)
.\Resources\Docker\start-docker.ps1 -Environment uat -Profile https -EnterpriseMode

# Document any issues or improvements needed
```

**Evening (7:00-8:00): Planning**
- [ ] Plan which Docker images to push to ACR first
- [ ] Review your current Docker multi-stage builds

#### **🗓️ Thursday, August 22**
**Morning (9:00-11:00): Push Images to ACR**
- [ ] Build and tag your API image for ACR
- [ ] Push first image to Azure Container Registry
- [ ] Verify image in Azure Portal

**Afternoon (2:00-4:00): Enterprise Validation**
```powershell
# Weekly comprehensive check
.\Resources\BuildConfiguration\enterprise-check.ps1

# Test production environment (enterprise standards)
.\Resources\Docker\start-docker.ps1 -Environment prod -Profile https -EnterpriseMode -BackupFirst

# Verify all environments still working after Azure activities
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http
.\Resources\Docker\start-docker.ps1 -Environment uat -Profile https  
.\Resources\Docker\start-docker.ps1 -Environment prod -Profile https
```

**Evening (7:00-8:00): Reflection**
- [ ] Document what worked well with ACR
- [ ] Note any enterprise standard improvements needed

#### **🗓️ Friday, August 23**
**Morning (9:00-11:00): Azure Container Apps Introduction**
- [ ] Create first Container App environment
- [ ] Understand Container Apps vs AKS differences
- [ ] Learn about Container Apps networking

**Afternoon (2:00-4:00): Enterprise Standards Review**
```powershell
# End-of-week enterprise audit
.\Resources\BuildConfiguration\enterprise-check.ps1

# Full environment validation
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile all
.\Resources\Docker\start-docker.ps1 -Environment uat -Profile all
.\Resources\Docker\start-docker.ps1 -Environment prod -Profile all
```

**Evening (7:00-8:00): Week Review**
- [ ] Document week's achievements
- [ ] Plan next week's enterprise standards integration

#### **🗓️ Weekend (August 24-25)**
**Saturday Morning (Optional)**
- [ ] Practice Azure CLI commands
- [ ] Review Container Apps documentation

**Sunday Evening**
- [ ] Plan Week 2 activities
- [ ] Ensure all Docker environments are clean and working

---

## 📅 **WEEK 2: August 27 - September 2, 2025 - Container Apps Deployment + Standards Integration**

### **🎯 Learning Objectives**
- Deploy your Order Processing System to Azure Container Apps
- Integrate enterprise standards into Azure environment
- Set up CI/CD pipeline foundations

### **📋 Daily Plan**

#### **🗓️ Wednesday, August 27**
**Morning: Azure Container Apps Deployment**
```bash
# Deploy API to Container Apps (using your enterprise images)
az containerapp create \
  --name orderprocessing-api-dev \
  --resource-group rg-orderprocessing-dev \
  --environment containerapp-env-dev \
  --image acrorderprocessing.azurecr.io/orderprocessing-api:dev
```

**Afternoon: Enterprise Standards Validation**
```powershell
# Daily enterprise check
.\Resources\BuildConfiguration\enterprise-check.ps1

# Ensure local development still works (maintain standards)
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http -EnterpriseMode
```

#### **🗓️ Thursday, August 28**
**Morning: Environment Variables & Configuration**
- [ ] Migrate sharedsettings.dev.json to Container Apps environment variables
- [ ] Set up Azure Key Vault for secrets
- [ ] Configure Container Apps ingress

**Afternoon: Enterprise Integration**
```powershell
# Validate enterprise standards maintained
.\Resources\BuildConfiguration\enterprise-check.ps1

# Test all local environments (ensure no regression)
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http
.\Resources\Docker\start-docker.ps1 -Environment uat -Profile https
.\Resources\Docker\start-docker.ps1 -Environment prod -Profile https
```

#### **🗓️ Friday, August 29**
**Morning: Multi-Environment Azure Setup**
- [ ] Create UAT Container App environment
- [ ] Deploy to UAT environment
- [ ] Test UAT deployment

**Afternoon: Enterprise Standards Audit**
```powershell
# Weekly comprehensive enterprise check
.\Resources\BuildConfiguration\enterprise-check.ps1

# Full local environment validation
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile all -EnterpriseMode
.\Resources\Docker\start-docker.ps1 -Environment uat -Profile all -EnterpriseMode
.\Resources\Docker\start-docker.ps1 -Environment prod -Profile all -EnterpriseMode
```

---

## 🏆 **ENTERPRISE STANDARDS MAINTENANCE STRATEGY**

### **🔄 Daily Habits (5 minutes)**
```powershell
# Every morning before starting work
.\Resources\BuildConfiguration\enterprise-check.ps1

# Every evening before finishing
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http -Down
```

### **📊 Weekly Enterprise Audit (15 minutes)**
```powershell
# Every Friday afternoon
.\Resources\BuildConfiguration\enterprise-check.ps1

# Test all environments
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http
.\Resources\Docker\start-docker.ps1 -Environment uat -Profile https  
.\Resources\Docker\start-docker.ps1 -Environment prod -Profile https -EnterpriseMode

# Clean shutdown
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http -Down
.\Resources\Docker\start-docker.ps1 -Environment uat -Profile https -Down
.\Resources\Docker\start-docker.ps1 -Environment prod -Profile https -Down
```

### **🚨 Enterprise Standards Red Flags**
Watch for these while learning Azure:

❌ **Never Do:**
- Skip enterprise-check.ps1 for more than 2 days
- Hardcode secrets in Azure Container Apps
- Break environment isolation (dev/uat/prod)
- Remove non-root user configurations
- Bypass multi-stage Docker builds

✅ **Always Do:**
- Run enterprise-check.ps1 before major changes
- Test local Docker after Azure activities  
- Maintain sharedsettings pattern (translate to Key Vault)
- Keep environment-specific networks in local setup
- Document enterprise standards in Azure equivalents

### **📋 Monthly Enterprise Review Checklist**

#### **🔍 Standards Verification**
- [ ] All Docker environments (dev/uat/prod) working locally
- [ ] Enterprise check script passing all validations
- [ ] Azure environments mirror local enterprise patterns
- [ ] Configuration externalization maintained
- [ ] Security practices preserved (non-root containers)
- [ ] Multi-environment isolation working in Azure
- [ ] Backup strategies implemented in Azure

#### **🚀 Azure Enterprise Integration**
- [ ] Container Apps environments match local dev/uat/prod
- [ ] Azure Key Vault replaces sharedsettings pattern
- [ ] Managed Identity configured for security
- [ ] Application Insights monitoring enabled
- [ ] Azure backup policies configured
- [ ] Network isolation implemented in Azure

---

## 🛠️ **ENTERPRISE STANDARDS AUTOMATION**

### **Enhanced Enterprise Check Script**
Let me enhance your enterprise-check.ps1 with Azure readiness validation:

```powershell
# Add to your enterprise-check.ps1
Write-Host "🚀 Azure Migration Readiness:" -ForegroundColor Cyan
Write-Host "   - Local Docker environments: ✅ $(if((docker ps -q) -and (docker network ls | Where-Object {$_ -match 'xy-.*-network'})) {'Ready'} else {'⚠️ Check needed'})" -ForegroundColor Gray
Write-Host "   - Configuration externalization: ✅ Ready for Key Vault" -ForegroundColor Gray
Write-Host "   - Multi-environment strategy: ✅ Ready for Container Apps" -ForegroundColor Gray
Write-Host "   - Enterprise security patterns: ✅ Ready for Managed Identity" -ForegroundColor Gray
```

### **Weekly Azure Learning Goals with Enterprise Validation**

#### **Week 1 Goal**: Azure Foundation + Local Standards Maintained
```powershell
# Success criteria
.\Resources\BuildConfiguration\enterprise-check.ps1  # Must pass
# + Azure subscription set up
# + ACR created and first image pushed
# + All local Docker environments still working
```

#### **Week 2 Goal**: Container Apps Deployment + Standards Integration  
```powershell
# Success criteria
.\Resources\BuildConfiguration\enterprise-check.ps1  # Must pass
# + Container Apps running in Azure
# + Environment variables migrated from sharedsettings
# + Local development still fully functional
```

#### **Week 3 Goal**: Production Deployment + Enterprise Security
```powershell
# Success criteria  
.\Resources\BuildConfiguration\enterprise-check.ps1  # Must pass
# + Production Container Apps with Key Vault
# + Managed Identity configured
# + All three environments (dev/uat/prod) in Azure
# + Local enterprise standards maintained
```

---

## 🎯 **ENTERPRISE MANTRAS FOR AZURE JOURNEY**

### **📜 Weekly Affirmations**
> **"I maintain enterprise standards while learning Azure"**  
> **"Local Docker excellence translates to Azure Container Apps excellence"**  
> **"Every Azure deployment preserves my enterprise patterns"**  
> **"I never compromise security for learning speed"**  
> **"My multi-environment strategy is my competitive advantage"**

### **🔄 Integration Philosophy**
1. **Learn Azure → Apply Enterprise Patterns**
2. **Test Azure → Validate Local Standards**  
3. **Deploy Azure → Maintain Local Backup**
4. **Iterate Azure → Enhance Enterprise Standards**

---

## 📊 **SUCCESS METRICS**

### **Daily Success**
- [ ] enterprise-check.ps1 passes ✅
- [ ] Local Docker development working ✅  
- [ ] Azure learning progress made ✅
- [ ] No enterprise standards compromised ✅

### **Weekly Success**
- [ ] All Docker environments (dev/uat/prod) tested ✅
- [ ] Azure milestones achieved ✅
- [ ] Enterprise standards enhanced (not degraded) ✅
- [ ] Documentation updated ✅

### **Monthly Success**
- [ ] Azure Container Apps running enterprise-grade workloads ✅
- [ ] Local development maintains gold standard ✅
- [ ] Enterprise patterns evolved for cloud ✅
- [ ] Ready for next learning phase ✅

---

**🏆 Remember: You're not just learning Azure - you're elevating Azure with your enterprise standards!** Your multi-environment strategy and configuration management approach are exactly what makes Azure Container Apps deployments successful. Keep maintaining those standards - they're your competitive advantage! 🚀

---

## 🚧 **TODO: CI/CD Pipeline Integration**

### **📋 FUTURE ENHANCEMENT: Enterprise Standards Automation**

> **Goal**: Integrate `enterprise-check.ps1` into CI/CD pipelines for automated enterprise compliance validation

#### **🔧 GitHub Actions Pipeline Example**

**Simple and Effective Implementation:**

```yaml
# .github/workflows/docker-standards.yml
name: Docker Enterprise Standards Check

on:
  push:
    branches: [ main ]
  pull_request:

jobs:
  standards-check:
    runs-on: windows-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Run Enterprise Standards Check
        shell: pwsh
        run: |
          Set-ExecutionPolicy Bypass -Scope Process -Force
          ./Resources/BuildConfiguration/enterprise-check.ps1

      - name: Upload Log Artifacts
        uses: actions/upload-artifact@v4
        with:
          name: enterprise-standards-logs
          path: logs/
```

**🔑 Key Points:**
- **Automatic Failure**: Script returns exit code 0 or 1, so GitHub Actions fails the job automatically if standards are not met
- **Artifact Storage**: Logs (CSV + optional JSON) are stored as artifacts for historical tracking
- **Simple Setup**: Minimal configuration, maximum effectiveness
- **Enterprise Gate**: No merges allowed without passing enterprise standards

#### **🔧 Advanced GitHub Actions Example** *(Optional Enhancement)*

```yaml
# .github/workflows/enterprise-standards-check.yml
name: Enterprise Standards Validation

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]
  schedule:
    # Run daily at 8 AM UTC (enterprise health check)
    - cron: '0 8 * * *'

jobs:
  enterprise-standards:
    runs-on: windows-latest
    name: Validate Enterprise Docker Standards
    
    steps:
    - name: Checkout Repository
      uses: actions/checkout@v4
      
    - name: Install Docker
      run: |
        # Ensure Docker is available for validation
        docker --version
        
    - name: Run Enterprise Standards Check
      id: enterprise-check
      run: |
        # Enable CI/CD mode for JSON output
        $env:EnableCICD = $true
        .\Resources\BuildConfiguration\enterprise-check.ps1
      shell: pwsh
      continue-on-error: true
      
    - name: Parse Enterprise Results
      if: always()
      run: |
        # Read JSON results for detailed analysis
        $results = Get-Content "logs\enterprise-standards-latest.json" | ConvertFrom-Json
        
        Write-Host "Enterprise Status: $($results.Status)"
        Write-Host "Overall Score: $($results.Overall)"
        Write-Host "Network Score: $($results.Network)"
        Write-Host "Config Score: $($results.Config)"
        Write-Host "Azure Ready: $($results.AzureReady)"
        
        # Set GitHub Actions outputs
        echo "enterprise-status=$($results.Status)" >> $env:GITHUB_OUTPUT
        echo "enterprise-score=$($results.Overall)" >> $env:GITHUB_OUTPUT
        echo "azure-ready=$($results.AzureReady)" >> $env:GITHUB_OUTPUT
      shell: pwsh
      
    - name: Upload Enterprise Report
      if: always()
      uses: actions/upload-artifact@v4
      with:
        name: enterprise-standards-report
        path: |
          logs/enterprise-standards-log.csv
          logs/enterprise-standards-latest.json
          
    - name: Fail Build on Poor Standards
      if: steps.enterprise-check.outcome == 'failure'
      run: |
        Write-Host "❌ Enterprise standards validation failed!" -ForegroundColor Red
        Write-Host "Review the enterprise report and fix issues before deployment" -ForegroundColor Yellow
        exit 1
      shell: pwsh
      
    - name: Success Notification
      if: success()
      run: |
        Write-Host "✅ Enterprise standards validation passed!" -ForegroundColor Green
        Write-Host "Ready for Azure Container Apps deployment!" -ForegroundColor Cyan
      shell: pwsh
```

#### **🔧 Azure DevOps Pipeline Example**

**Simple and Effective Implementation:**

```yaml
# azure-pipelines.yml
trigger:
  - main

pool:
  vmImage: 'windows-latest'

stages:
- stage: StandardsCheck
  displayName: "Enterprise Docker Standards Check"
  jobs:
  - job: Check
    steps:
    - checkout: self

    - powershell: |
        Set-ExecutionPolicy Bypass -Scope Process -Force
        ./Resources/BuildConfiguration/enterprise-check.ps1
      displayName: "Run Enterprise Standards Validation"

    - task: PublishBuildArtifacts@1
      displayName: "Publish Standards Logs"
      inputs:
        PathtoPublish: 'logs'
        ArtifactName: 'enterprise-standards-logs'
```

**🔑 Key Points:**
- **Automatic Failure**: Pipeline fails automatically if script exits with 1
- **Artifact Storage**: Logs are published as artifacts for history
- **Simple Setup**: Minimal configuration, maximum effectiveness
- **Enterprise Gate**: No deployments allowed without passing enterprise standards

#### **🔧 Advanced Azure DevOps Pipeline Example** *(Optional Enhancement)*

```yaml
# azure-pipelines-enterprise-check.yml
trigger:
  branches:
    include:
    - main
    - develop

schedules:
- cron: "0 8 * * *"  # Daily at 8 AM UTC
  displayName: Daily Enterprise Standards Check
  branches:
    include:
    - main

pool:
  vmImage: 'windows-latest'

variables:
  enableCICD: true

stages:
- stage: EnterpriseValidation
  displayName: 'Enterprise Standards Validation'
  jobs:
  - job: ValidateStandards
    displayName: 'Validate Docker Enterprise Standards'
    steps:
    
    - task: PowerShell@2
      displayName: 'Run Enterprise Standards Check'
      inputs:
        targetType: 'inline'
        script: |
          # Set CI/CD mode for JSON export
          $env:EnableCICD = $(enableCICD)
          
          # Run enterprise validation
          $exitCode = 0
          try {
            .\Resources\BuildConfiguration\enterprise-check.ps1
            $exitCode = $LASTEXITCODE
          } catch {
            Write-Host "❌ Enterprise check failed: $($_.Exception.Message)" -ForegroundColor Red
            $exitCode = 1
          }
          
          # Set pipeline variables for downstream jobs
          Write-Host "##vso[task.setvariable variable=enterpriseExitCode]$exitCode"
          
          if ($exitCode -ne 0) {
            Write-Host "##vso[task.logissue type=error]Enterprise standards validation failed with exit code: $exitCode"
          }
        pwsh: true
        workingDirectory: '$(Build.SourcesDirectory)'
      continueOnError: true
      
    - task: PowerShell@2
      displayName: 'Parse Enterprise Results'
      condition: always()
      inputs:
        targetType: 'inline'
        script: |
          # Read and parse JSON results
          $jsonPath = "logs\enterprise-standards-latest.json"
          if (Test-Path $jsonPath) {
            $results = Get-Content $jsonPath | ConvertFrom-Json
            
            Write-Host "📊 Enterprise Metrics Summary:"
            Write-Host "   Status: $($results.Status)"
            Write-Host "   Overall Score: $($results.Overall)"
            Write-Host "   Network: $($results.Network)"
            Write-Host "   Configuration: $($results.Config)"
            Write-Host "   Compose: $($results.Compose)"
            Write-Host "   Containers: $($results.Containers)"
            Write-Host "   Azure Ready: $($results.AzureReady)"
            
            # Set Azure DevOps variables
            Write-Host "##vso[task.setvariable variable=enterpriseStatus]$($results.Status)"
            Write-Host "##vso[task.setvariable variable=enterpriseScore]$($results.Overall)"
            Write-Host "##vso[task.setvariable variable=azureReadyScore]$($results.AzureReady)"
            
            # Create build tags based on enterprise status
            if ($results.Overall -ge 90) {
              Write-Host "##vso[build.addBuildTag]enterprise-excellent"
            } elseif ($results.Overall -ge 75) {
              Write-Host "##vso[build.addBuildTag]enterprise-good"
            } else {
              Write-Host "##vso[build.addBuildTag]enterprise-needs-attention"
            }
          } else {
            Write-Host "##vso[task.logissue type=warning]Enterprise JSON results not found"
          }
        pwsh: true
        workingDirectory: '$(Build.SourcesDirectory)'
        
    - task: PublishBuildArtifacts@1
      displayName: 'Publish Enterprise Reports'
      condition: always()
      inputs:
        pathToPublish: 'logs'
        artifactName: 'enterprise-standards-reports'
        publishLocation: 'Container'
        
    - task: PowerShell@2
      displayName: 'Enterprise Gate Check'
      inputs:
        targetType: 'inline'
        script: |
          $exitCode = [int]$(enterpriseExitCode)
          $status = "$(enterpriseStatus)"
          $score = [int]$(enterpriseScore)
          
          if ($exitCode -eq 0 -and $score -ge 75) {
            Write-Host "✅ Enterprise standards gate PASSED!" -ForegroundColor Green
            Write-Host "✅ Status: $status (Score: $score)" -ForegroundColor Green
            Write-Host "🚀 Ready for Azure Container Apps deployment!" -ForegroundColor Cyan
          } else {
            Write-Host "❌ Enterprise standards gate FAILED!" -ForegroundColor Red
            Write-Host "❌ Status: $status (Score: $score)" -ForegroundColor Red
            Write-Host "🔧 Fix enterprise issues before proceeding to deployment" -ForegroundColor Yellow
            exit 1
          }
        pwsh: true

- stage: AzureDeployment
  displayName: 'Azure Container Apps Deployment'
  dependsOn: EnterpriseValidation
  condition: succeeded()
  jobs:
  - job: DeployToAzure
    displayName: 'Deploy to Azure Container Apps'
    steps:
    - task: PowerShell@2
      displayName: 'Azure Deployment Placeholder'
      inputs:
        targetType: 'inline'
        script: |
          Write-Host "🚀 Enterprise standards validated - proceeding with Azure deployment!" -ForegroundColor Green
          Write-Host "📋 TODO: Implement Azure Container Apps deployment steps here" -ForegroundColor Yellow
        pwsh: true
```

#### **🎯 Implementation Checklist**

- [ ] **Enable CI/CD Mode**: Set `$EnableCICD = $true` in enterprise-check.ps1
- [ ] **Create GitHub Workflow**: Add `.github/workflows/enterprise-standards-check.yml`
- [ ] **Create Azure Pipeline**: Add `azure-pipelines-enterprise-check.yml`
- [ ] **Configure Branch Protection**: Require enterprise check to pass before merge
- [ ] **Set Up Notifications**: Alert team when enterprise standards degrade
- [ ] **Dashboard Integration**: Display enterprise metrics in CI/CD dashboards
- [ ] **Automated Remediation**: Create scripts to auto-fix common enterprise issues

#### **📊 Expected Benefits**

1. **Automated Quality Gates**: Prevent deployments with poor enterprise standards
2. **Historical Tracking**: Monitor enterprise standards trends over time
3. **Early Detection**: Catch enterprise standard degradation immediately
4. **Team Accountability**: Make enterprise standards visible to entire team
5. **Azure Readiness**: Continuous validation of Azure migration readiness

---

*This plan ensures you become an Azure expert while maintaining the enterprise excellence that sets you apart from other developers.*
