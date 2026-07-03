FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 8080

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["XYDataLabs.OrderProcessingSystem.Gateway/XYDataLabs.OrderProcessingSystem.Gateway.csproj", "XYDataLabs.OrderProcessingSystem.Gateway/"]
COPY ["XYDataLabs.OrderProcessingSystem.ServiceDefaults/XYDataLabs.OrderProcessingSystem.ServiceDefaults.csproj", "XYDataLabs.OrderProcessingSystem.ServiceDefaults/"]
RUN dotnet restore "./XYDataLabs.OrderProcessingSystem.Gateway/XYDataLabs.OrderProcessingSystem.Gateway.csproj"
COPY . .
WORKDIR "/src/XYDataLabs.OrderProcessingSystem.Gateway"
RUN dotnet publish "./XYDataLabs.OrderProcessingSystem.Gateway.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=build /app/publish .
ENV ASPNETCORE_URLS=http://+:8080
ENTRYPOINT ["dotnet", "XYDataLabs.OrderProcessingSystem.Gateway.dll"]
