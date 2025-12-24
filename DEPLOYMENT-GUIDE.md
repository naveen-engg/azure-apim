# Environment Comparison Guide

## 🌍 Quick Environment Reference

### Development Environment
**Purpose:** Local development, feature testing, debugging  
**Network:** 10.0.0.0/16  

```mermaid
graph LR
    Dev[Development] --> Features[Feature Testing<br/>Local Development<br/>Debug Mode]
    
    style Dev fill:#E3F2FD,stroke:#1976D2,stroke-width:2px,color:#000
    style Features fill:#FFF3E0,stroke:#F57C00,stroke-width:2px,color:#000
```

**Configuration:**
- APIM SKU: Developer (1 unit)
- App Gateway: 2 instances
- WAF Mode: Detection (logs only)
- Log Retention: 30 days
- VNet: 10.0.0.0/16

---

### Staging Environment
**Purpose:** Pre-production testing, UAT, performance testing  
**Network:** 10.5.0.0/16  

```mermaid
graph LR
    Staging[Staging] --> Tests[UAT<br/>Integration Tests<br/>Performance Tests]
    
    style Staging fill:#E8F5E9,stroke:#388E3C,stroke-width:2px,color:#000
    style Tests fill:#FFF9C4,stroke:#F57F17,stroke-width:2px,color:#000
```

**Configuration:**
- APIM SKU: Developer (1 unit)
- App Gateway: 2-7 instances (autoscale)
- WAF Mode: Prevention (blocks threats)
- Log Retention: 60 days
- VNet: 10.5.0.0/16

---

### Production Environment
**Purpose:** Live customer traffic, mission-critical workloads  
**Network:** 10.10.0.0/16  

```mermaid
graph LR
    Prod[Production] --> Live[Customer Traffic<br/>High Availability<br/>Multi-Region]
    
    style Prod fill:#FFEBEE,stroke:#C62828,stroke-width:2px,color:#000
    style Live fill:#E1BEE7,stroke:#8E24AA,stroke-width:2px,color:#000
```

**Configuration:**
- APIM SKU: Premium (2 units)
- App Gateway: 3-10 instances (autoscale)
- WAF Mode: Prevention (blocks threats)
- Log Retention: 90 days
- VNet: 10.10.0.0/16

---

## 📊 Side-by-Side Comparison

| Feature | Development | Staging | Production |
|---------|-------------|---------|------------|
| **APIM SKU** | Developer | Developer | Premium |
| **APIM Capacity** | 1 unit | 1 unit | 2 units |
| **Multi-Region** | ❌ No | ❌ No | ✅ Yes |
| **App Gateway Min** | 2 instances | 2 instances | 3 instances |
| **App Gateway Max** | 5 instances | 7 instances | 10 instances |
| **WAF Mode** | Detection | Prevention | Prevention |
| **Log Retention** | 30 days | 60 days | 90 days |
| **VNet Range** | 10.0.0.0/16 | 10.5.0.0/16 | 10.10.0.0/16 |
| **SLA** | None | None | 99.95% |
| **Use Case** | Dev & Debug | UAT & Testing | Production |

---

## 🏗️ ARM Template Deployment Sequence

```mermaid
sequenceDiagram
    participant User
    participant Main as main.json
    participant Monitor as monitoring.json
    participant Network as network.json
    participant KV as keyvault.json
    participant APIM as apim.json
    participant AppGw as appgateway.json
    
    User->>Main: 1. Deploy main.json<br/>with parameters
    
    Main->>Monitor: 2. Deploy Monitoring
    Note over Monitor: Creates:<br/>- Log Analytics<br/>- App Insights
    Monitor-->>Main: Workspace ID
    
    Main->>Network: 3. Deploy Network
    Note over Network: Creates:<br/>- VNet<br/>- 2 Subnets<br/>- 2 NSGs
    Network-->>Main: Subnet IDs
    
    Main->>KV: 4. Deploy Key Vault
    Note over KV: Creates:<br/>- Key Vault<br/>- Access Policies<br/>- Diagnostics
    KV-->>Main: Key Vault Name
    
    Main->>APIM: 5. Deploy API Management
    Note over APIM: Creates:<br/>- APIM Service<br/>- Named Values<br/>- Managed Identity<br/>- Diagnostics
    APIM-->>Main: APIM Private IP<br/>Principal ID
    
    Main->>AppGw: 6. Deploy App Gateway
    Note over AppGw: Creates:<br/>- Public IP<br/>- App Gateway<br/>- WAF Policy<br/>- Backend Pool<br/>- Diagnostics
    AppGw-->>Main: Public IP & FQDN
    
    Main-->>User: Deployment Complete<br/>All Outputs
```

---

## 📂 ARM Template Files Breakdown

### Template Execution Order

