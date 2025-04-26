# See https://aka.ms/customizecontainer to learn how to customize your debug container and how Visual Studio uses this Dockerfile to build your images for faster debugging.

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 8080 8081

# Add health check using curl
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl --fail http://localhost:8080/swagger || exit 1

# This stage is used to build the service project
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src
COPY ["XYDataLabs.OrderProcessingSystem.API/XYDataLabs.OrderProcessingSystem.API.csproj", "XYDataLabs.OrderProcessingSystem.API/"]
RUN dotnet restore "./XYDataLabs.OrderProcessingSystem.API/XYDataLabs.OrderProcessingSystem.API.csproj"
COPY . .
WORKDIR "/src/XYDataLabs.OrderProcessingSystem.API"
RUN dotnet build "./XYDataLabs.OrderProcessingSystem.API.csproj" -c $BUILD_CONFIGURATION -o /app/build

# This stage is used to publish the service project to be copied to the final stage
FROM build AS publish
ARG BUILD_CONFIGURATION=Release
RUN dotnet publish "./XYDataLabs.OrderProcessingSystem.API.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false

# This stage is used in production
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .

# Set environment variables for configuration
ENV ASPNETCORE_URLS=http://+:8080;https://+:8081
ENV ASPNETCORE_HTTP_PORTS=8080
ENV ASPNETCORE_HTTPS_PORTS=8081
ENV DOTNET_RUNNING_IN_CONTAINER=true

ENTRYPOINT ["dotnet", "XYDataLabs.OrderProcessingSystem.API.dll"]