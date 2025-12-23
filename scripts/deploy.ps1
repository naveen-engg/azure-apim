###############################################################################
# Azure API Management with Private Endpoint - Deployment Script (PowerShell)
# 
# This script deploys the complete APIM infrastructure including:
# - Virtual Network with subnets and NSGs
# - API Management in Internal VNet mode
# - Application Gateway with WAF v2 and Private Frontend
# - Private Endpoint for App Gateway
# - Private DNS Zone
# - Key Vault with Managed Identity
# - Monitoring (Log Analytics + Application Insights)
###############################################################################

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipWhatIf,
    
    [Parameter(Mandatory=$false)]
    [switch]$NoValidation
)

# Error action preference
$ErrorActionPreference = "Stop"

# Configuration
$resourceGroupName = "rg-apim-private-$Environment"
$location = "eastus"
$templateFile = ".\templates\main.json"
$parametersFile = ".\parameters\$Environment.parameters.json"
$deploymentName = "apim-private-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

# Color output functions
function Write-Header {
    param([string]$Message)
    Write-Host "`n============================================================" -ForegroundColor Blue
    Write-Host "  $Message" -ForegroundColor Blue
    Write-Host "============================================================`n" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Failure {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ $Message" -ForegroundColor Cyan
}

# Check prerequisites
function Test-Prerequisites {
    Write-Header "Checking Prerequisites"
    
    # Check if Azure PowerShell module is installed
    if (-not (Get-Module -ListAvailable -Name Az)) {
        Write-Failure "Azure PowerShell module (Az) is not installed"
        Write-Info "Install it with: Install-Module -Name Az -AllowClobber -Scope CurrentUser"
        exit 1
    }
    Write-Success "Azure PowerShell module is installed"
    
    # Check if connected to Azure
    try {
        $context = Get-AzContext
        if (-not $context) {
            Write-Warning "Not connected to Azure. Running Connect-AzAccount..."
            Connect-AzAccount
            $context = Get-AzContext
        }
        Write-Success "Connected to Azure"
        
        # Display current subscription
        Write-Info "Current subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
        
        $continue = Read-Host "Continue with this subscription? (Y/N)"
        if ($continue -ne 'Y' -and $continue -ne 'y') {
            Write-Warning "Deployment cancelled"
            exit 0
        }
    }
    catch {
        Write-Failure "Failed to connect to Azure: $_"
        exit 1
    }
    
    # Check if template files exist
    if (-not (Test-Path $templateFile)) {
        Write-Failure "Template file not found: $templateFile"
        exit 1
    }
    Write-Success "Template file found"
    
    if (-not (Test-Path $parametersFile)) {
        Write-Failure "Parameters file not found: $parametersFile"
        exit 1
    }
    Write-Success "Parameters file found"
}

# Create resource group
function New-AzureResourceGroup {
    Write-Header "Creating Resource Group"
    
    $rg = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
    
    if ($rg) {
        Write-Warning "Resource group already exists: $resourceGroupName"
    }
    else {
        Write-Info "Creating resource group: $resourceGroupName in $location"
        New-AzResourceGroup -Name $resourceGroupName -Location $location | Out-Null
        Write-Success "Resource group created"
    }
}

# Validate ARM template
function Test-ArmTemplate {
    Write-Header "Validating ARM Template"
    
    Write-Info "Running template validation..."
    
    try {
        $validation = Test-AzResourceGroupDeployment `
            -ResourceGroupName $resourceGroupName `
            -TemplateFile $templateFile `
            -TemplateParameterFile $parametersFile
        
        if ($validation) {
            Write-Failure "Template validation failed"
            $validation | Format-List
            exit 1
        }
        else {
            Write-Success "Template validation successful"
        }
    }
    catch {
        Write-Failure "Template validation failed: $_"
        exit 1
    }
}

# Preview deployment changes
function Show-DeploymentPreview {
    Write-Header "Previewing Deployment Changes (What-If)"
    
    Write-Info "Running what-if analysis..."
    Write-Warning "This may take a few minutes..."
    
    try {
        $whatIfParams = @{
            ResourceGroupName     = $resourceGroupName
            TemplateFile          = $templateFile
            TemplateParameterFile = $parametersFile
            ResultFormat          = 'ResourceIdOnly'
        }
        
        $whatIfResult = Get-AzResourceGroupDeploymentWhatIfResult @whatIfParams
        
        Write-Host "`nResources to be created or modified:"
        $whatIfResult.Changes | ForEach-Object {
            $changeType = $_.ChangeType
            $resourceId = $_.ResourceId
            
            switch ($changeType) {
                'Create' { Write-Host "  + CREATE: $resourceId" -ForegroundColor Green }
                'Modify' { Write-Host "  ~ MODIFY: $resourceId" -ForegroundColor Yellow }
                'Delete' { Write-Host "  - DELETE: $resourceId" -ForegroundColor Red }
                default  { Write-Host "  ? $changeType`: $resourceId" -ForegroundColor Cyan }
            }
        }
        
        Write-Host ""
        $continue = Read-Host "Continue with deployment? (Y/N)"
        if ($continue -ne 'Y' -and $continue -ne 'y') {
            Write-Warning "Deployment cancelled"
            exit 0
        }
    }
    catch {
        Write-Warning "What-if analysis failed: $_"
        Write-Info "Continuing with deployment..."
    }
}

# Deploy infrastructure
function Start-InfrastructureDeployment {
    Write-Header "Deploying Infrastructure"
    
    Write-Info "Starting deployment: $deploymentName"
    Write-Warning "This deployment will take 45-60 minutes (APIM provisioning is slow)"
    
    $deploymentStart = Get-Date
    
    try {
        $deployment = New-AzResourceGroupDeployment `
            -Name $deploymentName `
            -ResourceGroupName $resourceGroupName `
            -TemplateFile $templateFile `
            -TemplateParameterFile $parametersFile `
            -Verbose
        
        $deploymentEnd = Get-Date
        $duration = $deploymentEnd - $deploymentStart
        
        Write-Success "Deployment completed successfully"
        Write-Info "Deployment duration: $($duration.Minutes) minutes"
        
        return $deployment
    }
    catch {
        Write-Failure "Deployment failed: $_"
        
        # Show deployment errors
        $operations = Get-AzResourceGroupDeploymentOperation `
            -ResourceGroupName $resourceGroupName `
            -DeploymentName $deploymentName
        
        $operations | Where-Object { $_.ProvisioningState -eq 'Failed' } | ForEach-Object {
            Write-Host "`nFailed Operation:" -ForegroundColor Red
            Write-Host "  Resource: $($_.TargetResource.ResourceName)" -ForegroundColor Yellow
            Write-Host "  Type: $($_.TargetResource.ResourceType)" -ForegroundColor Yellow
            Write-Host "  Error: $($_.StatusMessage)" -ForegroundColor Red
        }
        
        throw
    }
}

