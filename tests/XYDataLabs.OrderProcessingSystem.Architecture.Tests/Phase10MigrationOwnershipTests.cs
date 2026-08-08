using FluentAssertions;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests;

public sealed class Phase10MigrationOwnershipTests
{
    [Fact]
    public void Phase10OwnedServiceHost_Should_Not_Run_DbInitializer_During_Runtime_Startup()
    {
        var solutionRoot = FindSolutionRoot();
        var hostPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.API",
            "Hosting",
            "Phase10OwnedServiceHost.cs");

        File.Exists(hostPath).Should().BeFalse(
            "the transitional Phase10OwnedServiceHost helper should be retired once module hosts own their composition roots directly");
    }

    [Fact]
    public void Phase10LocalProfile_Should_Use_Docker_Backing_Infra_And_Disable_Startup_Ddl()
    {
        var solutionRoot = FindSolutionRoot();
        var scriptPath = Path.Combine(solutionRoot, "scripts", "start-phase10-local-profile.ps1");
        var content = File.ReadAllText(scriptPath);

        content.Should().Contain(
            "start-phase10-docker-dev.ps1",
            "Phase 10 local debug mode must reuse the canonical Docker-backed infrastructure path");
        content.Should().Contain(
            "-DisableStartupDdl",
            "Phase 10 local debug mode must prevent API startup from mutating schema at runtime");
    }

    [Fact]
    public void Phase10LocalApiProfile_Should_Target_Phase10_Dev_Databases_When_Docker_Backing_Is_Enabled()
    {
        var solutionRoot = FindSolutionRoot();
        var scriptPath = Path.Combine(solutionRoot, "scripts", "start-local-api-profile.ps1");
        var content = File.ReadAllText(scriptPath);

        content.Should().Contain(
            "OrderProcessingSystem_Dev",
            "the Phase 10 Docker-backed local API profile must target the shared Phase 10 dev database");
        content.Should().Contain(
            "OrderProcessingSystem_TenantC_Dev",
            "the Phase 10 Docker-backed local API profile must target the dedicated Phase 10 TenantC dev database");
        content.Should().Contain(
            "LOCAL_SERVICEBUS_HOST_CONNECTION_STRING",
            "the Phase 10 Docker-backed local API profile must use host-reachable emulator endpoints");
    }

    [Fact]
    public void Phase10DockerStartup_Should_Delegate_DatabaseBootstrap_To_A_Reusable_Helper()
    {
        var solutionRoot = FindSolutionRoot();
        var scriptPath = Path.Combine(solutionRoot, "scripts", "start-phase10-docker-dev.ps1");
        var content = File.ReadAllText(scriptPath);

        content.Should().Contain(
            "invoke-phase10-database-bootstrap.ps1",
            "the Phase 10 Docker startup path should delegate shared and dedicated database bootstrap to one reusable helper");
    }

    [Fact]
    public void StandardLocalProfile_Should_Bootstrap_Database_And_Disable_Runtime_StartupDdl()
    {
        var solutionRoot = FindSolutionRoot();
        var scriptPath = Path.Combine(solutionRoot, "scripts", "start-local-profile.ps1");
        var content = File.ReadAllText(scriptPath);

        content.Should().Contain(
            "verify-local-db-ready.ps1",
            "the standard local profile should invoke an explicit local database bootstrap before starting the API");
        content.Should().Contain(
            "-DisableStartupDdl",
            "the standard local profile should launch the API with startup DDL disabled once bootstrap has already completed");
    }

    [Fact]
    public void LocalDbReadyScript_Should_Run_Explicit_DatabaseBootstrap_Tool()
    {
        var solutionRoot = FindSolutionRoot();
        var scriptPath = Path.Combine(solutionRoot, "scripts", "verify-local-db-ready.ps1");
        var content = File.ReadAllText(scriptPath);

        content.Should().Contain(
            "Phase10.DatabaseBootstrap.csproj",
            "local database readiness should run the dedicated bootstrap tool instead of relying on runtime startup DDL");
    }

    [Fact]
    public void ApiProgram_Should_Default_Runtime_StartupDdl_To_Disabled()
    {
        var solutionRoot = FindSolutionRoot();
        var programPath = Path.Combine(solutionRoot, "XYDataLabs.OrderProcessingSystem.API", "Program.cs");
        var content = File.ReadAllText(programPath);

        content.Should().Contain(
            "GetValue(\"Phase10:DisableStartupDdl\", true)",
            "Phase 10 runtime startup must default to bootstrap-owned schema mutation instead of performing DDL on app start");
    }

    [Fact]
    public void ApiLaunchProfiles_Should_Disable_StartupDdl_By_Default()
    {
        var solutionRoot = FindSolutionRoot();
        var launchSettingsPath = Path.Combine(solutionRoot, "XYDataLabs.OrderProcessingSystem.API", "Properties", "launchSettings.json");
        var content = File.ReadAllText(launchSettingsPath);

        content.Should().Contain(
            "\"Phase10__DisableStartupDdl\": \"true\"",
            "supported local API launch profiles must default to bootstrap-owned schema mutation instead of runtime startup DDL");
    }

    [Fact]
    public void ServiceBusSubscriptionConsumerWorker_Should_Remain_TransportOnly()
    {
        var solutionRoot = FindSolutionRoot();
        var workerPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Infrastructure",
            "Messaging",
            "ServiceBusSubscriptionConsumerWorker.cs");
        var content = File.ReadAllText(workerPath);

        content.Should().Contain(
            "IServiceBusConsumerMessageProcessor",
            "the broker worker should delegate tenant resolution, inbox coordination, and handler dispatch through a reusable processor seam");
        content.Should().NotContain(
            "OrderProcessingSystemDbContext",
            "the broker worker should not own database transaction and inbox orchestration directly");
        content.Should().NotContain(
            "TenantRegistryDbContext",
            "the broker worker should not resolve tenant topology directly");
        content.Should().NotContain(
            "ITenantResolver",
            "tenant resolution belongs inside the reusable consumer processor seam");
    }

    [Fact]
    public void LegacyDlqReplayWorker_Should_Be_Removed_In_Favor_Of_The_FunctionOwned_Replay_Path()
    {
        var solutionRoot = FindSolutionRoot();
        var workerPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Infrastructure",
            "Messaging",
            "DlqReplayWorker.cs");

        File.Exists(workerPath).Should().BeFalse(
            "Phase 10 replay ownership is approval -> replay request publisher -> queue -> Functions replay, so the legacy infrastructure replay worker should not remain as a competing path");
    }

    [Fact]
    public void DlqFunctions_Should_Use_Separate_Trigger_Entities_With_Application_Controlled_Settlement()
    {
        var solutionRoot = FindSolutionRoot();
        var intakePath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Functions",
            "DlqIntakeFunction.cs");
        var replayPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Functions",
            "DlqReplayFunction.cs");

        var intakeContent = File.ReadAllText(intakePath);
        var replayContent = File.ReadAllText(replayPath);

        intakeContent.Should().Contain(
            "\"%Phase10DlqTopicName%\"",
            "DLQ intake must listen to the dead-letter topic instead of the replay-request queue");
        intakeContent.Should().Contain(
            "\"%Phase10DlqIntakeSubscriptionName%\"",
            "DLQ intake must own its dedicated intake subscription");
        replayContent.Should().Contain(
            "\"%Phase10ReplayRequestQueueName%\"",
            "DLQ replay must listen to the approved replay-request queue instead of competing for the intake subscription");
        intakeContent.Should().Contain(
            "AutoCompleteMessages = false",
            "DLQ intake settlement must remain application-controlled");
        replayContent.Should().Contain(
            "AutoCompleteMessages = false",
            "DLQ replay settlement must remain application-controlled");
    }

    [Fact]
    public void PaymentsFeature_Should_Resolve_OrderPaymentContext_Through_OrdersModuleApi()
    {
        var solutionRoot = FindSolutionRoot();
        var contractPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Orders.Contracts",
            "IOrderModuleApi.cs");
        var handlerPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Payments.Features",
            "Commands",
            "ProcessPaymentCommandHandler.cs");

        var contractContent = File.ReadAllText(contractPath);
        var handlerContent = File.ReadAllText(handlerPath);

        contractContent.Should().Contain(
            "GetPaymentContextAsync",
            "Orders must expose an owner-controlled payment-context contract before Payments can stop reading Orders tables directly");
        contractContent.Should().Contain(
            "GetPaymentContextByOrderReferenceAsync",
            "the Phase 10 L1.5 flow should support the browser requesting payment using Orders-owned OrderReferenceId");
        handlerContent.Should().Contain(
            "_orderModuleApi.GetPaymentContextByOrderReferenceAsync",
            "Payments should prefer Orders-owned OrderReferenceId when the browser is linked to a persisted order");
        handlerContent.Should().NotContain(
            "_context.Orders",
            "Payments should not query the Orders DbSet directly once the Orders-owned payment-context seam exists");
    }

    [Fact]
    public void NotificationsHost_Should_Not_Reference_The_Monolithic_Api_Project()
    {
        var solutionRoot = FindSolutionRoot();
        var projectPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Notifications.Host",
            "XYDataLabs.OrderProcessingSystem.Notifications.Host.csproj");

        var content = File.ReadAllText(projectPath);

        content.Should().NotContain(
            "XYDataLabs.OrderProcessingSystem.API.csproj",
            "the Notifications host should compose directly from module and platform dependencies instead of the monolithic API");
    }

    [Fact]
    public void NotificationsHost_Should_Not_Use_The_Phase10OwnedServiceHost_From_The_Monolithic_Api()
    {
        var solutionRoot = FindSolutionRoot();
        var programPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Notifications.Host",
            "Program.cs");

        var content = File.ReadAllText(programPath);

        content.Should().NotContain(
            "Phase10OwnedServiceHost",
            "the Notifications host should own its runtime composition instead of delegating it back to the monolithic API host helper");
    }

    [Fact]
    public void InventoryHost_Should_Not_Reference_The_Monolithic_Api_Project()
    {
        var solutionRoot = FindSolutionRoot();
        var projectPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Inventory.Host",
            "XYDataLabs.OrderProcessingSystem.Inventory.Host.csproj");

        var content = File.ReadAllText(projectPath);

        content.Should().NotContain(
            "XYDataLabs.OrderProcessingSystem.API.csproj",
            "the Inventory host should compose directly from module and platform dependencies instead of the monolithic API");
    }

    [Fact]
    public void InventoryHost_Should_Not_Use_The_Phase10OwnedServiceHost_From_The_Monolithic_Api()
    {
        var solutionRoot = FindSolutionRoot();
        var programPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Inventory.Host",
            "Program.cs");

        var content = File.ReadAllText(programPath);

        content.Should().NotContain(
            "Phase10OwnedServiceHost",
            "the Inventory host should own its runtime composition instead of delegating it back to the monolithic API host helper");
    }

    [Fact]
    public void OrdersHost_Should_Not_Reference_The_Monolithic_Api_Project()
    {
        var solutionRoot = FindSolutionRoot();
        var projectPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Orders.Host",
            "XYDataLabs.OrderProcessingSystem.Orders.Host.csproj");

        var content = File.ReadAllText(projectPath);

        content.Should().NotContain(
            "XYDataLabs.OrderProcessingSystem.API.csproj",
            "the Orders host should compose directly from module and platform dependencies instead of the monolithic API");
    }

    [Fact]
    public void OrdersHost_Should_Not_Use_The_Phase10OwnedServiceHost_From_The_Monolithic_Api()
    {
        var solutionRoot = FindSolutionRoot();
        var programPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Orders.Host",
            "Program.cs");

        var content = File.ReadAllText(programPath);

        content.Should().NotContain(
            "Phase10OwnedServiceHost",
            "the Orders host should own its runtime composition instead of delegating it back to the monolithic API host helper");
    }

    [Fact]
    public void PaymentsHost_Should_Not_Reference_The_Monolithic_Api_Project()
    {
        var solutionRoot = FindSolutionRoot();
        var projectPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Payments.Host",
            "XYDataLabs.OrderProcessingSystem.Payments.Host.csproj");

        var content = File.ReadAllText(projectPath);

        content.Should().NotContain(
            "XYDataLabs.OrderProcessingSystem.API.csproj",
            "the Payments host should compose directly from module and platform dependencies instead of the monolithic API");
    }

    [Fact]
    public void PaymentsHost_Should_Not_Use_The_Phase10OwnedServiceHost_From_The_Monolithic_Api()
    {
        var solutionRoot = FindSolutionRoot();
        var programPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Payments.Host",
            "Program.cs");

        var content = File.ReadAllText(programPath);

        content.Should().NotContain(
            "Phase10OwnedServiceHost",
            "the Payments host should own its runtime composition instead of delegating it back to the monolithic API host helper");
    }

    [Fact]
    public void MonolithicApi_Should_Import_ModuleOwned_Controller_Assemblies_During_Phase10_Cutover()
    {
        var solutionRoot = FindSolutionRoot();
        var programPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.API",
            "Program.cs");

        var content = File.ReadAllText(programPath);

        content.Should().Contain(
            "AddApplicationPart(OrdersApiAssemblyReference.Assembly)",
            "Orders routes are now owned by the Orders API project and must be imported explicitly by the transitional monolithic host");
        content.Should().Contain(
            "AddApplicationPart(InventoryApiAssemblyReference.Assembly)",
            "Inventory routes must be served from the Inventory API project instead of drifting back into duplicate monolithic controllers");
        content.Should().Contain(
            "AddApplicationPart(NotificationsApiAssemblyReference.Assembly)",
            "Notifications routes must be served from the Notifications API project instead of drifting back into duplicate monolithic controllers");
        content.Should().Contain(
            "AddApplicationPart(PaymentsApiAssemblyReference.Assembly)",
            "Payments routes must be served from the Payments API project instead of drifting back into duplicate monolithic controllers");
    }

    [Fact]
    public void Application_Project_Should_Not_Reference_ModuleOwned_Api_Assemblies()
    {
        var solutionRoot = FindSolutionRoot();
        var projectPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Application",
            "XYDataLabs.OrderProcessingSystem.Application.csproj");

        var content = File.ReadAllText(projectPath);

        content.Should().NotContain(
            "XYDataLabs.OrderProcessingSystem.API.csproj",
            "Application must not point back at the transitional monolithic API project");
        content.Should().NotContain(
            "XYDataLabs.OrderProcessingSystem.Inventory.API.csproj",
            "Inventory API ownership belongs at the module edge, not inside Application");
        content.Should().NotContain(
            "XYDataLabs.OrderProcessingSystem.Notifications.API.csproj",
            "Notifications API ownership belongs at the module edge, not inside Application");
        content.Should().NotContain(
            "XYDataLabs.OrderProcessingSystem.Payments.API.csproj",
            "Payments API ownership belongs at the module edge, not inside Application");
    }

    [Fact]
    public void OrderCreated_Integration_Event_Should_Be_Owned_By_OrdersContracts_And_Not_By_Generic_Infrastructure()
    {
        var solutionRoot = FindSolutionRoot();

        var ordersContractEventPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Orders.Contracts",
            "Events",
            "OrderCreatedV1.cs");
        var legacyOrdersFeatureEventPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Orders.Features",
            "Events",
            "OrderCreatedV1.cs");
        var infrastructureProjectPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Infrastructure",
            "XYDataLabs.OrderProcessingSystem.Infrastructure.csproj");

        File.Exists(ordersContractEventPath).Should().BeTrue(
            "the OrderCreated integration event should be owned by Orders.Contracts so downstream consumers can depend on a stable contract seam");
        File.Exists(legacyOrdersFeatureEventPath).Should().BeFalse(
            "the legacy OrderCreatedV1 event implementation should not remain inside Orders.Features once the contract seam is extracted");

        var infrastructureProjectContent = File.ReadAllText(infrastructureProjectPath);
        infrastructureProjectContent.Should().Contain(
            "XYDataLabs.OrderProcessingSystem.Orders.Contracts.csproj",
            "generic infrastructure may depend on the stable Orders contract seam for transport deserialization");
        infrastructureProjectContent.Should().NotContain(
            "XYDataLabs.OrderProcessingSystem.Orders.Features.csproj",
            "generic infrastructure should not depend on Orders feature implementation just to read OrderCreatedV1");
    }

    [Fact]
    public void Orders_Features_Should_Not_Contain_An_OrderCreated_Consumer()
    {
        var solutionRoot = FindSolutionRoot();
        var legacyHandlerPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Orders.Features",
            "Events",
            "OrderCreatedV1Handler.cs");

        File.Exists(legacyHandlerPath).Should().BeFalse(
            "Orders owns publishing OrderCreatedV1, but downstream business effects must be handled by Inventory and Notifications instead of an Orders-side choreography handler");
    }

    [Fact]
    public void Feature_Assemblies_Should_Not_Contain_Legacy_InventoryReserved_Or_NotificationRequested_Choreography()
    {
        var solutionRoot = FindSolutionRoot();

        File.Exists(Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Inventory.Features",
            "Events",
            "InventoryReservedV1.cs")).Should().BeFalse(
            "the finalized pre-Azure topology routes OrderCreatedV1 directly to Inventory and Notifications instead of using an intermediate InventoryReserved integration event");

        File.Exists(Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Inventory.Features",
            "Events",
            "InventoryReservedV1Handler.cs")).Should().BeFalse(
            "Inventory should not publish a follow-on NotificationRequested integration event through feature-level choreography");

        File.Exists(Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Notifications.Features",
            "Events",
            "NotificationRequestedV1.cs")).Should().BeFalse(
            "Notifications should persist its downstream effect directly from the owned OrderCreatedV1 consumer rather than a legacy NotificationRequested choreography event");

        File.Exists(Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Notifications.Features",
            "Events",
            "NotificationRequestedV1Handler.cs")).Should().BeFalse(
            "the legacy NotificationRequestedV1 feature handler should be retired once Notifications owns its real downstream service behavior");
    }

    [Fact]
    public void Event_Contracts_Should_Depend_On_Lightweight_Eventing_Abstractions_And_Not_SharedKernel()
    {
        var solutionRoot = FindSolutionRoot();

        var ordersContractsProjectPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Orders.Contracts",
            "XYDataLabs.OrderProcessingSystem.Orders.Contracts.csproj");
        var paymentsContractsProjectPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Payments.Contracts",
            "XYDataLabs.OrderProcessingSystem.Payments.Contracts.csproj");
        var eventingAbstractionsProjectPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.Eventing.Abstractions",
            "XYDataLabs.OrderProcessingSystem.Eventing.Abstractions.csproj");
        var legacySharedKernelEventPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.SharedKernel",
            "Events",
            "IIntegrationEvent.cs");

        File.Exists(eventingAbstractionsProjectPath).Should().BeTrue(
            "event contracts should depend on a lightweight seam that does not inherit platform telemetry or Azure configuration dependencies");
        File.Exists(legacySharedKernelEventPath).Should().BeFalse(
            "the integration-event marker should not remain under SharedKernel once the contract seam has been extracted");

        var ordersContractsProjectContent = File.ReadAllText(ordersContractsProjectPath);
        ordersContractsProjectContent.Should().Contain(
            "XYDataLabs.OrderProcessingSystem.Eventing.Abstractions.csproj",
            "Orders contract payloads should depend on the lightweight eventing seam");
        ordersContractsProjectContent.Should().NotContain(
            "XYDataLabs.OrderProcessingSystem.SharedKernel.csproj",
            "Orders contract payloads should not bring SharedKernel platform dependencies into stable transport contracts");

        var paymentsContractsProjectContent = File.ReadAllText(paymentsContractsProjectPath);
        paymentsContractsProjectContent.Should().Contain(
            "XYDataLabs.OrderProcessingSystem.Eventing.Abstractions.csproj",
            "Payments contract payloads should depend on the lightweight eventing seam");
        paymentsContractsProjectContent.Should().NotContain(
            "XYDataLabs.OrderProcessingSystem.SharedKernel.csproj",
            "Payments contract payloads should not bring SharedKernel platform dependencies into stable transport contracts");
    }

    [Fact]
    public void ServiceDefaults_Should_Not_Reference_SharedKernel_Project()
    {
        var solutionRoot = FindSolutionRoot();
        var projectPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.ServiceDefaults",
            "XYDataLabs.OrderProcessingSystem.ServiceDefaults.csproj");
        var extensionsPath = Path.Combine(
            solutionRoot,
            "XYDataLabs.OrderProcessingSystem.ServiceDefaults",
            "ServiceDefaultsExtensions.cs");

        var projectContent = File.ReadAllText(projectPath);
        projectContent.Should().NotContain(
            "XYDataLabs.OrderProcessingSystem.SharedKernel.csproj",
            "ServiceDefaults must stay platform-only instead of inheriting domain or business-layer dependencies through SharedKernel");

        var extensionsContent = File.ReadAllText(extensionsPath);
        extensionsContent.Should().NotContain(
            "SharedKernel",
            "ServiceDefaults should bootstrap platform observability directly instead of importing SharedKernel observability helpers");
    }

    [Fact]
    public void Business_Route_Controllers_Should_Be_ModuleOwned_And_The_Transitional_Monolith_Should_Only_Expose_Operations_Admin()
    {
        var solutionRoot = FindSolutionRoot();

        GetControllerNames(solutionRoot, Path.Combine("XYDataLabs.OrderProcessingSystem.API", "Controllers"))
            .Should().BeEquivalentTo(
                [],
                "the transitional monolithic API should not retain business or operations controllers once the Phase 10 stack owns those routes through module APIs");

        GetControllerNames(solutionRoot, Path.Combine("XYDataLabs.OrderProcessingSystem.Orders.API", "Controllers"))
            .Should().BeEquivalentTo(
                ["AuditController.cs", "CustomerController.cs", "DlqAdminController.cs", "InfoController.cs", "OrderController.cs"],
                "the transitional replay approval endpoint now rides with the Orders-hosted API surface so the Phase 10 local identity and authorization proof can exercise a real protected endpoint");

        GetControllerNames(solutionRoot, Path.Combine("XYDataLabs.OrderProcessingSystem.Payments.API", "Controllers"))
            .Should().BeEquivalentTo(
                ["PaymentCallbackController.cs", "PaymentsController.cs", "WebhookController.cs"],
                "Payments should own payment processing, callback, and webhook routes");

        GetControllerNames(solutionRoot, Path.Combine("XYDataLabs.OrderProcessingSystem.Inventory.API", "Controllers"))
            .Should().BeEquivalentTo(
                ["InventoryController.cs", "ProductController.cs"],
                "Inventory should own inventory and product routes");

        GetControllerNames(solutionRoot, Path.Combine("XYDataLabs.OrderProcessingSystem.Notifications.API", "Controllers"))
            .Should().BeEquivalentTo(
                ["NotificationsController.cs"],
                "Notifications should own the notification delivery routes");
    }

    [Fact]
    public void CrossContext_Table_Access_Should_Be_Explicitly_Allowlisted_And_Limited_To_Known_Phase10_Exceptions()
    {
        var solutionRoot = FindSolutionRoot();
        var exceptionManifestPath = Path.Combine(
            solutionRoot,
            "docs",
            "internal",
            "phase10-architecture-exception-manifest.md");

        File.Exists(exceptionManifestPath).Should().BeTrue(
            "Phase 10 requires an explicit exception manifest for any temporary cross-context data access that still remains during cutover");

        var exceptionManifestContent = File.ReadAllText(exceptionManifestPath);
        exceptionManifestContent.Should().Contain("## Active Exceptions");
        exceptionManifestContent.Should().Contain("None.");

        var moduleOwnership = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal)
        {
            ["Orders"] =
            [
                "AuditLogs",
                "Customers",
                "Orders",
                "OrderProducts"
            ],
            ["Payments"] =
            [
                "BillingCustomers",
                "BillingCustomerKeyInfos",
                "CardTransactions",
                "PaymentAttempts",
                "PaymentAttemptHistories",
                "PaymentMethods",
                "PaymentProviders",
                "PayinLogs",
                "PayinLogDetails",
                "TransactionStatusHistories"
            ],
            ["Inventory"] =
            [
                "InventoryReservations",
                "Products"
            ],
            ["Notifications"] =
            [
                "NotificationDeliveries"
            ]
        };

        var explicitAllowlist = Array.Empty<CrossContextException>();

        if (explicitAllowlist.Length > 0)
        {
            explicitAllowlist.Should().OnlyContain(entry =>
                    !string.IsNullOrWhiteSpace(entry.Module) &&
                    !string.IsNullOrWhiteSpace(entry.DbSet) &&
                    !string.IsNullOrWhiteSpace(entry.RelativePath) &&
                    !string.IsNullOrWhiteSpace(entry.Reason) &&
                    !string.IsNullOrWhiteSpace(entry.ReplacementDesign) &&
                    !string.IsNullOrWhiteSpace(entry.RemovalMilestone),
                "every temporary exception must record owner, reason, location, replacement design, and removal milestone");
        }

        var knownDbSets = moduleOwnership.Values
            .SelectMany(static items => items)
            .ToHashSet(StringComparer.Ordinal);

        var moduleFolders = new Dictionary<string, string[]>(StringComparer.Ordinal)
        {
            ["Orders"] =
            [
                Path.Combine(solutionRoot, "XYDataLabs.OrderProcessingSystem.Orders.Features"),
                Path.Combine(solutionRoot, "XYDataLabs.OrderProcessingSystem.Orders.Infrastructure")
            ],
            ["Payments"] =
            [
                Path.Combine(solutionRoot, "XYDataLabs.OrderProcessingSystem.Payments.Features"),
                Path.Combine(solutionRoot, "XYDataLabs.OrderProcessingSystem.Payments.Infrastructure")
            ],
            ["Inventory"] =
            [
                Path.Combine(solutionRoot, "XYDataLabs.OrderProcessingSystem.Inventory.Features"),
                Path.Combine(solutionRoot, "XYDataLabs.OrderProcessingSystem.Inventory.Infrastructure")
            ],
            ["Notifications"] =
            [
                Path.Combine(solutionRoot, "XYDataLabs.OrderProcessingSystem.Notifications.Features"),
                Path.Combine(solutionRoot, "XYDataLabs.OrderProcessingSystem.Notifications.Infrastructure")
            ]
        };

        var dbSetAccessPattern = new System.Text.RegularExpressions.Regex(
            @"\b(?:_context|_dbContext|dbContext|context)\.(?<dbset>\w+)\b",
            System.Text.RegularExpressions.RegexOptions.Compiled | System.Text.RegularExpressions.RegexOptions.ExplicitCapture);

        var unexpectedViolations = new List<string>();
        var observedAllowlistEntries = new HashSet<string>(StringComparer.Ordinal);

        foreach (var moduleFolder in moduleFolders)
        {
            var ownedDbSets = moduleOwnership[moduleFolder.Key];
            foreach (var directory in moduleFolder.Value.Where(Directory.Exists))
            {
                foreach (var file in Directory.EnumerateFiles(directory, "*.cs", SearchOption.AllDirectories))
                {
                    var relativePath = Path.GetRelativePath(solutionRoot, file).Replace('\\', '/');
                    var content = File.ReadAllText(file);
                    foreach (System.Text.RegularExpressions.Match match in dbSetAccessPattern.Matches(content))
                    {
                        var dbSetName = match.Groups["dbset"].Value;
                        if (!knownDbSets.Contains(dbSetName) || ownedDbSets.Contains(dbSetName))
                        {
                            continue;
                        }

                        var allowlisted = explicitAllowlist.FirstOrDefault(entry =>
                            string.Equals(entry.Module, moduleFolder.Key, StringComparison.Ordinal) &&
                            string.Equals(entry.DbSet, dbSetName, StringComparison.Ordinal) &&
                            string.Equals(entry.RelativePath, relativePath, StringComparison.Ordinal));

                        if (allowlisted is null)
                        {
                            unexpectedViolations.Add($"{moduleFolder.Key}: {relativePath} -> {dbSetName}");
                            continue;
                        }

                        observedAllowlistEntries.Add($"{allowlisted.Module}|{allowlisted.DbSet}|{allowlisted.RelativePath}");
                    }
                }
            }
        }

        unexpectedViolations.Should().BeEmpty(
            "Phase 10 should fail immediately when a module starts reading another module's tables without an explicit temporary exception");

        observedAllowlistEntries.Should().BeEquivalentTo(
            explicitAllowlist.Select(entry => $"{entry.Module}|{entry.DbSet}|{entry.RelativePath}"),
            "the temporary exception allowlist should stay tight and should be removed as soon as the replacement seam is implemented");
    }

    private static string FindSolutionRoot()
    {
        var dir = AppContext.BaseDirectory;
        while (dir is not null)
        {
            if (Directory.GetFiles(dir, "*.sln").Length > 0)
            {
                return dir;
            }

            dir = Directory.GetParent(dir)?.FullName;
        }

        throw new InvalidOperationException("Could not find solution root directory.");
    }

    private static string[] GetControllerNames(string solutionRoot, string relativeDirectory)
    {
        var directory = Path.Combine(solutionRoot, relativeDirectory);
        return Directory.Exists(directory)
            ? Directory.EnumerateFiles(directory, "*.cs", SearchOption.TopDirectoryOnly)
                .Select(static path => Path.GetFileName(path)!)
                .OrderBy(static item => item, StringComparer.Ordinal)
                .ToArray()
            : [];
    }

    private sealed record CrossContextException(
        string Module,
        string DbSet,
        string RelativePath,
        string Reason,
        string ReplacementDesign,
        string RemovalMilestone);
}
