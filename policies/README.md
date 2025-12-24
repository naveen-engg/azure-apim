# APIM Policy Templates

## 📋 Available Policies

### 1. api-auth0-policy.xml
**Purpose:** JWT token validation with Auth0  
**Apply to:** All APIs that require authentication  
**What it does:**
- Validates JWT signature using Auth0 JWKS endpoint
- Checks token expiration
- Validates audience and issuer
- Enforces rate limiting (100 req/min per user)
- Enforces quota (10,000 req/day per subscription)

### 2. backend-integration-policy.xml
**Purpose:** Route requests to your backend services  
**Apply to:** APIs that proxy to backend microservices/systems  
**What it does:**
- Routes to backend service URL
- Adds correlation headers
- Implements retry logic for failed requests
- Returns standardized error responses

---

## 🔴 IMPORTANT: MuleSoft is NOT a Backend Service!

### What MuleSoft Actually Is
**MuleSoft is an EXTERNAL CLIENT** that calls your API Gateway, just like:
- Mobile apps
- Web applications  
- Third-party integrations
- Any other API consumer

### Traffic Flow with MuleSoft

```
┌─────────────┐
│  MuleSoft   │ (External Integration Platform)
│  Platform   │
└──────┬──────┘
       │
       │ HTTPS (443)
       │ GET /api/v1/customers
       │ Authorization: Bearer {jwt_token}
       │
       ↓
┌─────────────┐
│   Public    │
│  IP/FQDN    │
└──────┬──────┘
       │
       ↓
┌─────────────┐
│ App Gateway │ (WAF v2)
│   + WAF     │
└──────┬──────┘
       │
       │ Internal VNet
       ↓
┌─────────────┐
│     APIM    │ (Validates JWT with Auth0)
│   Gateway   │
└──────┬──────┘
       │
       ↓
┌─────────────┐
│   Backend   │ (YOUR microservices/APIs)
│   Services  │
└─────────────┘
```

### How MuleSoft Authenticates

1. **MuleSoft gets a JWT token from Auth0:**
   ```bash
   POST https://your-tenant.auth0.com/oauth/token
   {
     "client_id": "mulesoft_client_id",
     "client_secret": "mulesoft_client_secret",
     "audience": "https://api.yourdomain.com",
     "grant_type": "client_credentials"
   }
   ```

2. **MuleSoft calls your API Gateway with the token:**
   ```bash
   GET https://your-appgateway-fqdn.cloudapp.azure.com/api/v1/customers
   Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
   ```

3. **APIM validates the token using api-auth0-policy.xml**

4. **APIM routes to your backend using backend-integration-policy.xml**

### NO Special MuleSoft Policy Needed!

❌ **Don't create:** "MuleSoft integration policy"  
✅ **Do use:** Standard Auth0 JWT validation policy  

**Why?** Because MuleSoft is just another client. It authenticates the same way as any other external system.

---

## 🎯 Policy Application Guide

### Option 1: Apply at Product Level (Recommended)
All APIs in the product inherit the policy:
```bash
az apim product policy create \
  --resource-group rg-apim-public-dev \
  --service-name myproject-dev-apim \
  --product-id unlimited \
  --xml-content @policies/api-auth0-policy.xml
```

### Option 2: Apply at API Level
Specific to one API:
```bash
az apim api policy create \
  --resource-group rg-apim-public-dev \
  --service-name myproject-dev-apim \
  --api-id customers-api \
  --xml-content @policies/api-auth0-policy.xml
```

### Option 3: Apply at Operation Level
Specific to one endpoint:
```bash
az apim api operation policy create \
  --resource-group rg-apim-public-dev \
  --service-name myproject-dev-apim \
  --api-id customers-api \
  --operation-id get-customer \
  --xml-content @policies/backend-integration-policy.xml
```

---

## 🔧 Customizing Policies

### Update Auth0 Configuration
The Auth0 policy references named values created during deployment:
- `{{auth0-domain}}` → Your Auth0 tenant domain
- `{{auth0-audience}}` → Your Auth0 API identifier

These are set in the parameter files. No need to edit the policy XML.

### Update Backend URL
The backend policy references:
- `{{backend-service-url}}` → Your actual backend API URL

Set this in the parameter file (`backendServiceUrl` parameter).

### Add Custom Headers
Edit the policy to add your own headers:
```xml
<set-header name="X-Custom-Header" exists-action="override">
    <value>custom-value</value>
</set-header>
```

---

## 📝 Example: Complete Setup for MuleSoft Client

1. **Create Auth0 Machine-to-Machine Application:**
   - Name: "MuleSoft Integration"
   - Get Client ID and Client Secret
   - Authorize for your API

2. **Give MuleSoft the credentials:**
   - Auth0 Domain: `your-tenant.auth0.com`
   - Client ID: `abc123...`
   - Client Secret: `secret456...`
   - API Audience: `https://api.yourdomain.com`
   - API Gateway URL: `https://your-appgw.cloudapp.azure.com`

3. **MuleSoft configuration (their side):**
   ```xml
   <!-- MuleSoft flow -->
   <http:request method="POST" url="https://your-tenant.auth0.com/oauth/token">
       <http:body>
           {
               "client_id": "${auth0.client.id}",
               "client_secret": "${auth0.client.secret}",
               "audience": "https://api.yourdomain.com",
               "grant_type": "client_credentials"
           }
       </http:body>
   </http:request>
   
   <http:request method="GET" url="https://your-appgw.cloudapp.azure.com/api/v1/customers">
       <http:headers>
           <http:header name="Authorization" value="Bearer #[payload.access_token]"/>
       </http:headers>
   </http:request>
   ```

4. **Your APIM automatically handles it:**
   - Receives request at App Gateway
   - WAF inspects
   - APIM validates JWT with Auth0
   - Routes to backend
   - Returns response

**That's it!** No special MuleSoft policy or configuration needed on your side.

---

## ✅ Summary

| System | Role | Authentication | Policy Needed |
|--------|------|---------------|---------------|
| **MuleSoft** | External Client | JWT from Auth0 | Auth0 JWT validation |
| **Mobile App** | External Client | JWT from Auth0 | Auth0 JWT validation |
| **Web App** | External Client | JWT from Auth0 | Auth0 JWT validation |
| **Backend APIs** | Internal Service | N/A (called by APIM) | Backend integration |

**Key Takeaway:** MuleSoft = Just another external client. Treat it like any other API consumer with JWT authentication.