# Display deployment outputs
function Show-DeploymentOutputs {
    param([object]$Deployment)
    
    Write-Header "Deployment Outputs"
    
    $outputs = $Deployment.Outputs
    
    Write-Success "API Management Service: $($outputs.apimName.Value)"
    Write-Success "API Gateway URL: $($outputs.apimGatewayUrl.Value)"
    Write-Success "Private Endpoint IP: $($outputs.privateEndpointIp.Value)"
    Write-Success "App Gateway Private IP: $($outputs.appGatewayFrontendIp.Value)"
    Write-Success "Key Vault Name: $($outputs.keyVaultName.Value)"
    
    Write-Info "`nNext Steps:"
    Write-Host "1. Configure DNS to point to Private Endpoint IP: $($outputs.privateEndpointIp.Value)"
    Write-Host "2. Upload SSL certificates to Key Vault: $($outputs.keyVaultName.Value)"
    Write-Host "3. Import APIs into APIM: $($outputs.apimName.Value)"
    Write-Host "4. Apply APIM policies from .\policies\ directory"
    Write-Host "5. Configure Auth0 application and update named values"
    Write-Host ""
    
    # Save outputs to file
    $outputFile = "deployment-output-$Environment.json"
    $outputs | ConvertTo-Json -Depth 10 | Out-File $outputFile
    Write-Success "Deployment outputs saved to: $outputFile"
}

