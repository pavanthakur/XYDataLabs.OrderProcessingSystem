#!/bin/bash

# Verify Key Vault Setup Script for Order Processing System
# This script validates the setup created by PR#54 (Key Vault) and PR#5 (GitHub Workflow)
#
# Usage: ./verify-keyvault-setup.sh <resource-group> [environment]
# Example: ./verify-keyvault-setup.sh rg-orderprocessing-dev dev

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -lt 1 ]; then
    echo -e "${RED}Error: Missing required argument${NC}"
    echo "Usage: $0 <resource-group> [environment]"
    echo "Example: $0 rg-orderprocessing-dev dev"
    exit 1
fi

RESOURCE_GROUP=$1
ENVIRONMENT=${2:-dev}
KV_NAME="kv-orderproc-$ENVIRONMENT"
APP_SERVICE_PATTERN="*-orderprocessing-api-xyapp-$ENVIRONMENT"

# Initialize counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║   Key Vault Verification - Order Processing System        ║"
echo "║   Environment: ${ENVIRONMENT}$(printf '%*s' $((43 - ${#ENVIRONMENT})))║"
echo "╚════════════════════════════════════════════════════════════╝"

# Check if logged in to Azure
echo ""
echo -e "${YELLOW}🔐 Checking Azure authentication...${NC}"
if ! az account show &>/dev/null; then
    echo -e "${RED}❌ Not logged in to Azure. Please run 'az login'${NC}"
    exit 1
fi

ACCOUNT_NAME=$(az account show --query "user.name" -o tsv)
SUBSCRIPTION_NAME=$(az account show --query "name" -o tsv)
echo -e "${GREEN}✅ Logged in as: $ACCOUNT_NAME${NC}"
echo -e "${GRAY}   Subscription: $SUBSCRIPTION_NAME${NC}"

# 1. Check if Key Vault exists
echo ""
echo -e "${YELLOW}📦 Step 1: Checking Key Vault existence...${NC}"
echo -e "${GRAY}   Looking for: $KV_NAME${NC}"

if az keyvault show --name "$KV_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    echo -e "${GREEN}✅ Key Vault '$KV_NAME' found${NC}"
    KV_LOCATION=$(az keyvault show --name "$KV_NAME" --query "location" -o tsv)
    KV_URI=$(az keyvault show --name "$KV_NAME" --query "properties.vaultUri" -o tsv)
    echo -e "${GRAY}   Location: $KV_LOCATION${NC}"
    echo -e "${GRAY}   Vault URI: $KV_URI${NC}"
    echo -e "${GRAY}   Resource Group: $RESOURCE_GROUP${NC}"
    ((CHECKS_PASSED++))
else
    echo -e "${RED}❌ Key Vault '$KV_NAME' not found in resource group '$RESOURCE_GROUP'${NC}"
    echo -e "${YELLOW}   Please verify:${NC}"
    echo -e "${YELLOW}   - Resource group name is correct${NC}"
    echo -e "${YELLOW}   - Key Vault was created by the deployment workflow${NC}"
    echo -e "${YELLOW}   - You have permissions to access the Key Vault${NC}"
    ((CHECKS_FAILED++))
    exit 1
fi

# 2. Check Key Vault configuration properties
echo ""
echo -e "${YELLOW}🔧 Step 2: Checking Key Vault configuration...${NC}"

SOFT_DELETE=$(az keyvault show --name "$KV_NAME" --query "properties.enableSoftDelete" -o tsv)
RETENTION=$(az keyvault show --name "$KV_NAME" --query "properties.softDeleteRetentionInDays" -o tsv)
SKU=$(az keyvault show --name "$KV_NAME" --query "properties.sku.name" -o tsv)

if [ "$SOFT_DELETE" == "true" ]; then
    echo -e "${GREEN}   Soft Delete Enabled: true${NC}"
    echo -e "${GREEN}   Soft Delete Retention: $RETENTION days${NC}"
    if [ "$RETENTION" == "90" ]; then
        echo -e "${GREEN}   ✅ Matches PR#54 specification (90 days)${NC}"
    fi
    ((CHECKS_PASSED++))
