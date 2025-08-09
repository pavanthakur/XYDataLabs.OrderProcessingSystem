# Enterprise Docker Setup Guide

## Overview

This document provides comprehensive instructions for deploying the XYDataLabs Order Processing System using enterprise-ready Docker configurations across development, UAT, and production environments.

## 🏗️ Architecture

### Multi-Environment Strategy

```
docker-compose.yml           # Base configuration (production defaults)
├── docker-compose.dev.yml   # Development overrides
├── docker-compose.uat.yml   # UAT/Staging overrides  
└── docker-compose.prod.yml  # Production overrides
```

### Environment Characteristics

| Environment | Target Use | Key Features |
|-------------|------------|--------------|
| **Development** | Local development | Hot reload, source mounting, debug config |
| **UAT** | Staging/Testing | Production-like, resource limits, enhanced monitoring |
| **Production** | Live deployment | High availability, scaling, security hardening |

## 🚀 Quick Start

### Development Environment
```powershell
# Start development environment with HTTP
.\start-docker.ps1

# Start development environment with HTTPS
.\start-docker.ps1 -Environment dev -Profile https

# Stop development services
.\start-docker.ps1 -Environment dev -Down
```

### UAT Environment
```powershell
# Start UAT environment for testing
.\start-docker.ps1 -Environment uat -Profile https

# Stop UAT services
.\start-docker.ps1 -Environment uat -Down
```

### Production Environment
```powershell
# Start production environment
.\start-docker.ps1 -Environment prod -Profile all

# Stop production services
.\start-docker.ps1 -Environment prod -Down
```

## 📋 Environment Details

### Development Configuration (`dev`)

**Features:**
- Hot reload enabled for rapid development
- Source code mounted as volumes for live changes
- Debug-friendly logging and configuration
- Fast startup times optimized for development workflow

**Services:**
- Target: `dev` stage in Dockerfiles
- Environment: `Development`
- Volumes: Source code mounted for live editing
- Network: Bridge networking for local development

**Usage:**
```powershell
.\start-docker.ps1 -Environment dev -Profile http
```

### UAT Configuration (`uat`)

**Features:**
- Production-like environment for comprehensive testing
- Resource limits to simulate production constraints
- Enhanced health checks and monitoring
- Separate UAT database connections

**Services:**
- Target: `final` stage (production build)
- Environment: `Staging`
- Resource Limits: CPU and memory constraints
- Health Checks: Comprehensive monitoring

**Usage:**
```powershell
.\start-docker.ps1 -Environment uat -Profile https
```

### Production Configuration (`prod`)

**Features:**
- High availability with service replicas
- Resource limits and reservations for optimal performance
- Advanced monitoring and restart policies
- Security-hardened configuration

**Services:**
- Target: `final` stage (optimized production build)
- Environment: `Production`
- Replicas: 2 instances per service for high availability
- Resource Management: CPU/memory limits and reservations
- Security: Production certificates and security policies

**Usage:**
```powershell
.\start-docker.ps1 -Environment prod -Profile all
```

## 🔧 Configuration Management

### Port Configuration

All port configuration is managed through `sharedsettings.json`:

```json
{
  "ApiSettings": {
    "API": {
      "http": { "Port": 5000 },
      "https": { "Port": 5001 }
    },
    "UI": {
      "http": { "Port": 5002 },
      "https": { "Port": 5003 }
    }
  }
}
```

### Environment Variables

The `start-docker.ps1` script automatically generates `.env` file:

```properties
API_HTTP_PORT=5000
API_HTTPS_PORT=5001
UI_HTTP_PORT=5002
UI_HTTPS_PORT=5003
```

## 📊 Monitoring & Health Checks

### Health Check Endpoints

| Service | HTTP | HTTPS |
|---------|------|-------|
| API | http://localhost:5000/health | https://localhost:5001/health |
| UI | http://localhost:5002/health | https://localhost:5003/health |

### Container Status
```powershell
# View running containers
docker ps

# View container logs
docker-compose logs -f api
docker-compose logs -f ui
```

## 🔒 Security Considerations

### Development Security
- Self-signed certificates for HTTPS testing
- Local-only network access
- Debug information enabled

### UAT Security
- Production-like certificate validation
- Limited resource access
- Enhanced logging for audit trails

### Production Security
- Valid SSL certificates required
- Resource constraints enforced
- Security policies applied
- Limited container privileges

## 🚀 Deployment Strategies

### Development Deployment
1. Pull latest code changes
2. Start development environment
3. Verify hot reload functionality
4. Run development tests

### UAT Deployment
1. Deploy latest stable build
2. Start UAT environment with production-like settings
3. Execute comprehensive test suites
4. Validate performance under resource constraints

### Production Deployment
1. Deploy tested and approved builds only
2. Start production environment with high availability
3. Verify health checks and monitoring
4. Implement blue-green deployment if needed

## 🔧 Troubleshooting

### Common Issues

**Port Conflicts:**
```powershell
# Check port usage
netstat -an | findstr :5000

# Stop conflicting services
.\start-docker.ps1 -Down
```

**Container Issues:**
```powershell
# View container logs
docker-compose -f docker-compose.yml -f docker-compose.dev.yml logs api

# Restart specific service
docker-compose restart api
```

**Resource Issues (Production):**
```powershell
# Check resource usage
docker stats

# Scale services if needed
docker-compose up --scale api=3
```

## 📈 Scaling Considerations

### Development
- Single instance per service
- Minimal resource allocation
- Fast startup prioritized

### UAT
- Resource limits to test performance
- Single instance with monitoring
- Production-like constraints

### Production
- Multiple replicas for high availability
- Resource reservations and limits
- Load balancing and health checks
- Auto-restart policies

## 🔄 Migration Path

### From Development to UAT
1. Test in development environment
2. Build and tag stable images
3. Deploy to UAT with production-like settings
4. Execute comprehensive testing

### From UAT to Production
1. Validate UAT testing results
2. Promote tested images to production
3. Deploy with high availability configuration
4. Monitor performance and health metrics

## 📚 Additional Resources

- [SharedSettings Configuration Guide](LearningHelp/sharedsettingsHelp.md)
- [Docker Help Documentation](LearningHelp/DockerHelp.md)
- [API Documentation](XYDataLabs.OrderProcessingSystem.API/README.md)

## 🤝 Support

For technical support or questions about this enterprise Docker setup:

1. Check the troubleshooting section above
2. Review container logs for error details
3. Verify environment-specific configuration files
4. Contact the development team with specific error messages
