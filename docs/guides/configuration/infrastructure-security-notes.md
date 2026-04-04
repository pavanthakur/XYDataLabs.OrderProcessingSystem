# Security Notes for Infrastructure Deployment

## ⚠️ Current Security Considerations

This document outlines security considerations for the current infrastructure implementation and provides recommendations for hardening production deployments.

## SQL Database Credentials

### Current Implementation

**Status**: ⚠️ **Development-Only - NOT Production-Ready**

SQL admin credentials are currently stored in plain text in parameter files:
- `infra/parameters/dev.json`
- `infra/parameters/staging.json`
- `infra/parameters/prod.json`

**Why this is acceptable for development:**
- Quick setup and testing
- Credentials are for development environments only
- Simplified troubleshooting
- Common practice in dev/test scenarios

**Why this is NOT acceptable for production:**
- ❌ Credentials exposed in source control
- ❌ Visible to all developers with repo access
- ❌ Visible in deployment logs
- ❌ Violates least-privilege principle
- ❌ Difficult to rotate credentials
- ❌ Compliance issues (SOC 2, ISO 27001, etc.)

### Recommended Production Solutions

#### Option 1: Azure Key Vault (Recommended for SQL Auth)

**Implementation:**

1. Store SQL admin password in Key Vault:
```bash
az keyvault secret set --vault-name "kv-orderprocessing-prod" --name "sql-admin-password" --value "YourSecurePassword123!"
```

2. Update parameter file to reference Key Vault:
```json
{
  "sqlAdminPassword": {
    "reference": {
      "keyVault": {
        "id": "/subscriptions/{subscriptionId}/resourceGroups/{rgName}/providers/Microsoft.KeyVault/vaults/{vaultName}"
      },
      "secretName": "sql-admin-password"
    }
  }
}
```

**Benefits:**
- ✅ Credentials never in source control
- ✅ Centralized secret management
- ✅ Access controlled via RBAC
- ✅ Audit trail of secret access
- ✅ Automatic rotation support
- ✅ Compliance-ready

#### Option 2: Managed Identity (Most Secure - Recommended)

**Implementation:**

1. Enable Managed Identity on App Services (already done if `enableIdentity: true`)

2. Grant App Service Managed Identity access to SQL:
```sql
CREATE USER [app-service-name] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [app-service-name];
ALTER ROLE db_datawriter ADD MEMBER [app-service-name];
```

3. Update connection string to use Managed Identity:
```
Server=tcp:{server}.database.windows.net,1433;Initial Catalog={database};Authentication=Active Directory Managed Identity;Encrypt=True;
```

**Benefits:**
- ✅ **No passwords needed at all**
- ✅ Azure AD authentication
- ✅ Automatic credential rotation
- ✅ Fine-grained RBAC
- ✅ Best security practice
- ✅ Zero credential management overhead

