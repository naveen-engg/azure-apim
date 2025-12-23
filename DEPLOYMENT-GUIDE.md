# Azure APIM Private Endpoint Deployment Guide

## 📋 Overview

This deployment package provides production-ready ARM templates for Azure API Management with Private Endpoint architecture, featuring comprehensive security, Auth0 integration, and MuleSoft connectivity.

**Estimated Deployment Time:** 45-60 minutes

## 📁 Package Contents

### Templates (templates/)
- `main.json` - Main orchestration template
- `network.json` - VNet, Subnets, NSGs  
- `apim.json` - API Management (Internal VNet mode)
- `appgateway.json` - Application Gateway + WAF v2 (Private Frontend)
- `private-endpoint.json` - Private Endpoint configuration
- `private-dns.json` - Private DNS Zone
- `keyvault.json` - Azure Key Vault with Managed Identity
- `monitoring.json` - Log Analytics + Application Insights

### Parameters (parameters/)
- `dev.parameters.json` - Development environment settings
- `prod.parameters.json` - Production environment settings

### Policies (policies/)
- `api-auth0-policy.xml` - Auth0 JWT validation policy
- `mulesoft-integration-policy.xml` - MuleSoft integration policy

### Scripts (scripts/)
- `deploy.sh` - Bash deployment script
- `deploy.ps1` - PowerShell deployment script

## 🔧 Prerequisites

### Required Tools

**Option 1: Azure CLI**
```bash
# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
az --version
```

**Option 2: Azure PowerShell**
```powershell
Install-Module -Name Az -AllowClobber -Scope CurrentUser
Get-InstalledModule -Name Az
```

### Azure Permissions
- Owner or Contributor role on subscription
- Ability to create resources
- Ability to assign roles (for Managed Identity)

### Get Azure AD Object ID
```bash
# Azure CLI
az ad signed-in-user show --query id -o tsv

# PowerShell
(Get-AzADUser -UserPrincipalName (Get-AzContext).Account).Id
```

## 🚀 Quick Start

### 1. Update Parameters

Edit `parameters/dev.parameters.json`:
```json
{
  "adminObjectId": { "value": "YOUR-AZURE-AD-OBJECT-ID" },
  "auth0Domain": { "value": "YOUR-TENANT.auth0.com" },
  "auth0Audience": { "value": "https://api.YOUR-DOMAIN.com" }
}
```

### 2. Deploy

**Using Bash:**
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh dev
```

**Using PowerShell:**
```powershell
.\scripts\deploy.ps1 -Environment dev
```

## 📊 Architecture Components

The deployment creates:
- Virtual Network (10.0.0.0/16 for dev, 10.10.0.0/16 for prod)
- 3 Subnets (APIM, App Gateway, Private Endpoint)
- Network Security Groups with production-ready rules
- API Management in Internal VNet mode
- Application Gateway with WAF v2 (OWASP 3.2)
- Private Endpoint for secure App Gateway access
- Private DNS Zone for name resolution
- Key Vault with soft delete and purge protection
- Managed Identity for APIM
- Log Analytics Workspace (30 days dev, 90 days prod)
- Application Insights for APM

## ⚙️ Configuration

### Key Parameters

| Parameter | Dev | Prod | Description |
|-----------|-----|------|-------------|
| apimSku | Developer | Premium | APIM pricing tier |
| apimCapacity | 1 | 2 | APIM instance count |
| appGatewayCapacity | 2 | 3-10 | App Gateway instances |
| enableWafPreventionMode | false | true | WAF mode |
| logRetentionDays | 30 | 90 | Log retention |

### Network Layout

**Development (10.0.0.0/16):**
- APIM Subnet: 10.0.1.0/24
- App Gateway Subnet: 10.0.2.0/24
- Private Endpoint Subnet: 10.0.3.0/24

**Production (10.10.0.0/16):**
- APIM Subnet: 10.10.1.0/24
- App Gateway Subnet: 10.10.2.0/24
- Private Endpoint Subnet: 10.10.3.0/24

## 📝 Post-Deployment Tasks

### 1. Configure DNS

Get Private Endpoint IP:
```bash
az network private-endpoint show \
  --resource-group rg-apim-private-dev \
  --name myproject-dev-pe-appgw \
  --query customDnsConfigs[0].ipAddresses[0] -o tsv
```

Create A record pointing `api.yourdomain.com` to the Private Endpoint IP.

### 2. Upload SSL Certificates

```bash
az keyvault certificate import \
  --vault-name myprojectdevkv \
  --name api-ssl-cert \
  --file certificate.pfx \
  --password "cert-password"
```

### 3. Grant APIM Key Vault Access

```bash
APIM_PRINCIPAL_ID=$(az apim show \
  --resource-group rg-apim-private-dev \
  --name myproject-dev-apim \
  --query identity.principalId -o tsv)

az keyvault set-policy \
  --name myprojectdevkv \
  --object-id $APIM_PRINCIPAL_ID \
  --secret-permissions get list
```

### 4. Import APIs

```bash
az apim api import \
  --resource-group rg-apim-private-dev \
  --service-name myproject-dev-apim \
  --path /api/v1 \
  --specification-path openapi.json \
  --specification-format OpenApiJson \
  --api-id my-api
```

### 5. Apply APIM Policies

```bash
# Apply Auth0 JWT validation
az apim api policy create \
  --resource-group rg-apim-private-dev \
  --service-name myproject-dev-apim \
  --api-id my-api \
  --xml-content @policies/api-auth0-policy.xml

