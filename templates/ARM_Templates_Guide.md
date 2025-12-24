# ARM Templates Guide

## 📚 Complete Template Documentation

This guide explains every ARM template, parameter, variable, and how values flow between templates.

---

## 🗂️ Template Overview

| Template | Purpose | Dependencies | Resources Created |
|----------|---------|--------------|-------------------|
| **main.json** | Orchestrator | None (entry point) | Deploys all other templates |
| **monitoring.json** | Logging & APM | None | Log Analytics, App Insights |
| **network.json** | Network infrastructure | None | VNet, Subnets, NSGs |
| **keyvault.json** | Secure storage | monitoring.json | Key Vault, Access Policies |
| **apim.json** | API Gateway | network.json, keyvault.json, monitoring.json | API Management Service |
| **appgateway.json** | Public WAF | network.json, apim.json, monitoring.json | App Gateway, Public IP, WAF |

---

## 📄 main.json - Orchestration Template

### Purpose
- Entry point for deployment
- Links all other templates
- Passes parameters between templates
- Returns final deployment outputs

### Parameters You MUST Update

#### 1. **projectName** (Required)
```json
"projectName": {
  "value": "myproject"  // UPDATE THIS - your project name
}
```
**Used for:** Resource naming prefix  
**Example:** `myproject-dev-apim`, `myproject-prod-vnet`  
**Rules:** Lowercase, alphanumeric, max 10 characters

#### 2. **environment** (Required)
```json
"environment": {
  "value": "dev"  // UPDATE THIS - choose: dev, staging, or prod
}
```
**Used for:** Resource naming and configuration selection  
**Allowed values:** `dev`, `staging`, `prod`

#### 3. **adminObjectId** (Required - GET YOUR VALUE)
```json
"adminObjectId": {
  "value": "12345678-1234-1234-1234-123456789012"  // UPDATE THIS
}
```
**How to get it:**
```bash
az ad signed-in-user show --query id -o tsv
```
**Used for:** Key Vault admin access permissions  
**Important:** Without this, you can't access Key Vault

#### 4. **auth0Domain** (Required - YOUR AUTH0 TENANT)
```json
"auth0Domain": {
  "value": "your-tenant.auth0.com"  // UPDATE THIS
}
```
**Used for:** JWT token validation in APIM policies  
**Example:** `contoso.auth0.com` or `contoso.us.auth0.com`  
**Find it:** Auth0 Dashboard → Applications → Your App → Domain

#### 5. **auth0Audience** (Required - YOUR AUTH0 API)
```json
"auth0Audience": {
  "value": "https://api.yourdomain.com"  // UPDATE THIS
}
```
**Used for:** JWT audience validation  
**Example:** `https://api.contoso.com`  
**Find it:** Auth0 Dashboard → APIs → Your API → Identifier

#### 6. **mulesoftBackendUrl** (Required - YOUR MULESOFT ENDPOINT)
```json
"mulesoftBackendUrl": {
  "value": "https://api.mulesoft.contoso.com"  // UPDATE THIS
}
```
**Used for:** APIM named value for MuleSoft backend  
**Example:** `https://api-dev.mulesoft.contoso.com`

### Parameters with Smart Defaults (Usually Don't Need to Change)

#### Network Configuration
```json
"vnetAddressPrefix": "10.0.0.0/16",      // Dev default
"apimSubnetPrefix": "10.0.1.0/24",       // APIM subnet
"appGatewaySubnetPrefix": "10.0.2.0/24"  // App Gateway subnet
```
**Pre-configured per environment in parameter files:**
- Dev: `10.0.0.0/16`
- Staging: `10.5.0.0/16`
- Prod: `10.10.0.0/16`

#### Capacity Settings
```json
"apimSku": "Developer",           // Developer (dev/staging) or Premium (prod)
"apimCapacity": 1,                // 1 unit (dev/staging), 2+ (prod)
"appGatewayCapacity": 2,          // Min instances: 2 (dev/staging), 3 (prod)
"appGatewayMaxCapacity": 5        // Max instances: 5 (dev), 7 (staging), 10 (prod)
```

