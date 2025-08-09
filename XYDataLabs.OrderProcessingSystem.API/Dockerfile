# See https://aka.ms/customizecontainer to learn how to customize your debug container and how Visual Studio uses this Dockerfile to build your images for faster debugging.

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
# Expose HTTP and HTTPS - these will be overridden by Docker Compose
EXPOSE 8080 8081

# Add health check using curl (will be configured by Docker Compose)
# Align timezone with UI container (Asia/Kolkata) so log timestamps match
RUN apt-get update && apt-get install -y curl tzdata && rm -rf /var/lib/apt/lists/*
ENV TZ=Asia/Kolkata
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo "$TZ" > /etc/timezone
RUN mkdir -p /logs

# This stage is used to build the service project
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src

# Copy all project files for dependency resolution
COPY ["XYDataLabs.OrderProcessingSystem.API/XYDataLabs.OrderProcessingSystem.API.csproj", "XYDataLabs.OrderProcessingSystem.API/"]
COPY ["XYDataLabs.OrderProcessingSystem.Application/XYDataLabs.OrderProcessingSystem.Application.csproj", "XYDataLabs.OrderProcessingSystem.Application/"]
COPY ["XYDataLabs.OrderProcessingSystem.Domain/XYDataLabs.OrderProcessingSystem.Domain.csproj", "XYDataLabs.OrderProcessingSystem.Domain/"]
COPY ["XYDataLabs.OrderProcessingSystem.Infrastructure/XYDataLabs.OrderProcessingSystem.Infrastructure.csproj", "XYDataLabs.OrderProcessingSystem.Infrastructure/"]
COPY ["XYDataLabs.OrderProcessingSystem.Utilities/XYDataLabs.OrderProcessingSystem.Utilities.csproj", "XYDataLabs.OrderProcessingSystem.Utilities/"]
COPY ["XYDataLabs.OpenPayAdapter/XYDataLabs.OpenPayAdapter.csproj", "XYDataLabs.OpenPayAdapter/"]

# Restore dependencies
RUN dotnet restore "./XYDataLabs.OrderProcessingSystem.API/XYDataLabs.OrderProcessingSystem.API.csproj"

# Copy all source code
COPY . .
WORKDIR "/src/XYDataLabs.OrderProcessingSystem.API"
RUN dotnet build "./XYDataLabs.OrderProcessingSystem.API.csproj" -c $BUILD_CONFIGURATION -o /app/build

# This stage is used to publish the service project to be copied to the final stage
FROM build AS publish
ARG BUILD_CONFIGURATION=Release
RUN dotnet publish "./XYDataLabs.OrderProcessingSystem.API.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false

# This stage is specifically for development with volume mounts
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS dev
WORKDIR /app
# Align timezone with UI for dev/watch scenario as well
RUN apt-get update && apt-get install -y tzdata && rm -rf /var/lib/apt/lists/*
ENV TZ=Asia/Kolkata
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo "$TZ" > /etc/timezone

# Copy all project files for dependency resolution
COPY ["XYDataLabs.OrderProcessingSystem.API/XYDataLabs.OrderProcessingSystem.API.csproj", "./"]
COPY ["XYDataLabs.OrderProcessingSystem.Application/XYDataLabs.OrderProcessingSystem.Application.csproj", "../XYDataLabs.OrderProcessingSystem.Application/"]
COPY ["XYDataLabs.OrderProcessingSystem.Domain/XYDataLabs.OrderProcessingSystem.Domain.csproj", "../XYDataLabs.OrderProcessingSystem.Domain/"]
COPY ["XYDataLabs.OrderProcessingSystem.Infrastructure/XYDataLabs.OrderProcessingSystem.Infrastructure.csproj", "../XYDataLabs.OrderProcessingSystem.Infrastructure/"]
COPY ["XYDataLabs.OrderProcessingSystem.Utilities/XYDataLabs.OrderProcessingSystem.Utilities.csproj", "../XYDataLabs.OrderProcessingSystem.Utilities/"]
COPY ["XYDataLabs.OpenPayAdapter/XYDataLabs.OpenPayAdapter.csproj", "../XYDataLabs.OpenPayAdapter/"]

RUN dotnet restore "XYDataLabs.OrderProcessingSystem.API.csproj"

# Remove hardcoded ports - let Docker Compose environment variables control this
ENV DOTNET_RUNNING_IN_CONTAINER=true
ENV DOTNET_WATCH_RESTART_ON_RUDE_EDIT=1
ENV DOTNET_USE_POLLING_FILE_WATCHER=1

ENTRYPOINT ["dotnet", "watch", "run", "--no-restore"]

# This stage is used for debugging (development)
FROM build AS debug
WORKDIR /app
COPY --from=build /app/build .
ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_HTTP_PORTS=8080
ENV DOTNET_RUNNING_IN_CONTAINER=true
ENTRYPOINT ["dotnet", "XYDataLabs.OrderProcessingSystem.API.dll"]

# This stage is used in production
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
# Note: sharedsettings.json and certificate copying is handled by docker-compose volumes
# Remove hardcoded ports - let Docker Compose environment variables control this
ENV DOTNET_RUNNING_IN_CONTAINER=true
ENTRYPOINT ["dotnet", "XYDataLabs.OrderProcessingSystem.API.dll"]