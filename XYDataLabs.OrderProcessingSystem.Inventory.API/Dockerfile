FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 8080

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["XYDataLabs.OrderProcessingSystem.Inventory.API/XYDataLabs.OrderProcessingSystem.Inventory.API.csproj", "XYDataLabs.OrderProcessingSystem.Inventory.API/"]
RUN dotnet restore "./XYDataLabs.OrderProcessingSystem.Inventory.API/XYDataLabs.OrderProcessingSystem.Inventory.API.csproj"
COPY . .
WORKDIR "/src/XYDataLabs.OrderProcessingSystem.Inventory.API"
RUN dotnet publish "./XYDataLabs.OrderProcessingSystem.Inventory.API.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=build /app/publish .
ENV ASPNETCORE_URLS=http://+:8080
ENTRYPOINT ["dotnet", "XYDataLabs.OrderProcessingSystem.Inventory.API.dll"]
