# XYDataLabs Order Processing System - Enterprise Edition

![Build Status](https://img.shields.io/badge/build-passing-green)
![Quality Gate](https://img.shields.io/badge/quality%20gate-passed-green)
![Coverage](https://img.shields.io/badge/coverage-80%25-green)
![.NET](https://img.shields.io/badge/.NET-8.0-blue)

An enterprise-grade order processing system built with Clean Architecture principles and modern .NET practices.

## 🏗️ Architecture

This solution follows **Clean Architecture** principles with clear separation of concerns:

```
├── Domain/           # Pure business logic, no dependencies
├── Application/      # Use cases, interfaces, DTOs
├── Infrastructure/   # Data access, external services
├── API/             # RESTful API controllers
├── UI/              # MVC presentation layer
├── Utilities/       # Shared utilities and helpers
├── OpenPayAdapter/  # Payment processing integration
└── UnitTest/        # Comprehensive test suite
```

## 🚀 Quick Start

### Prerequisites
- .NET 9.0 SDK
- SQL Server or Docker
- Visual Studio 2022 or VS Code

### Building the Solution

**For Development (Visual Studio):**
```bash
# Use the full solution with Docker Compose support
dotnet build XYDataLabs.OrderProcessingSystem.sln
```

**For CI/CD and Command Line:**
```bash
# Use the CI-friendly solution (no Docker Compose project)
dotnet build XYDataLabs.OrderProcessingSystem.CI.sln

# Or use our build scripts
.\quick-build.ps1 Build          # Quick build
.\build.ps1 All                  # Full enterprise build pipeline
```

### Running the Application

**Local Development:**
```bash
# Start dependencies with Docker Compose
docker-compose up -d

# Run API
dotnet run --project XYDataLabs.OrderProcessingSystem.API

# Run UI (separate terminal)
dotnet run --project XYDataLabs.OrderProcessingSystem.UI
```

**Docker Development:**
```bash
# Use our enhanced startup script
.\start-docker-enhanced.ps1
```

## 🏢 Enterprise Features

### Code Quality & Standards
- ✅ **StyleCop Analyzers** - Enforces coding standards
- ✅ **Microsoft Code Analysis** - Security and performance rules
- ✅ **SonarAnalyzer** - Code quality and maintainability
- ✅ **Banned API Analyzers** - Prevents insecure API usage
- ✅ **EditorConfig** - Consistent formatting across teams
- ✅ **Centralized Package Management** - Directory.Packages.props

### Observability & Monitoring
- ✅ **Structured Logging** - Serilog with enrichers
- ✅ **Consistent Log Format** - Environment, Application, Runtime tracking
- ✅ **Timezone Standardization** - Asia/Kolkata across all containers
- ✅ **Health Checks** - API and database monitoring
- 🔄 **OpenTelemetry** - Distributed tracing (coming soon)
- 🔄 **Metrics & Dashboards** - Performance monitoring (coming soon)

### Security & Compliance
- ✅ **Banned Symbols** - Prevents insecure code patterns
- ✅ **Security Rules** - CA rules for SQL injection, XSS prevention
- 🔄 **Authentication & Authorization** - JWT with refresh tokens (coming soon)
- 🔄 **Data Protection** - Encryption at rest and in transit (coming soon)
- 🔄 **Secrets Management** - Azure Key Vault integration (coming soon)

### Testing Strategy
- ✅ **Unit Tests** - Comprehensive test coverage
- ✅ **Test Data Generation** - Bogus for realistic test data
- ✅ **Mocking Framework** - Moq for dependencies
- 🔄 **Integration Tests** - API and database testing (coming soon)
- 🔄 **Contract Tests** - API contract verification (coming soon)
- 🔄 **Load Testing** - Performance validation (coming soon)

### DevOps & Automation
- ✅ **Multi-Solution Strategy** - Dev and CI solutions
- ✅ **Build Automation** - PowerShell scripts for all scenarios
- ✅ **Docker Support** - Multi-stage builds, health checks
- 🔄 **GitHub Actions** - CI/CD pipeline (coming soon)
- 🔄 **Infrastructure as Code** - Kubernetes/Helm charts (coming soon)

## 📋 Build Scripts

We provide multiple build scripts for different scenarios:

### Quick Build (Development)
```bash
.\quick-build.ps1 [Clean|Build|Test|All]
```

### Enterprise Build (CI/CD)
```bash
.\build.ps1 [Clean|Restore|Build|Test|Pack|Publish|All] 
  -Configuration [Debug|Release]
  -OutputPath "./artifacts"
  -SkipTests
  -GenerateCodeCoverage
  -TestFilter "Category=Unit"
```

Examples:
```bash
# Quick development build
.\quick-build.ps1 Build

# Full CI pipeline
.\build.ps1 All -Configuration Release -GenerateCodeCoverage

# Run only unit tests
.\build.ps1 Test -TestFilter "Category=Unit"

# Package for deployment
.\build.ps1 Pack -Configuration Release
```

## 🗂️ Solution Structure

### Dual Solution Approach
- **XYDataLabs.OrderProcessingSystem.sln** - Full solution for Visual Studio development
- **XYDataLabs.OrderProcessingSystem.CI.sln** - CI-friendly solution without Docker Compose

This approach ensures:
- Visual Studio developers get full Docker Compose integration
- CI/CD pipelines have clean, fast builds without docker-compose.dcproj issues
- Cross-platform compatibility for `dotnet` CLI commands

### Package Management
- **Directory.Packages.props** - Centralized version management
- **Directory.Build.props** - Shared MSBuild properties and analyzers
- **global.json** - SDK version pinning
- **.editorconfig** - Code formatting and style rules

## 🔧 Configuration

### Environment-Specific Settings
```
sharedsettings.dev.json     # Development configuration
sharedsettings.uat.json     # User acceptance testing
sharedsettings.prod.json    # Production configuration
```

### Docker Environments
```bash
docker-compose.yml          # Base configuration
docker-compose.dev.yml      # Development overrides
docker-compose.uat.yml      # UAT overrides  
docker-compose.prod.yml     # Production overrides
```

## 📊 Monitoring & Logging

### Log Locations
- **Local Development**: `logs/` directory
- **Docker**: Mounted volumes to host `logs/` directory
- **Format**: Structured JSON with timestamp, level, message, and context

### Health Checks
- **API Health**: `https://localhost:7001/health`
- **Database**: Connection and query validation
- **External Services**: OpenPay integration status

## 🧪 Testing

### Running Tests
```bash
# All tests
dotnet test XYDataLabs.OrderProcessingSystem.CI.sln

# Unit tests only
dotnet test --filter Category=Unit

# With coverage
dotnet test --collect:"XPlat Code Coverage"
```

### Test Categories
- **Unit** - Fast, isolated tests
- **Integration** - Database and API tests
- **E2E** - End-to-end user scenarios

## 🚀 Deployment

### Local Docker
```bash
# Development
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up

# Production simulation
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up
```

### Production Deployment
1. Build release packages: `.\build.ps1 Publish -Configuration Release`
2. Review artifacts in `./artifacts/publish/`
3. Deploy using your preferred container orchestration platform

## 🔮 Roadmap

### Phase 1: Foundation ✅
- [x] Clean Architecture setup
- [x] Code quality analyzers
- [x] Centralized package management
- [x] Build automation
- [x] Structured logging

### Phase 2: Core Patterns (Current)
- [ ] MediatR + CQRS implementation
- [ ] FluentValidation integration
- [ ] Result pattern for error handling
- [ ] Health checks and metrics

### Phase 3: Security & Observability
- [ ] JWT authentication
- [ ] OpenTelemetry tracing
- [ ] Security scanning in CI
- [ ] Performance monitoring

### Phase 4: Advanced Features
- [ ] Event-driven architecture
- [ ] Distributed caching
- [ ] Background job processing
- [ ] API versioning strategy

## 📚 Documentation

- [Docker Setup Guide](DOCKER_COMPREHENSIVE_GUIDE.md)
- [Configuration Guide](ENHANCED_SHAREDSETTINGS_GUIDE.md)
- [Architecture Decisions](docs/architecture/)
- [API Documentation](https://localhost:7001/swagger)

## 🤝 Contributing

1. Follow the established coding standards (enforced by analyzers)
2. Write tests for new functionality
3. Update documentation for significant changes
4. Use the CI solution for validation: `.\quick-build.ps1 All`

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Built with ❤️ by XYDataLabs Engineering Team**
