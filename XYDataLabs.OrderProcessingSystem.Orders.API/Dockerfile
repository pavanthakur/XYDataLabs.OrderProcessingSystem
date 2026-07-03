FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 8080

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["XYDataLabs.OrderProcessingSystem.Orders.API/XYDataLabs.OrderProcessingSystem.Orders.API.csproj", "XYDataLabs.OrderProcessingSystem.Orders.API/"]
COPY ["XYDataLabs.OrderProcessingSystem.Domain/XYDataLabs.OrderProcessingSystem.Domain.csproj", "XYDataLabs.OrderProcessingSystem.Domain/"]
RUN dotnet restore "./XYDataLabs.OrderProcessingSystem.Orders.API/XYDataLabs.OrderProcessingSystem.Orders.API.csproj"
COPY . .
WORKDIR "/src/XYDataLabs.OrderProcessingSystem.Orders.API"
RUN dotnet publish "./XYDataLabs.OrderProcessingSystem.Orders.API.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=build /app/publish .
ENV ASPNETCORE_URLS=http://+:8080
ENTRYPOINT ["dotnet", "XYDataLabs.OrderProcessingSystem.Orders.API.dll"]