else
    echo -e "${RED}   Soft Delete Enabled: false${NC}"
    echo -e "${YELLOW}   ⚠️  Soft Delete should be enabled (PR#54 requirement)${NC}"
    ((CHECKS_WARNING++))
fi

echo -e "${GRAY}   SKU: $SKU${NC}"

# Check Tags
TAGS=$(az keyvault show --name "$KV_NAME" --query "tags" -o json 2>/dev/null)
if [ "$TAGS" != "null" ] && [ "$TAGS" != "" ]; then
    echo -e "${GRAY}   Tags:${NC}"
    echo "$TAGS" | jq -r 'to_entries[] | "      - \(.key): \(.value)"' 2>/dev/null || echo -e "${GRAY}      (Unable to parse tags)${NC}"
fi

# 3. Check required secrets
echo ""
echo -e "${YELLOW}🔑 Step 3: Checking required secrets...${NC}"

REQUIRED_SECRETS=("OpenPayAdapter--ApiKey" "ApplicationInsights--ConnectionString")
SECRETS_FOUND=0
SECRETS_MISSING=()

echo -e "${GRAY}   Checking for ${#REQUIRED_SECRETS[@]} required secret(s)...${NC}"

for SECRET in "${REQUIRED_SECRETS[@]}"; do
    if az keyvault secret show --vault-name "$KV_NAME" --name "$SECRET" &>/dev/null; then
        echo -e "${GREEN}   ✅ Secret '$SECRET' exists${NC}"
        CREATED=$(az keyvault secret show --vault-name "$KV_NAME" --name "$SECRET" --query "attributes.created" -o tsv)
        UPDATED=$(az keyvault secret show --vault-name "$KV_NAME" --name "$SECRET" --query "attributes.updated" -o tsv)
        ENABLED=$(az keyvault secret show --vault-name "$KV_NAME" --name "$SECRET" --query "attributes.enabled" -o tsv)
        echo -e "${GRAY}      Created: $CREATED${NC}"
        echo -e "${GRAY}      Updated: $UPDATED${NC}"
        echo -e "${GRAY}      Enabled: $ENABLED${NC}"
        ((SECRETS_FOUND++))
        ((CHECKS_PASSED++))
    else
        echo -e "${RED}   ❌ Secret '$SECRET' NOT FOUND${NC}"
        echo -e "${YELLOW}      Action required: Create this secret in Key Vault${NC}"
        SECRETS_MISSING+=("$SECRET")
        ((CHECKS_FAILED++))
    fi
done

