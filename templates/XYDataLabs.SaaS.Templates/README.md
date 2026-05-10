# XYDataLabs.SaaS.Templates

`XYDataLabs.SaaS.Templates` is the Layer 1 `dotnet new` package for bootstrapping the XYDataLabs multi-tenant SaaS backend solution skeleton.

## What it includes

- .NET 8 Clean Architecture solution layout
- API, Application, Domain, Infrastructure, SharedKernel, and PaymentGateway projects
- Five test projects
- EF Core scaffolding and multi-tenant primitives
- Hand-rolled CQRS skeleton with `Result<T>` patterns
- Architecture guardrails via NetArchTest

## Install

```powershell
dotnet new install XYDataLabs.SaaS.Templates::1.0.0
```

## Create a solution

```powershell
dotnet new xy-saas `
  -n TradingAnalytics `
  --rootNamespace Contoso.TradingAnalytics `
  --companySlug contoso `
  --productSlug tradinganalytics
```

## Important note

The generated template uses a provider-agnostic `PaymentGateway` seam with a default in-memory implementation for bootstrap and smoke validation. Replace that default implementation with a real payment provider before production deployment.