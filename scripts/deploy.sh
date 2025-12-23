#!/bin/bash

###############################################################################
# Azure API Management with Private Endpoint - Deployment Script (Bash)
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

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT="${1:-dev}"  # dev, staging, or prod
RESOURCE_GROUP_NAME="rg-apim-private-${ENVIRONMENT}"
LOCATION="eastus"
TEMPLATE_FILE="./templates/main.json"
PARAMETERS_FILE="./parameters/${ENVIRONMENT}.parameters.json"
DEPLOYMENT_NAME="apim-private-deployment-$(date +%Y%m%d-%H%M%S)"

# Functions
print_header() {
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    print_success "Azure CLI is installed"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Running 'az login'..."
        az login
    fi
    print_success "Logged in to Azure"
    
    # Check if template files exist
    if [ ! -f "$TEMPLATE_FILE" ]; then
        print_error "Template file not found: $TEMPLATE_FILE"
        exit 1
    fi
    print_success "Template file found"
    
    if [ ! -f "$PARAMETERS_FILE" ]; then
        print_error "Parameters file not found: $PARAMETERS_FILE"
        exit 1
    fi
    print_success "Parameters file found"
    
    # Display current Azure subscription
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    print_info "Current subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    
    echo
    read -p "Continue with this subscription? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Deployment cancelled"
        exit 0
    fi
}

create_resource_group() {
    print_header "Creating Resource Group"
    
    # Check if resource group exists
    if az group exists --name "$RESOURCE_GROUP_NAME" | grep -q "true"; then
        print_warning "Resource group already exists: $RESOURCE_GROUP_NAME"
    else
        print_info "Creating resource group: $RESOURCE_GROUP_NAME in $LOCATION"
        az group create \
            --name "$RESOURCE_GROUP_NAME" \
            --location "$LOCATION" \
            --output none
        print_success "Resource group created"
    fi
}

validate_template() {
    print_header "Validating ARM Template"
    
    print_info "Running template validation..."
    VALIDATION_OUTPUT=$(az deployment group validate \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETERS_FILE" \
        --output json 2>&1)
    
    if [ $? -eq 0 ]; then
        print_success "Template validation successful"
    else
        print_error "Template validation failed"
        echo "$VALIDATION_OUTPUT"
        exit 1
    fi
}

preview_changes() {
    print_header "Previewing Deployment Changes (What-If)"
    
    print_info "Running what-if analysis..."
    az deployment group what-if \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETERS_FILE" \
        --no-pretty-print
    
    echo
    read -p "Continue with deployment? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Deployment cancelled"
        exit 0
    fi
}

deploy_infrastructure() {
    print_header "Deploying Infrastructure"
    
    print_info "Starting deployment: $DEPLOYMENT_NAME"
    print_warning "This deployment will take 45-60 minutes (APIM provisioning is slow)"
    
    # Start deployment
    DEPLOYMENT_START=$(date +%s)
    
    az deployment group create \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETERS_FILE" \
        --verbose \
        --output json > deployment-output.json
    
    DEPLOYMENT_STATUS=$?
    DEPLOYMENT_END=$(date +%s)
    DEPLOYMENT_DURATION=$((DEPLOYMENT_END - DEPLOYMENT_START))
    
    if [ $DEPLOYMENT_STATUS -eq 0 ]; then
        print_success "Deployment completed successfully"
        print_info "Deployment duration: $((DEPLOYMENT_DURATION / 60)) minutes"
    else
        print_error "Deployment failed"
        cat deployment-output.json
        exit 1
    fi
}

display_outputs() {
    print_header "Deployment Outputs"
    
    # Extract outputs from deployment
    APIM_NAME=$(jq -r '.properties.outputs.apimName.value' deployment-output.json)
    APIM_URL=$(jq -r '.properties.outputs.apimGatewayUrl.value' deployment-output.json)
    PRIVATE_ENDPOINT_IP=$(jq -r '.properties.outputs.privateEndpointIp.value' deployment-output.json)
    APP_GATEWAY_IP=$(jq -r '.properties.outputs.appGatewayFrontendIp.value' deployment-output.json)
    KEY_VAULT_NAME=$(jq -r '.properties.outputs.keyVaultName.value' deployment-output.json)
    
    echo
    print_success "API Management Service: $APIM_NAME"
    print_success "API Gateway URL: $APIM_URL"
    print_success "Private Endpoint IP: $PRIVATE_ENDPOINT_IP"
    print_success "App Gateway Private IP: $APP_GATEWAY_IP"
    print_success "Key Vault Name: $KEY_VAULT_NAME"
    echo
    
    print_info "Next Steps:"
    echo "1. Configure DNS to point to Private Endpoint IP: $PRIVATE_ENDPOINT_IP"
    echo "2. Upload SSL certificates to Key Vault: $KEY_VAULT_NAME"
    echo "3. Import APIs into APIM: $APIM_NAME"
    echo "4. Apply APIM policies from ./policies/ directory"
    echo "5. Configure Auth0 application and update named values"
    echo
}

post_deployment_checks() {
    print_header "Post-Deployment Verification"
    
    # Check APIM provisioning state
    print_info "Checking APIM provisioning state..."
    APIM_NAME=$(jq -r '.properties.outputs.apimName.value' deployment-output.json)
    APIM_STATE=$(az apim show \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --name "$APIM_NAME" \
        --query provisioningState \
        --output tsv)
    
    if [ "$APIM_STATE" == "Succeeded" ]; then
        print_success "APIM is successfully provisioned"
    else
        print_warning "APIM provisioning state: $APIM_STATE"
    fi
    
    # Check Application Gateway backend health
    print_info "Checking Application Gateway backend health..."
    APP_GATEWAY_NAME=$(jq -r '.properties.outputs.deploymentSummary.value.projectName' deployment-output.json)-$(jq -r '.properties.outputs.deploymentSummary.value.environment' deployment-output.json)-appgw
    
    az network application-gateway show-backend-health \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --name "$APP_GATEWAY_NAME" \
        --output table || print_warning "Backend health check not yet available"
    
    echo
}

cleanup_on_error() {
    print_header "Cleaning Up Failed Deployment"
    
    print_warning "Do you want to delete the resource group? (y/n)"
    read -r RESPONSE
    if [[ "$RESPONSE" =~ ^[Yy]$ ]]; then
        print_info "Deleting resource group: $RESOURCE_GROUP_NAME"
        az group delete --name "$RESOURCE_GROUP_NAME" --yes --no-wait
        print_success "Resource group deletion initiated"
    fi
}

# Main execution
main() {
    print_header "Azure APIM Private Endpoint Deployment"
    print_info "Environment: $ENVIRONMENT"
    print_info "Resource Group: $RESOURCE_GROUP_NAME"
    print_info "Location: $LOCATION"
    echo
    
    # Execute deployment steps
    check_prerequisites
    create_resource_group
    validate_template
    preview_changes
    
    # Deploy infrastructure
    if deploy_infrastructure; then
        display_outputs
        post_deployment_checks
        
        print_success "Deployment completed successfully!"
        print_info "Deployment logs saved to: deployment-output.json"
    else
        print_error "Deployment failed!"
        cleanup_on_error
        exit 1
    fi
}

# Trap errors
trap 'print_error "An error occurred. Exiting..."; exit 1' ERR

# Run main function
main

exit 0
