FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 8080

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY . .
RUN dotnet restore "XYDataLabs.OrderProcessingSystem.Orders.Host/XYDataLabs.OrderProcessingSystem.Orders.Host.csproj"
RUN dotnet publish "XYDataLabs.OrderProcessingSystem.Orders.Host/XYDataLabs.OrderProcessingSystem.Orders.Host.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=build /app/publish .
ENV ASPNETCORE_URLS=http://+:8080
ENTRYPOINT ["dotnet", "XYDataLabs.OrderProcessingSystem.Orders.Host.dll"]