if [ ${#SECRETS_MISSING[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}   ⚠️  Missing Secrets - Manual Action Required:${NC}"
    echo -e "${YELLOW}   Run the following commands to add missing secrets:${NC}"
    for SECRET in "${SECRETS_MISSING[@]}"; do
        echo -e "${CYAN}   az keyvault secret set --vault-name $KV_NAME --name \"$SECRET\" --value \"<your-value>\"${NC}"
    done
fi

# 4. Check App Services
echo ""
echo -e "${YELLOW}🌐 Step 4: Checking App Service configuration...${NC}"
echo -e "${GRAY}   Looking for App Services matching: $APP_SERVICE_PATTERN${NC}"

# Get list of web apps in the resource group
WEBAPPS=$(az webapp list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'orderprocessing-api-xyapp-$ENVIRONMENT')].name" -o tsv)

if [ -z "$WEBAPPS" ]; then
    echo -e "${YELLOW}   ⚠️  No App Service matching pattern found${NC}"
    echo -e "${GRAY}   This might be expected if the App Service hasn't been deployed yet${NC}"
    ((CHECKS_WARNING++))
else
    APP_COUNT=$(echo "$WEBAPPS" | wc -l)
    echo -e "${GREEN}   Found $APP_COUNT App Service(s)${NC}"
    
    while IFS= read -r WEBAPP_NAME; do
        echo ""
        echo -e "${CYAN}   📱 App Service: $WEBAPP_NAME${NC}"
        
        DEFAULT_HOST=$(az webapp show --name "$WEBAPP_NAME" --resource-group "$RESOURCE_GROUP" --query "defaultHostName" -o tsv)
        STATE=$(az webapp show --name "$WEBAPP_NAME" --resource-group "$RESOURCE_GROUP" --query "state" -o tsv)
        echo -e "${GRAY}      URL: https://$DEFAULT_HOST${NC}"
        echo -e "${GRAY}      State: $STATE${NC}"
        
        # Check Managed Identity
        IDENTITY_TYPE=$(az webapp identity show --name "$WEBAPP_NAME" --resource-group "$RESOURCE_GROUP" --query "type" -o tsv 2>/dev/null)
        
        if [ "$IDENTITY_TYPE" == "SystemAssigned" ]; then
            echo -e "${GREEN}      ✅ System-Assigned Managed Identity enabled${NC}"
            PRINCIPAL_ID=$(az webapp identity show --name "$WEBAPP_NAME" --resource-group "$RESOURCE_GROUP" --query "principalId" -o tsv)
            echo -e "${GRAY}         Principal ID: $PRINCIPAL_ID${NC}"
            ((CHECKS_PASSED++))
            
            # Check Key Vault access
            ACCESS=$(az keyvault show --name "$KV_NAME" --query "properties.accessPolicies[?objectId=='$PRINCIPAL_ID'].permissions.secrets" -o tsv 2>/dev/null)
            
            if [ -n "$ACCESS" ]; then
                echo -e "${GREEN}      ✅ Managed Identity has Key Vault access${NC}"
                echo -e "${GRAY}         Permissions: $ACCESS${NC}"
                
                # Check for Get and List permissions
                if echo "$ACCESS" | grep -q "get" && echo "$ACCESS" | grep -q "list"; then
                    echo -e "${GREEN}         ✅ Has required permissions (Get, List)${NC}"
                    ((CHECKS_PASSED++))
                else
                    echo -e "${YELLOW}         ⚠️  Missing required permissions${NC}"
                    ((CHECKS_WARNING++))
                fi
            else
                echo -e "${RED}      ❌ Managed Identity does NOT have Key Vault access${NC}"
                echo -e "${YELLOW}         Action required: Grant Key Vault access to this identity${NC}"
                echo -e "${YELLOW}         Command:${NC}"
                echo -e "${CYAN}         az keyvault set-policy --name $KV_NAME --object-id $PRINCIPAL_ID --secret-permissions get list${NC}"
                ((CHECKS_FAILED++))
            fi
        else
            echo -e "${RED}      ❌ System-Assigned Managed Identity NOT enabled${NC}"
            echo -e "${YELLOW}         Action required: Enable managed identity on the App Service${NC}"
            ((CHECKS_FAILED++))
        fi
        
        # Check App Settings for Key Vault references
        echo -e "${GRAY}      Checking App Settings for Key Vault references...${NC}"
        
        KV_REFS=$(az webapp config appsettings list --name "$WEBAPP_NAME" --resource-group "$RESOURCE_GROUP" --query "[?contains(value, '@Microsoft.KeyVault')]" -o json 2>/dev/null)
        KV_REF_COUNT=$(echo "$KV_REFS" | jq '. | length' 2>/dev/null || echo "0")
        
        if [ "$KV_REF_COUNT" -gt 0 ]; then
            echo -e "${GREEN}      ✅ Found $KV_REF_COUNT Key Vault reference(s):${NC}"
            echo "$KV_REFS" | jq -r '.[] | "         - \(.name)"' 2>/dev/null
            
            # Check for specific expected references
            HAS_API_KEY=$(echo "$KV_REFS" | jq -r '.[] | select(.name | contains("OpenPayAdapter") and contains("ApiKey")) | .name' 2>/dev/null)
            HAS_APP_INSIGHTS=$(echo "$KV_REFS" | jq -r '.[] | select(.name == "APPLICATIONINSIGHTS_CONNECTION_STRING") | .name' 2>/dev/null)
            
            if [ -n "$HAS_API_KEY" ]; then
                echo -e "${GREEN}         ✅ OpenPayAdapter ApiKey reference configured${NC}"
            else
                echo -e "${YELLOW}         ⚠️  OpenPayAdapter ApiKey reference not found${NC}"
                ((CHECKS_WARNING++))
            fi
            
            if [ -n "$HAS_APP_INSIGHTS" ]; then
                echo -e "${GREEN}         ✅ Application Insights connection string reference configured${NC}"
            else
                echo -e "${YELLOW}         ⚠️  Application Insights connection string reference not found${NC}"
                ((CHECKS_WARNING++))
            fi
            ((CHECKS_PASSED++))
        else
            echo -e "${YELLOW}      ⚠️  No Key Vault references found in App Settings${NC}"
            echo -e "${YELLOW}         Action required: Configure App Settings to reference Key Vault secrets${NC}"
            ((CHECKS_WARNING++))
        fi
        
    done <<< "$WEBAPPS"
fi

# 5. Check Access Policies Summary
echo ""
echo -e "${YELLOW}🔐 Step 5: Access Policies Summary...${NC}"

POLICY_COUNT=$(az keyvault show --name "$KV_NAME" --query "properties.accessPolicies | length(@)" -o tsv)
echo -e "${GRAY}   Total access policies configured: $POLICY_COUNT${NC}"

if [ "$POLICY_COUNT" -gt 0 ]; then
    echo -e "${GRAY}   Access policies:${NC}"
    az keyvault show --name "$KV_NAME" --query "properties.accessPolicies[].{ObjectId:objectId, Secrets:permissions.secrets}" -o json | \
        jq -r '.[] | "      - Object ID: \(.ObjectId)\n        Permissions: Secrets(\(.Secrets | join(", ")))"' 2>/dev/null || \
        echo -e "${GRAY}      (Unable to parse access policies)${NC}"
fi

# 6. Summary Report
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                  Verification Summary                     ║"
echo "╚════════════════════════════════════════════════════════════╝"

echo ""
echo -e "${CYAN}Check Results:${NC}"
echo -e "  • Checks Passed: ${GREEN}$CHECKS_PASSED${NC}"
echo -e "  • Checks Failed: ${RED}$CHECKS_FAILED${NC}"
echo -e "  • Warnings: ${YELLOW}$CHECKS_WARNING${NC}"

echo ""
echo -e "${CYAN}Secrets Status:${NC}"
echo -e "  • Found: ${GREEN}$SECRETS_FOUND${NC}/${#REQUIRED_SECRETS[@]}"
if [ ${#SECRETS_MISSING[@]} -gt 0 ]; then
    echo -e "  • Missing: ${RED}${SECRETS_MISSING[*]}${NC}"
fi

# Overall Status
echo ""
if [ $CHECKS_FAILED -eq 0 ] && [ ${#SECRETS_MISSING[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ Overall Status: SUCCESS${NC}"
    echo -e "${GREEN}   All critical checks passed!${NC}"
    EXIT_CODE=0
elif [ ${#SECRETS_MISSING[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Overall Status: INCOMPLETE${NC}"
    echo -e "${YELLOW}   Key Vault is configured but missing required secrets${NC}"
    echo -e "${YELLOW}   Please populate the missing secrets to complete setup${NC}"
    EXIT_CODE=1
else
    echo -e "${RED}❌ Overall Status: FAILED${NC}"
    echo -e "${RED}   Some critical checks failed. Review the output above${NC}"
    echo -e "${RED}   and take corrective actions as suggested${NC}"
    EXIT_CODE=1
fi

# PR References
echo ""
echo -e "${CYAN}📚 Related Changes:${NC}"
echo -e "${GRAY}  • PR#54: Key Vault creation and configuration${NC}"
echo -e "${GRAY}  • PR#5:  GitHub workflow automation (GITHUB_TOKEN)${NC}"

echo ""
echo -e "${CYAN}📖 For detailed verification steps and troubleshooting:${NC}"
echo -e "${GRAY}   See: Documentation/KEY-VAULT-VERIFICATION-GUIDE.md${NC}"

echo ""

exit $EXIT_CODE