# Apply MuleSoft integration policy
az apim api operation policy create \
  --resource-group rg-apim-private-dev \
  --service-name myproject-dev-apim \
  --api-id my-api \
  --operation-id mulesoft-op \
  --xml-content @policies/mulesoft-integration-policy.xml
```

### 6. Configure Auth0

1. Create Auth0 Application (Machine-to-Machine or Web App)
2. Create Auth0 API with audience matching your parameter
3. Update APIM named values if needed

### 7. Test Deployment

```bash
# Get Auth0 token
TOKEN=$(curl --request POST \
  --url https://your-tenant.auth0.com/oauth/token \
  --header 'content-type: application/json' \
  --data '{
    "client_id":"YOUR_CLIENT_ID",
    "client_secret":"YOUR_CLIENT_SECRET",
    "audience":"https://api.yourdomain.com",
    "grant_type":"client_credentials"
  }' | jq -r '.access_token')

# Test API call
curl -X GET \
  -H "Authorization: Bearer $TOKEN" \
  https://api.yourdomain.com/api/v1/test
```

## 🔍 Troubleshooting

### APIM Provisioning Takes Long
**Normal:** APIM can take 45-60 minutes to provision. Check status:
```bash
az apim show --resource-group rg-apim-private-dev --name myproject-dev-apim --query provisioningState
```

### Private Endpoint Not Resolving
Verify DNS zone is linked to VNet:
```bash
az network private-dns link vnet show \
  --resource-group rg-apim-private-dev \
  --zone-name privatelink.azurewebsites.net \
  --name privatelink.azurewebsites.net-link
```

### JWT Validation Fails (401)
1. Verify Auth0 domain and audience in APIM named values
2. Check JWT is valid: jwt.io
3. Verify Auth0 OpenID config is accessible

### WAF Blocking Requests (403)
Check WAF logs:
```kusto
AzureDiagnostics
| where Category == "ApplicationGatewayFirewallLog"
| where action_s == "Blocked"
| project TimeGenerated, clientIp_s, requestUri_s, ruleId_s
```

### Key Vault Access Denied
Verify APIM Managed Identity has permissions:
```bash
az keyvault show --name myprojectdevkv --query properties.accessPolicies
```

## 💰 Cost Estimation

### Development (~$347/month)
- API Management Developer: ~$50
- Application Gateway WAF_v2: ~$270
- Other services: ~$27

### Production (~$6,723-8,023/month)
- API Management Premium (2 units): ~$5,950
- Application Gateway WAF_v2 (3-10 instances): ~$700-2,000
- Other services: ~$73

**Cost Optimization:**
- Use Azure Reservations (save up to 70%)
- Right-size APIM SKU (Developer for dev/test)
- Configure App Gateway autoscaling
- Set Log Analytics daily cap

## 📚 Monitoring Queries

### API Request Rate
```kusto
ApiManagementGatewayLogs
| where TimeGenerated > ago(1h)
| summarize RequestCount = count() by bin(TimeGenerated, 5m)
| render timechart
```

### Response Time Percentiles
```kusto
ApiManagementGatewayLogs
| where TimeGenerated > ago(1h)
| summarize 
    P50 = percentile(DurationMs, 50),
    P95 = percentile(DurationMs, 95),
    P99 = percentile(DurationMs, 99)
  by bin(TimeGenerated, 5m)
| render timechart
```

### Error Rate
```kusto
ApiManagementGatewayLogs
| where TimeGenerated > ago(1h)
| summarize 
    Total = count(),
    Errors = countif(ResponseCode >= 400)
  by bin(TimeGenerated, 5m)
| extend ErrorRate = (Errors * 100.0) / Total
| render timechart
```

### WAF Blocks
```kusto
AzureDiagnostics
| where Category == "ApplicationGatewayFirewallLog"
| where action_s == "Blocked"
| summarize BlockCount = count() by ruleId_s, Message
| order by BlockCount desc
```

## 🔒 Security Features

- ✅ Private Endpoint connectivity (no public IPs)
- ✅ WAF v2 with OWASP 3.2 rules
- ✅ TLS 1.2+ enforcement
- ✅ Managed Identity for Key Vault access
- ✅ Network Security Groups with least privilege
- ✅ JWT token validation with Auth0
- ✅ Rate limiting and quotas
- ✅ Comprehensive audit logging
- ✅ Security headers on all responses
- ✅ CORS configuration

## 📖 Resources

- [Azure APIM Docs](https://docs.microsoft.com/azure/api-management/)
- [Application Gateway Docs](https://docs.microsoft.com/azure/application-gateway/)
- [Private Link Docs](https://docs.microsoft.com/azure/private-link/)
- [Auth0 Documentation](https://auth0.com/docs)
- [ARM Templates Reference](https://docs.microsoft.com/azure/templates/)

## 🎯 Next Steps

1. ✅ Configure custom domain and SSL
2. ✅ Import your APIs
3. ✅ Apply and test policies
4. ✅ Configure Auth0
5. ✅ Set up monitoring alerts
6. ✅ Conduct load testing
7. ✅ Document your APIs
8. ✅ Set up CI/CD
9. ✅ Train your team

---

**Questions?** Review the troubleshooting section or consult Azure documentation.

**Happy Deploying! 🚀**