```mermaid
graph TB
    Start[Start Deployment] --> Main[main.json<br/>Orchestration]
    
    Main --> Step1[monitoring.json]
    Step1 --> LA[Log Analytics<br/>App Insights]
    
    Main --> Step2[network.json]
    Step2 --> Net[VNet + Subnets<br/>NSG Rules]
    
    Main --> Step3[keyvault.json]
    Step3 --> KV[Key Vault<br/>Access Policies]
    
    Main --> Step4[apim.json]
    Step4 --> APIM[API Management<br/>Internal VNet<br/>Named Values]
    
    Main --> Step5[appgateway.json]
    Step5 --> AppGw[App Gateway<br/>WAF v2<br/>Public IP]
    
    LA --> Complete[Deployment Complete]
    Net --> Complete
    KV --> Complete
    APIM --> Complete
    AppGw --> Complete
    
    style Main fill:#E3F2FD,stroke:#1976D2,stroke-width:2px,color:#000
    style Step1 fill:#FFF3E0,stroke:#F57C00,stroke-width:2px,color:#000
    style Step2 fill:#E8F5E9,stroke:#388E3C,stroke-width:2px,color:#000
    style Step3 fill:#FFF9C4,stroke:#F57F17,stroke-width:2px,color:#000
    style Step4 fill:#FCE4EC,stroke:#C2185B,stroke-width:2px,color:#000
    style Step5 fill:#F3E5F5,stroke:#7B1FA2,stroke-width:2px,color:#000
    style Complete fill:#C8E6C9,stroke:#388E3C,stroke-width:3px,color:#000
```

### File Descriptions

| File | Resources Created | Dependencies |
|------|-------------------|--------------|
| **main.json** | Orchestrates all deployments | None (entry point) |
| **monitoring.json** | Log Analytics Workspace<br/>Application Insights | None |
| **network.json** | Virtual Network<br/>APIM Subnet (10.x.1.0/24)<br/>App Gateway Subnet (10.x.2.0/24)<br/>NSG for APIM<br/>NSG for App Gateway | None |
| **keyvault.json** | Key Vault<br/>Admin Access Policy<br/>Diagnostic Settings | monitoring.json |
| **apim.json** | API Management Service<br/>Managed Identity<br/>Named Values (Auth0)<br/>Logger (App Insights)<br/>Diagnostics | network.json<br/>keyvault.json<br/>monitoring.json |
| **appgateway.json** | Public IP Address<br/>Application Gateway<br/>WAF Policy<br/>Backend Pool (to APIM)<br/>Listeners & Rules<br/>Diagnostics | network.json<br/>apim.json<br/>monitoring.json |

---

## 🚀 Deployment Commands

### Development
```bash
# Bash
./scripts/deploy.sh dev

# PowerShell
.\scripts\deploy.ps1 -Environment dev
```

### Staging
```bash
# Bash
./scripts/deploy.sh staging

# PowerShell
.\scripts\deploy.ps1 -Environment staging
```

### Production
```bash
# Bash
./scripts/deploy.sh prod

# PowerShell
.\scripts\deploy.ps1 -Environment prod
```

---

## 🔄 Promotion Path

```mermaid
graph LR
    Dev[Development<br/>10.0.0.0/16] -->|Test & Validate| Staging[Staging<br/>10.5.0.0/16]
    Staging -->|UAT Approval| Prod[Production<br/>10.10.0.0/16]
    
    style Dev fill:#E3F2FD,stroke:#1976D2,stroke-width:2px,color:#000
    style Staging fill:#E8F5E9,stroke:#388E3C,stroke-width:2px,color:#000
    style Prod fill:#FFEBEE,stroke:#C62828,stroke-width:2px,color:#000
```

**Typical Flow:**
1. **Dev**: Develop features, test locally
2. **Staging**: Integration tests, UAT, performance validation
3. **Production**: Deploy to customers

---

## 📋 Environment Checklist

### Before Deploying to Dev
- [ ] Update `dev.parameters.json` with Object ID
- [ ] Update Auth0 dev domain
- [ ] Configure backend URLs

### Before Deploying to Staging
- [ ] Copy working config from dev
- [ ] Update `staging.parameters.json`
- [ ] Enable WAF Prevention mode
- [ ] Configure staging Auth0 tenant
- [ ] Update MuleSoft staging endpoints

### Before Deploying to Production
- [ ] Validate in staging environment
- [ ] Review WAF exclusion rules
- [ ] Upload SSL certificates to Key Vault
- [ ] Configure custom domain DNS
- [ ] Enable all monitoring alerts
- [ ] Document runbook procedures
- [ ] Plan rollback strategy
- [ ] Notify stakeholders

---

## 🎯 Best Practices

### Development
- Use for rapid iteration
- Test breaking changes
- Debug with Detection mode WAF
- Quick feedback loops

### Staging
- Mirror production configuration
- Run full integration tests
- Validate performance under load
- Test disaster recovery
- Use Prevention mode WAF

### Production
- Premium SKU for SLA
- Multi-region for HA
- Comprehensive monitoring
- Regular security audits
- Automated backups

---

## 💡 Tips

**Network Isolation:**
- Each environment has separate VNet
- No network connectivity between environments
- Prevents accidental cross-environment access

**Testing Strategy:**
- Dev: Unit tests, feature validation
- Staging: Integration tests, UAT, load tests
- Prod: Monitoring, alerting, incident response

**Deployment Time:**
- Total deployment: 45-60 minutes
- APIM provisioning: 40-50 minutes (slowest)
- Network resources: 2-5 minutes
- App Gateway: 10-15 minutes

---

**Need Help?** Review the main README.md for detailed setup instructions.