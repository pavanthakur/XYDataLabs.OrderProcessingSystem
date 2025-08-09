# See https://aka.ms/customizecontainer to learn how to customize your debug container and how Visual Studio uses this Dockerfile to build your images for faster debugging.

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
# Expose HTTP and HTTPS - these will be overridden by Docker Compose
EXPOSE 8080 8081

# Add better health check using curl (will be configured by Docker Compose)
RUN apt-get update && apt-get install -y curl tzdata && rm -rf /var/lib/apt/lists/*
ENV TZ=Asia/Kolkata
RUN ln -snf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime && echo "Asia/Kolkata" > /etc/timezone

# Ensure compatibility with launchSettings.json and Program.cs
# Add environment variables for development and debugging
ENV DOTNET_USE_POLLING_FILE_WATCHER=true
ENV DOTNET_HOSTBUILDER__RELOADCONFIGONCHANGE=true

# Ensure the container runs with a non-root user for security
RUN adduser --disabled-password --gecos "" appuser && chown -R appuser /app
RUN mkdir -p /logs && chown -R appuser:appuser /logs
USER appuser

# This stage is used to build the service project
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src

# Copy all project files for dependency resolution
COPY ["XYDataLabs.OrderProcessingSystem.UI/XYDataLabs.OrderProcessingSystem.UI.csproj", "XYDataLabs.OrderProcessingSystem.UI/"]
COPY ["XYDataLabs.OrderProcessingSystem.Utilities/XYDataLabs.OrderProcessingSystem.Utilities.csproj", "XYDataLabs.OrderProcessingSystem.Utilities/"]

# Restore dependencies
RUN dotnet restore "./XYDataLabs.OrderProcessingSystem.UI/XYDataLabs.OrderProcessingSystem.UI.csproj"

# Copy all source code
COPY . . 
WORKDIR "/src/XYDataLabs.OrderProcessingSystem.UI"
RUN dotnet build "./XYDataLabs.OrderProcessingSystem.UI.csproj" -c $BUILD_CONFIGURATION -o /app/build

# This stage is specifically for development with volume mounts
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS dev
WORKDIR /app
RUN mkdir -p /logs && chown -R appuser:appuser /logs

# Copy all project files for dependency resolution
COPY ["XYDataLabs.OrderProcessingSystem.UI/XYDataLabs.OrderProcessingSystem.UI.csproj", "./"]
COPY ["XYDataLabs.OrderProcessingSystem.Utilities/XYDataLabs.OrderProcessingSystem.Utilities.csproj", "../XYDataLabs.OrderProcessingSystem.Utilities/"]

RUN dotnet restore "XYDataLabs.OrderProcessingSystem.UI.csproj"

# Remove hardcoded ports - let Docker Compose environment variables control this
ENV DOTNET_RUNNING_IN_CONTAINER=true
ENV DOTNET_WATCH_RESTART_ON_RUDE_EDIT=1
ENV DOTNET_USE_POLLING_FILE_WATCHER=1

ENTRYPOINT ["dotnet", "watch", "run", "--no-restore"]

# This stage is used to publish the service project to be copied to the final stage
FROM build AS publish
ARG BUILD_CONFIGURATION=Release
RUN dotnet publish "./XYDataLabs.OrderProcessingSystem.UI.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false

# This stage is used in production or when running from VS in regular mode (Default when not using the Debug configuration)
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
# Note: sharedsettings.json and certificate copying is handled by docker-compose volumes
# Remove hardcoded ports - let Docker Compose environment variables control this
RUN mkdir -p /logs && chown -R appuser:appuser /logs
ENV DOTNET_RUNNING_IN_CONTAINER=true
ENTRYPOINT ["dotnet", "XYDataLabs.OrderProcessingSystem.UI.dll"]