#### Monitoring & Security
```json
"logRetentionDays": 30,            // 30 (dev), 60 (staging), 90 (prod)
"enableWafPreventionMode": false   // false (dev), true (staging/prod)
```

### How Values Flow Through Templates

```
main.json receives parameters
    ↓
Variables computed (resource names)
    ↓
monitoring.json deployed → returns workspaceId
    ↓
network.json deployed → returns subnetIds
    ↓
keyvault.json deployed (uses workspaceId)
    ↓
apim.json deployed (uses subnetId, workspaceId) → returns privateIp
    ↓
appgateway.json deployed (uses subnetId, privateIp, workspaceId)
    ↓
main.json returns all outputs
```

### Variable Naming Convention

All variables are computed automatically - **DO NOT MODIFY**:

```json
"variables": {
  "namingPrefix": "{projectName}-{environment}",
  
  // Resource names auto-generated:
  "vnetName": "{projectName}-{environment}-vnet",
  "apimName": "{projectName}-{environment}-apim",
  "appGatewayName": "{projectName}-{environment}-appgw",
  "keyVaultName": "{projectName}{environment}kv",  // No dashes, max 24 chars
  "logAnalyticsName": "{projectName}-{environment}-la",
  "appInsightsName": "{projectName}-{environment}-ai"
}
```

**Example with projectName="myproject", environment="dev":**
- VNet: `myproject-dev-vnet`
- APIM: `myproject-dev-apim`
- App Gateway: `myproject-dev-appgw`
- Key Vault: `myprojectdevkv` (no dashes due to naming rules)

### Outputs Returned

After deployment completes, you'll receive:

```json
{
  "apimName": "myproject-dev-apim",
  "apimGatewayUrl": "https://myproject-dev-apim.azure-api.net",
  
  // USE THESE TO ACCESS YOUR APIS:
  "appGatewayPublicIp": "52.168.117.42",
  "appGatewayFqdn": "myproject-dev-appgw.eastus.cloudapp.azure.com",
  
  "keyVaultName": "myprojectdevkv",
  "logAnalyticsWorkspaceId": "/subscriptions/.../workspaces/..."
}
```

---

## 📊 monitoring.json - Log Analytics & Application Insights

### Purpose
Creates centralized logging and monitoring infrastructure.

### Parameters Received from main.json

```json
{
  "location": "eastus",                    // FROM: main.json parameter
  "logAnalyticsName": "myproject-dev-la",  // FROM: main.json variable
  "appInsightsName": "myproject-dev-ai",   // FROM: main.json variable
  "retentionInDays": 30                    // FROM: main.json parameter
}
```

### Resources Created

1. **Log Analytics Workspace**
   - Name: `{projectName}-{environment}-la`
   - SKU: `PerGB2018` (pay-as-you-go)
   - Retention: 30/60/90 days (based on environment)
   - Stores: APIM logs, App Gateway logs, WAF logs, Key Vault audit logs

2. **Application Insights**
   - Name: `{projectName}-{environment}-ai`
   - Type: `web`
   - Connected to Log Analytics workspace
   - Stores: Performance metrics, request telemetry, dependencies

### Outputs Returned to main.json

```json
{
  "logAnalyticsWorkspaceId": "/subscriptions/.../resourceGroups/.../providers/Microsoft.OperationalInsights/workspaces/myproject-dev-la",
  "appInsightsInstrumentationKey": "abc123-...-xyz789"
}
```

### Where These Values Go

- **logAnalyticsWorkspaceId** → Used by:
  - keyvault.json (diagnostic settings)
  - apim.json (diagnostic settings)
  - appgateway.json (diagnostic settings)

- **appInsightsInstrumentationKey** → Used by:
  - apim.json (logger configuration)

---

## 🌐 network.json - Virtual Network Infrastructure

### Purpose
Creates isolated network with segmented subnets and security rules.

### Parameters Received from main.json