**Implementation Guide:**
See [Microsoft Documentation](https://learn.microsoft.com/azure/app-service/tutorial-connect-msi-sql-database)

## SQL Server Network Access

### Current Implementation

**Status**: ⚠️ **Development-Only - Consider Hardening**

SQL Server is configured with:
```bicep
publicNetworkAccess: 'Enabled'
```

Firewall rule allows all Azure services:
```bicep
startIpAddress: '0.0.0.0'
endIpAddress: '0.0.0.0'
```

**Why this is acceptable for development:**
- Easy access from Azure resources
- Simplified initial setup
- Works with App Services without additional networking
- Common for dev/test

**Why you might want to harden for production:**
- ⚠️ Broader attack surface
- ⚠️ Any Azure service can attempt connection
- ⚠️ Compliance requirements may require private connectivity
- ⚠️ Best practice is to minimize exposed services

### Recommended Production Solutions

#### Option 1: Restrict Firewall Rules

Add specific IP ranges instead of allowing all Azure:
```bicep
resource restrictedFirewall 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowSpecificAppService'
  properties: {
    startIpAddress: '20.x.x.x' // App Service outbound IP
    endIpAddress: '20.x.x.x'
  }
}
```

Get App Service outbound IPs:
```bash
az webapp show --name {app-name} --resource-group {rg} --query "outboundIpAddresses"
```

#### Option 2: Private Endpoint (Most Secure)

1. Disable public network access:
```bicep
publicNetworkAccess: 'Disabled'
```

2. Create Virtual Network and Subnet

3. Create Private Endpoint for SQL Server

4. Integrate App Service with VNet

**Benefits:**
- ✅ No public internet exposure
- ✅ Traffic stays within Azure backbone
- ✅ Enhanced compliance posture
- ✅ Better performance
- ✅ Defense in depth

**Cost**: Additional charges for Private Endpoints (~$7-10/month per endpoint)

## Connection String Exposure

### Current Implementation

**Status**: ⚠️ **Be Aware - Logged in Deployment Outputs**

Connection string (including password) is output from `sql.bicep`:
```bicep
output connectionString string = 'Server=...;Password=${sqlAdminPassword};...'
```

**Risk:**
- Connection string may appear in:
  - Deployment logs
  - Azure Resource Manager operation logs
  - CI/CD pipeline logs

**Mitigation (Current):**
- Connection string is immediately consumed by hosting module
- Not exposed as top-level output in `main.bicep`
- Configured directly in App Service (not exposed to clients)

**Recommendation for Production:**
- Use Managed Identity (eliminates password entirely)
- Use Key Vault references instead of embedding in connection string
- Enable Log Analytics workspace filtering to exclude sensitive data

## Application Insights

### Current Implementation

**Status**: ✅ **Properly Configured**

Application Insights connection string is:
- Generated by Azure (not user-provided)
- Automatically configured in App Services
- Does not contain secrets (uses instrumentation key)
- Properly secured

**No action needed** - App Insights is correctly implemented.

## GitHub OIDC

### Current Implementation

**Status**: ✅ **Secure by Design**

OIDC federated credentials:
- No secrets stored in GitHub
- Token-based authentication
- Short-lived tokens
- Scoped to specific repositories and branches

**No action needed** - OIDC is secure.

## Deployment Checklist

### Development Environment
- [x] SQL credentials in parameter files (acceptable)
- [x] Public network access enabled (acceptable)
- [x] All Azure services firewall rule (acceptable)
- [x] Application Insights configured
- [x] OIDC configured

### Staging Environment
- [ ] Consider using Key Vault for SQL credentials
- [ ] Review firewall rules
- [ ] Test with production-like security settings
- [x] Application Insights configured

### Production Environment
- [ ] **CRITICAL**: Migrate to Key Vault for SQL credentials
- [ ] **RECOMMENDED**: Implement Managed Identity for SQL
- [ ] **RECOMMENDED**: Restrict SQL firewall rules or use Private Endpoint
- [ ] Enable Azure Defender for SQL
- [ ] Enable diagnostic settings for all resources
- [ ] Set up Azure Policy for compliance
- [ ] Configure alerts for security events
- [ ] Regular vulnerability assessments
- [ ] Implement backup and disaster recovery

## Security Hardening Roadmap

### Phase 1: Credential Management (Priority: HIGH)
1. Create Azure Key Vault per environment
2. Store SQL credentials in Key Vault
3. Update parameter files to reference Key Vault
4. Test deployment with Key Vault references

**Timeline**: 1-2 days
**Impact**: High security improvement, minimal code changes

### Phase 2: Managed Identity (Priority: HIGH)
1. Enable System-Assigned Managed Identity on App Services
2. Configure Azure AD authentication on SQL Server
3. Grant App Service identities SQL permissions
4. Update connection strings to use Managed Identity
5. Remove SQL admin credentials entirely

**Timeline**: 2-3 days
**Impact**: Highest security improvement, eliminates passwords

### Phase 3: Network Security (Priority: MEDIUM)
1. Create Virtual Network and Subnets
2. Create Private Endpoints for SQL Server
3. Integrate App Services with VNet
4. Disable public network access on SQL Server
5. Configure Network Security Groups

**Timeline**: 3-5 days
**Impact**: Medium-high security improvement, increased complexity

### Phase 4: Monitoring & Compliance (Priority: MEDIUM)
1. Enable Azure Defender for SQL
2. Configure security alerts
3. Enable diagnostic settings
4. Set up Log Analytics workspace
5. Configure Azure Policy
6. Regular security assessments

**Timeline**: Ongoing
**Impact**: Continuous security posture improvement

## Compliance Considerations

### Current Posture
- ⚠️ **SOC 2**: Credential management needs improvement
- ⚠️ **ISO 27001**: Network security could be enhanced
- ⚠️ **HIPAA**: Not suitable without hardening
- ⚠️ **PCI-DSS**: Not suitable without hardening
- ✅ **General Best Practices**: Development appropriate

### After Phase 1 (Key Vault)
- ✅ **SOC 2**: Acceptable with proper procedures
- ✅ **ISO 27001**: Good credential management
- ⚠️ **HIPAA**: Additional controls needed
- ⚠️ **PCI-DSS**: Additional controls needed

### After Phase 2 (Managed Identity)
- ✅ **SOC 2**: Excellent credential management
- ✅ **ISO 27001**: Industry best practice
- ✅ **HIPAA**: Good credential posture
- ✅ **PCI-DSS**: Strong authentication

### After Phase 3 (Private Endpoints)
- ✅ **SOC 2**: Comprehensive security
- ✅ **ISO 27001**: Excellent network security
- ✅ **HIPAA**: Strong network isolation
- ✅ **PCI-DSS**: Network segmentation achieved

## Resources

### Microsoft Documentation
- [Azure SQL Security Best Practices](https://learn.microsoft.com/azure/azure-sql/database/security-best-practice)
- [Managed Identity for SQL](https://learn.microsoft.com/azure/app-service/tutorial-connect-msi-sql-database)
- [Azure Key Vault Integration](https://learn.microsoft.com/azure/key-vault/general/overview)
- [Private Endpoints](https://learn.microsoft.com/azure/private-link/private-endpoint-overview)
- [Azure Security Baseline](https://learn.microsoft.com/security/benchmark/azure/baselines/sql-database-security-baseline)

### Security Frameworks
- [CIS Azure Foundations Benchmark](https://www.cisecurity.org/benchmark/azure)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [OWASP Projects](https://owasp.org/projects/)

## Questions?

For security-related questions or concerns:
1. Review Microsoft's security documentation
2. Consult with your security team
3. Consider hiring a security consultant for production deployments
4. Follow the principle of least privilege
5. When in doubt, be more restrictive

## PowerShell Script Security — Invoke-Expression Usage

### Finding: Command Injection via Invoke-Expression

**Severity**: Medium (mitigated by context)
**Location**: `Invoke-AzCommandWithRetry` function in `Resources/Azure-Deployment/` scripts (e.g. `enable-managed-identity.ps1`, `populate-keyvault-secrets.ps1`)

**Description**: The retry function uses `Invoke-Expression` to execute Azure CLI commands, which could allow command injection if variables contain malicious content.

### Remediation Status: ACCEPTED AS DESIGNED

**Justification**:
1. **Administrative tool** — scripts require an authenticated Azure CLI session with admin permissions
2. **No external input** — all variables come from validated script parameters or Azure CLI output
3. **PowerShell validation** — `ValidateSet`, `ValidateLength`, `ValidateNotNullOrEmpty` on all parameters
4. **Azure CLI validation** — resource names, object IDs, and parameters are validated by Azure
5. **RBAC enforcement** — Azure enforces authorization on all operations

### If Hardening Later

Replace `Invoke-Expression` with PowerShell script blocks or direct `az` invocations via `Start-Process`. This is a low-priority improvement given the current mitigations.

---

## Summary

✅ **Current implementation is suitable for development and testing**
⚠️ **Production deployment requires security hardening**
🔐 **Follow the phased hardening roadmap for production**
📊 **Regular security assessments are essential**

The provided infrastructure is a solid foundation that prioritizes ease of development while clearly documenting security considerations for production hardening.