# Post-deployment verification
function Test-Deployment {
    param([object]$Deployment)
    
    Write-Header "Post-Deployment Verification"
    
    # Check APIM provisioning state
    Write-Info "Checking APIM provisioning state..."
    $apimName = $Deployment.Outputs.apimName.Value
    
    try {
        $apim = Get-AzApiManagement -ResourceGroupName $resourceGroupName -Name $apimName
        
        if ($apim.ProvisioningState -eq 'Succeeded') {
            Write-Success "APIM is successfully provisioned"
        }
        else {
            Write-Warning "APIM provisioning state: $($apim.ProvisioningState)"
        }
    }
    catch {
        Write-Warning "Failed to check APIM state: $_"
    }
    
    # Check Application Gateway backend health
    Write-Info "Checking Application Gateway backend health..."
    $appGwName = "$($Deployment.Outputs.deploymentSummary.Value.projectName)-$($Deployment.Outputs.deploymentSummary.Value.environment)-appgw"
    
    try {
        $backendHealth = Get-AzApplicationGatewayBackendHealth `
            -ResourceGroupName $resourceGroupName `
            -Name $appGwName
        
        Write-Host "`nBackend Health Status:"
        $backendHealth.BackendAddressPools | ForEach-Object {
            $pool = $_
            Write-Host "  Pool: $($pool.BackendAddressPool.Id.Split('/')[-1])"
            
            $pool.BackendHttpSettingsCollection | ForEach-Object {
                $settings = $_
                Write-Host "    Settings: $($settings.BackendHttpSettings.Id.Split('/')[-1])"
                
                $settings.Servers | ForEach-Object {
                    $server = $_
                    $status = if ($server.Health -eq 'Healthy') { 'Green' } else { 'Red' }
                    Write-Host "      Server: $($server.Address) - " -NoNewline
                    Write-Host "$($server.Health)" -ForegroundColor $status
                }
            }
        }
    }
    catch {
        Write-Warning "Backend health check not yet available: $_"
    }
    
    Write-Host ""
}

# Cleanup on error
function Remove-FailedDeployment {
    Write-Header "Cleaning Up Failed Deployment"
    
    $response = Read-Host "Do you want to delete the resource group? (Y/N)"
    if ($response -eq 'Y' -or $response -eq 'y') {
        Write-Info "Deleting resource group: $resourceGroupName"
        Remove-AzResourceGroup -Name $resourceGroupName -Force -AsJob | Out-Null
        Write-Success "Resource group deletion initiated"
    }
}

# Main execution
function Main {
    Write-Header "Azure APIM Private Endpoint Deployment"
    Write-Info "Environment: $Environment"
    Write-Info "Resource Group: $resourceGroupName"
    Write-Info "Location: $location"
    
    try {
        # Execute deployment steps
        Test-Prerequisites
        New-AzureResourceGroup
        
        if (-not $NoValidation) {
            Test-ArmTemplate
        }
        
        if (-not $SkipWhatIf) {
            Show-DeploymentPreview
        }
        
        # Deploy infrastructure
        $deployment = Start-InfrastructureDeployment
        
        # Show results
        Show-DeploymentOutputs -Deployment $deployment
        Test-Deployment -Deployment $deployment
        
        Write-Success "`nDeployment completed successfully!"
    }
    catch {
        Write-Failure "`nDeployment failed: $_"
        Remove-FailedDeployment
        exit 1
    }
}

# Run main function
Main