```json
{
  "location": "eastus",                       // FROM: main.json parameter
  "vnetName": "myproject-dev-vnet",           // FROM: main.json variable
  "vnetAddressPrefix": "10.0.0.0/16",         // FROM: main.json parameter
  "apimSubnetPrefix": "10.0.1.0/24",          // FROM: main.json parameter
  "appGatewaySubnetPrefix": "10.0.2.0/24"     // FROM: main.json parameter
}
```

### Resources Created

1. **Network Security Group - APIM**
   - Name: `{vnetName}-apim-nsg`
   - Inbound Rules:
     - Port 3443: APIM Management (from ApiManagement service tag)
     - Port 6390: Azure Load Balancer health probes
     - Port 443: HTTPS from App Gateway subnet

2. **Network Security Group - App Gateway**
   - Name: `{vnetName}-appgw-nsg`
   - Inbound Rules:
     - Port 443: HTTPS from Internet
     - Port 80: HTTP from Internet (redirects to 443)
     - Port 65200-65535: Gateway Manager

3. **Virtual Network**
   - Name: `{vnetName}`
   - Address Space: `10.x.0.0/16` (x varies by environment)
   - DDoS Protection: Basic (included)

4. **Subnet: apim-subnet**
   - Address Range: `10.x.1.0/24`
   - NSG: APIM NSG attached
   - Service Endpoints: Microsoft.Storage, Microsoft.Sql, Microsoft.KeyVault
   - Delegation: Microsoft.Web/serverFarms (required for APIM)

