FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY ["Directory.Build.props", "."]
COPY ["Directory.Packages.props", "."]
COPY ["XYDataLabs.OrderProcessingSystem.SharedKernel/XYDataLabs.OrderProcessingSystem.SharedKernel.csproj", "XYDataLabs.OrderProcessingSystem.SharedKernel/"]
COPY ["XYDataLabs.OrderProcessingSystem.Domain/XYDataLabs.OrderProcessingSystem.Domain.csproj", "XYDataLabs.OrderProcessingSystem.Domain/"]
COPY ["XYDataLabs.OrderProcessingSystem.Application/XYDataLabs.OrderProcessingSystem.Application.csproj", "XYDataLabs.OrderProcessingSystem.Application/"]
COPY ["XYDataLabs.OrderProcessingSystem.Infrastructure/XYDataLabs.OrderProcessingSystem.Infrastructure.csproj", "XYDataLabs.OrderProcessingSystem.Infrastructure/"]
COPY ["XYDataLabs.OrderProcessingSystem.Orders.API/XYDataLabs.OrderProcessingSystem.Orders.API.csproj", "XYDataLabs.OrderProcessingSystem.Orders.API/"]
COPY ["XYDataLabs.OrderProcessingSystem.Inventory.API/XYDataLabs.OrderProcessingSystem.Inventory.API.csproj", "XYDataLabs.OrderProcessingSystem.Inventory.API/"]
COPY ["XYDataLabs.OrderProcessingSystem.Notifications.API/XYDataLabs.OrderProcessingSystem.Notifications.API.csproj", "XYDataLabs.OrderProcessingSystem.Notifications.API/"]
COPY ["XYDataLabs.OrderProcessingSystem.Payments.API/XYDataLabs.OrderProcessingSystem.Payments.API.csproj", "XYDataLabs.OrderProcessingSystem.Payments.API/"]
COPY ["XYDataLabs.OrderProcessingSystem.Functions/XYDataLabs.OrderProcessingSystem.Functions.csproj", "XYDataLabs.OrderProcessingSystem.Functions/"]
RUN dotnet restore "XYDataLabs.OrderProcessingSystem.Functions/XYDataLabs.OrderProcessingSystem.Functions.csproj"

COPY . .
RUN dotnet publish "XYDataLabs.OrderProcessingSystem.Functions/XYDataLabs.OrderProcessingSystem.Functions.csproj" -c Release -o /home/site/wwwroot --no-restore

FROM mcr.microsoft.com/azure-functions/dotnet-isolated:4-dotnet-isolated8.0 AS final
WORKDIR /home/site/wwwroot
COPY --from=build /home/site/wwwroot .