5. **Subnet: appgateway-subnet**
   - Address Range: `10.x.2.0/24`
   - NSG: App Gateway NSG attached
   - Delegation: None (App Gateway doesn't need delegation)

### Outputs Returned to main.json

```json
{
  "vnetId": "/subscriptions/.../virtualNetworks/myproject-dev-vnet",
  "apimSubnetId": "/subscriptions/.../virtualNetworks/myproject-dev-vnet/subnets/apim-subnet",
  "appGatewaySubnetId": "/subscriptions/.../virtualNetworks/myproject-dev-vnet/subnets/appgateway-subnet"
}
```

### Where These Values Go

- **apimSubnetId** → apim.json (VNet integration)
- **appGatewaySubnetId** → appgateway.json (placement)

---

## 🔐 keyvault.json - Secure Storage

### Purpose
Provides secure storage for certificates, secrets, and keys.

### Parameters Received from main.json

```json
{
  "location": "eastus",                             // FROM: main.json parameter
  "keyVaultName": "myprojectdevkv",                 // FROM: main.json variable (no dashes)
  "adminObjectId": "12345678-1234-1234-...",        // FROM: main.json parameter
  "logAnalyticsWorkspaceId": "/subscriptions/..."   // FROM: monitoring.json output
}
```

### Resources Created

1. **Key Vault**
   - Name: `{projectName}{environment}kv` (no dashes, max 24 chars)
   - SKU: Standard
   - Features:
     - Soft Delete: Enabled (90-day retention)
     - Purge Protection: Enabled (can't force delete)
     - RBAC: Disabled (using Access Policies)
   
2. **Access Policy - Admin**
   - Object ID: Your Azure AD user/service principal
   - Permissions:
     - Keys: get, list, create, delete
     - Secrets: get, list, set, delete
     - Certificates: get, list, create, delete, import

3. **Diagnostic Settings**
   - Logs: AuditEvent
   - Destination: Log Analytics Workspace

### Post-Deployment: What to Store

```bash
# 1. SSL Certificate for App Gateway
az keyvault certificate import \
  --vault-name myprojectdevkv \
  --name api-ssl-cert \
  --file yourdomain.pfx \
  --password "your-cert-password"

# 2. MuleSoft Backend Credentials
az keyvault secret set \
  --vault-name myprojectdevkv \
  --name mulesoft-username \
  --value "admin"

az keyvault secret set \
  --vault-name myprojectdevkv \
  --name mulesoft-password \
  --value "secure-password"
```

### Post-Deployment: Grant APIM Access

```bash
# Get APIM Managed Identity Principal ID
APIM_PRINCIPAL_ID=$(az apim show \
  --resource-group rg-apim-public-dev \
  --name myproject-dev-apim \
  --query identity.principalId -o tsv)

# Grant secrets access
az keyvault set-policy \
  --name myprojectdevkv \
  --object-id $APIM_PRINCIPAL_ID \
  --secret-permissions get list
```

### Outputs Returned to main.json

```json
{
  "keyVaultName": "myprojectdevkv",
  "keyVaultUri": "https://myprojectdevkv.vault.azure.net/"
}
```

---

## 🎯 apim.json - API Management Service

### Purpose
Creates API Management instance with Auth0 integration and MuleSoft configuration.

### Parameters Received from main.json

```json
{
  "location": "eastus",
  "apimName": "myproject-dev-apim",
  "apimSku": "Developer",                        // Developer or Premium
  "apimCapacity": 1,                             // Number of units
  "vnetName": "myproject-dev-vnet",
  "apimSubnetName": "apim-subnet",
  "auth0Domain": "contoso.auth0.com",            // YOUR AUTH0 TENANT
  "auth0Audience": "https://api.contoso.com",    // YOUR AUTH0 API
  "mulesoftBackendUrl": "https://api.mulesoft.contoso.com",
  "appInsightsInstrumentationKey": "abc123...",  // FROM: monitoring.json
  "logAnalyticsWorkspaceId": "/subscriptions/..."  // FROM: monitoring.json
}
```

### Resources Created

1. **API Management Service**
   - Name: `{projectName}-{environment}-apim`
   - SKU: Developer (dev/staging) or Premium (prod)
   - Capacity: 1-10 units
   - Virtual Network: Internal mode (not directly accessible from internet)
   - Managed Identity: SystemAssigned (for Key Vault access)
   
2. **Custom Properties (Named Values)**
   - `auth0-domain`: `contoso.auth0.com`
   - `auth0-audience`: `https://api.contoso.com`
   - `mulesoft-backend-url`: `https://api.mulesoft.contoso.com`

3. **TLS Settings**
   - TLS 1.2: Enabled ✅
   - TLS 1.1: Disabled ❌
   - TLS 1.0: Disabled ❌
   - SSL 3.0: Disabled ❌

4. **Application Insights Logger**
   - Name: `apim-logger`
   - Instrumentation Key: From monitoring.json
   - Sampling: 100%
   - Log request/response body: First 512 bytes

5. **Diagnostic Settings**
   - Gateway Logs → Log Analytics
   - Metrics → Log Analytics

### How Named Values Are Used in Policies

In `policies/api-auth0-policy.xml`:
```xml
<validate-jwt>
  <openid-config url="https://{{auth0-domain}}/.well-known/openid-configuration" />
  <audiences>
    <audience>{{auth0-audience}}</audience>
  </audiences>
</validate-jwt>
```

**The `{{name}}` syntax references Named Values from APIM.**

### Outputs Returned to main.json

```json
{
  "apimName": "myproject-dev-apim",
  "apimGatewayUrl": "https://myproject-dev-apim.azure-api.net",
  "apimPrivateIp": "10.0.1.5",  // Dynamic IP assigned by Azure in APIM subnet
  "apimPrincipalId": "abc-def-ghi..."  // Managed Identity ID for Key Vault access
}
```

### Where These Values Go

- **apimPrivateIp** → appgateway.json (backend pool configuration)
- **apimPrincipalId** → Manual step: Grant Key Vault access

---

## 🚪 appgateway.json - Public Application Gateway with WAF

### Purpose
Creates public-facing entry point with Web Application Firewall protection.

### Parameters Received from main.json

```json
{
  "location": "eastus",
  "appGatewayName": "myproject-dev-appgw",
  "vnetName": "myproject-dev-vnet",
  "appGatewaySubnetName": "appgateway-subnet",
  "minCapacity": 2,                              // Min instances
  "maxCapacity": 5,                              // Max instances (autoscale)
  "apimPrivateIp": "10.0.1.5",                   // FROM: apim.json output
  "enableWafPreventionMode": false,              // Detection (dev) or Prevention (staging/prod)
  "logAnalyticsWorkspaceId": "/subscriptions/..."  // FROM: monitoring.json
}
```

### Resources Created

1. **Public IP Address**
   - Name: `{appGatewayName}-pip`
   - SKU: Standard (required for App Gateway v2)
   - Allocation: Static
   - DNS Label: `{projectName}-{environment}-appgw`
   - Result FQDN: `myproject-dev-appgw.eastus.cloudapp.azure.com`

2. **Application Gateway**
   - Name: `{projectName}-{environment}-appgw`
   - Tier: WAF_v2
   - Autoscaling:
     - Min capacity: 2 (dev/staging), 3 (prod)
     - Max capacity: 5 (dev), 7 (staging), 10 (prod)

3. **WAF Policy**
   - Mode: Detection (dev) or Prevention (staging/prod)
   - Rule Set: OWASP 3.2
   - Additional Rules: Microsoft Bot Manager 1.0
   - Custom Rules:
     - Rate Limiting: 100 requests/min per IP
     - Geo-blocking: Configurable (disabled by default)

4. **Backend Pool**
   - Name: `apim-backend-pool`
   - Target: APIM private IP (10.x.1.5)
   - Port: 443 (HTTPS)

5. **Backend HTTP Settings**
   - Protocol: HTTPS
   - Port: 443
   - Cookie Affinity: Disabled
   - Request Timeout: 30 seconds
   - Override Hostname: Yes (uses APIM hostname)
   - Probe: Custom health probe to APIM

6. **Listeners**
   - **HTTPS Listener**: Port 443 (requires SSL certificate)
   - **HTTP Listener**: Port 80 (redirects to HTTPS)

7. **Routing Rules**
   - HTTP → HTTPS Redirect
   - HTTPS → APIM Backend Pool

8. **Diagnostic Settings**
   - Access Logs → Log Analytics
   - Firewall Logs → Log Analytics
   - Metrics → Log Analytics

### SSL Certificate Configuration (POST-DEPLOYMENT)

The template doesn't include SSL certificate - you must add it manually:

```bash
# Option 1: Upload to Key Vault (recommended)
az keyvault certificate import \
  --vault-name myprojectdevkv \
  --name appgateway-ssl \
  --file yourdomain.pfx

# Option 2: Reference in App Gateway
az network application-gateway ssl-cert create \
  --resource-group rg-apim-public-dev \
  --gateway-name myproject-dev-appgw \
  --name ssl-cert \
  --key-vault-secret-id "https://myprojectdevkv.vault.azure.net/secrets/appgateway-ssl"
```

### Outputs Returned to main.json

```json
{
  "appGatewayId": "/subscriptions/.../applicationGateways/myproject-dev-appgw",
  "appGatewayName": "myproject-dev-appgw",
  "publicIpAddress": "52.168.117.42",
  "publicIpFqdn": "myproject-dev-appgw.eastus.cloudapp.azure.com"
}
```

### How to Access Your APIs

**Option 1: Use Auto-Generated FQDN (Immediate)**
```bash
curl https://myproject-dev-appgw.eastus.cloudapp.azure.com/api/v1/endpoint
```

**Option 2: Configure Custom Domain**
1. Create DNS A record: `api.yourdomain.com` → `52.168.117.42`
2. Upload SSL certificate to Key Vault
3. Configure App Gateway listener with custom domain

---

## 🔄 Complete Value Flow Diagram

```
USER UPDATES PARAMETERS FILE:
├─ projectName: "myproject"
├─ environment: "dev"
├─ adminObjectId: "your-aad-object-id"
├─ auth0Domain: "contoso.auth0.com"
├─ auth0Audience: "https://api.contoso.com"
└─ mulesoftBackendUrl: "https://api.mulesoft.contoso.com"

         ↓

MAIN.JSON CREATES VARIABLES:
├─ vnetName: "myproject-dev-vnet"
├─ apimName: "myproject-dev-apim"
├─ appGatewayName: "myproject-dev-appgw"
└─ keyVaultName: "myprojectdevkv"

         ↓

MONITORING.JSON DEPLOYS:
├─ Creates: Log Analytics Workspace
├─ Creates: Application Insights
└─ Returns: workspaceId, instrumentationKey

         ↓

NETWORK.JSON DEPLOYS:
├─ Creates: VNet (10.x.0.0/16)
├─ Creates: APIM Subnet (10.x.1.0/24)
├─ Creates: App Gateway Subnet (10.x.2.0/24)
├─ Creates: 2 NSGs
└─ Returns: subnetIds

         ↓

KEYVAULT.JSON DEPLOYS:
├─ Creates: Key Vault
├─ Uses: workspaceId (from monitoring)
├─ Uses: adminObjectId (from parameters)
└─ Returns: keyVaultName

         ↓

APIM.JSON DEPLOYS:
├─ Creates: API Management Service
├─ Uses: apimSubnetId (from network)
├─ Uses: workspaceId (from monitoring)
├─ Uses: instrumentationKey (from monitoring)
├─ Uses: auth0Domain, auth0Audience (from parameters)
├─ Creates: Named Values for Auth0 and MuleSoft
└─ Returns: apimPrivateIp, apimPrincipalId

         ↓

APPGATEWAY.JSON DEPLOYS:
├─ Creates: Public IP + FQDN
├─ Creates: Application Gateway + WAF
├─ Uses: appGatewaySubnetId (from network)
├─ Uses: apimPrivateIp (from apim) ← BACKEND POOL TARGET
├─ Uses: workspaceId (from monitoring)
└─ Returns: publicIpAddress, publicIpFqdn

         ↓

MAIN.JSON RETURNS OUTPUTS:
├─ apimName: "myproject-dev-apim"
├─ appGatewayPublicIp: "52.168.117.42" ← USE THIS
├─ appGatewayFqdn: "myproject-dev-appgw.eastus.cloudapp.azure.com" ← OR THIS
└─ keyVaultName: "myprojectdevkv" ← UPLOAD CERTS HERE
```

---

## ✅ Quick Reference: What to Update

### Before Deployment

1. **In parameters/{environment}.parameters.json:**
   ```json
   {
     "adminObjectId": { "value": "GET-YOUR-AAD-OBJECT-ID" },
     "auth0Domain": { "value": "your-tenant.auth0.com" },
     "auth0Audience": { "value": "https://api.yourdomain.com" },
     "mulesoftBackendUrl": { "value": "https://api.mulesoft.yourdomain.com" }
   }
   ```

2. **Get your Azure AD Object ID:**
   ```bash
   az ad signed-in-user show --query id -o tsv
   ```

### After Deployment

1. **Upload SSL Certificate:**
   ```bash
   az keyvault certificate import \
     --vault-name {keyVaultName} \
     --name api-ssl-cert \
     --file certificate.pfx
   ```

2. **Grant APIM Access to Key Vault:**
   ```bash
   az keyvault set-policy \
     --name {keyVaultName} \
     --object-id {apimPrincipalId} \
     --secret-permissions get list
   ```

3. **Access Your APIs:**
   - Use FQDN: `https://{appGatewayFqdn}/api/v1/...`
   - Or configure DNS: `api.yourdomain.com` → `{publicIpAddress}`

---

## 🎯 Summary

**DO modify:**
- Parameter files (dev/staging/prod.parameters.json)
- Only the 6 required parameters

**DON'T modify:**
- Template files (*.json)
- Variables section
- Resource definitions

**Templates work together like building blocks:**
1. Monitoring creates logging infrastructure
2. Network creates isolated subnets
3. Key Vault creates secure storage
4. APIM creates internal API gateway
5. App Gateway creates public entry point with WAF

**Values flow automatically** - parameters → variables → resources → outputs → next template's inputs.