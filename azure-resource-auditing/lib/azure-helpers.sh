#!/bin/bash
# Azure CLI Helper Functions
# Utilities for Azure authentication, subscription management, and error handling

# Source logging if available
if [[ -f "${LIB_DIR:-./}/logging.sh" ]]; then
    source "${LIB_DIR:-./}/logging.sh"
fi

# Azure CLI version requirements
readonly MIN_AZURE_CLI_VERSION="2.50.0"

# Check if Azure CLI is installed and meets minimum version
check_azure_cli() {
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI not found. Please install Azure CLI 2.50.0 or later"
        log_error "Installation guide: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        return 1
    fi
    
    local current_version
    current_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null)
    
    if [[ -z "$current_version" ]]; then
        log_error "Unable to determine Azure CLI version"
        return 1
    fi
    
    if ! version_compare "$current_version" "$MIN_AZURE_CLI_VERSION"; then
        log_error "Azure CLI version $current_version is below minimum required version $MIN_AZURE_CLI_VERSION"
        log_error "Please update Azure CLI: az upgrade"
        return 1
    fi
    
    log_success "Azure CLI version $current_version meets requirements"
    return 0
}

# Compare version strings (returns 0 if first >= second)
version_compare() {
    local version1="$1"
    local version2="$2"
    
    # Convert version strings to arrays
    IFS='.' read -ra V1 <<< "$version1"
    IFS='.' read -ra V2 <<< "$version2"
    
    # Pad arrays to same length
    local max_length=$((${#V1[@]} > ${#V2[@]} ? ${#V1[@]} : ${#V2[@]}))
    
    for ((i=0; i<max_length; i++)); do
        local num1=${V1[i]:-0}
        local num2=${V2[i]:-0}
        
        if ((num1 > num2)); then
            return 0
        elif ((num1 < num2)); then
            return 1
        fi
    done
    
    return 0  # Equal versions
}

# Check Azure authentication status
check_azure_auth() {
    log_debug "Checking Azure authentication status..."
    
    if ! az account show &>/dev/null; then
        log_error "Not authenticated to Azure"
        log_info "Please run 'az login' to authenticate"
        return 1
    fi
    
    local account_info
    account_info=$(az account show --query '{name:name, id:id, user:user.name, tenantId:tenantId}' -o json 2>/dev/null)
    
    if [[ -z "$account_info" ]]; then
        log_error "Unable to retrieve account information"
        return 1
    fi
    
    local account_name user_name tenant_id
    account_name=$(echo "$account_info" | jq -r '.name // "Unknown"')
    user_name=$(echo "$account_info" | jq -r '.user // "Unknown"')
    tenant_id=$(echo "$account_info" | jq -r '.tenantId // "Unknown"')
    
    log_success "Authenticated to Azure"
    log_info "Account: $account_name"
    log_info "User: $user_name"
    log_info "Tenant: $tenant_id"
    
    return 0
}

# Authenticate to Azure with multiple methods
authenticate_azure() {
    log_info "Authenticating to Azure..."
    
    # Check if already authenticated
    if check_azure_auth; then
        return 0
    fi
    
    # Try different authentication methods
    log_info "Attempting authentication..."
    
    # Method 1: Try service principal with environment variables
    if [[ -n "${AZURE_CLIENT_ID:-}" && -n "${AZURE_CLIENT_SECRET:-}" && -n "${AZURE_TENANT_ID:-}" ]]; then
        log_info "Using service principal authentication"
        if az login --service-principal \
            --username "$AZURE_CLIENT_ID" \
            --password "$AZURE_CLIENT_SECRET" \
            --tenant "$AZURE_TENANT_ID" &>/dev/null; then
            log_success "Service principal authentication successful"
            return 0
        else
            log_warn "Service principal authentication failed"
        fi
    fi
    
    # Method 2: Try managed identity (for Azure VMs)
    if az login --identity &>/dev/null; then
        log_success "Managed identity authentication successful"
        return 0
    fi
    
    # Method 3: Interactive login
    log_info "Attempting interactive authentication..."
    if az login &>/dev/null; then
        log_success "Interactive authentication successful"
        return 0
    fi
    
    log_error "All authentication methods failed"
    return 1
}

# Set active subscription
set_subscription() {
    local subscription_id="$1"
    
    if [[ -z "$subscription_id" ]]; then
        log_error "Subscription ID is required"
        return 1
    fi
    
    log_info "Setting active subscription to: $subscription_id"
    
    if az account set --subscription "$subscription_id" &>/dev/null; then
        # Verify the subscription was set correctly
        local current_sub
        current_sub=$(az account show --query 'id' -o tsv 2>/dev/null)
        
        if [[ "$current_sub" == "$subscription_id" ]]; then
            local sub_name
            sub_name=$(az account show --query 'name' -o tsv 2>/dev/null)
            log_success "Active subscription set to: $sub_name ($subscription_id)"
            return 0
        else
            log_error "Failed to verify subscription change"
            return 1
        fi
    else
        log_error "Failed to set subscription: $subscription_id"
        log_info "Available subscriptions:"
        az account list --query '[].{Name:name, Id:id, State:state}' -o table
        return 1
    fi
}

# Validate subscription access
validate_subscription() {
    local subscription_id="$1"
    
    log_debug "Validating access to subscription: $subscription_id"
    
    # Check if subscription exists and is accessible
    local subscription_info
    subscription_info=$(az account show --subscription "$subscription_id" --query '{id:id, name:name, state:state}' -o json 2>/dev/null)
    
    if [[ -z "$subscription_info" ]]; then
        log_error "Cannot access subscription: $subscription_id"
        log_info "Please verify the subscription ID and your permissions"
        return 1
    fi
    
    local sub_name sub_state
    sub_name=$(echo "$subscription_info" | jq -r '.name')
    sub_state=$(echo "$subscription_info" | jq -r '.state')
    
    if [[ "$sub_state" != "Enabled" ]]; then
        log_error "Subscription '$sub_name' is in state: $sub_state"
        return 1
    fi
    
    log_success "Subscription access validated: $sub_name"
    return 0
}

# Check required Azure CLI extensions
check_azure_extensions() {
    local required_extensions=("resource-graph")
    
    log_info "Checking required Azure CLI extensions..."
    
    for extension in "${required_extensions[@]}"; do
        if ! az extension show --name "$extension" &>/dev/null; then
            log_info "Installing extension: $extension"
            if az extension add --name "$extension" &>/dev/null; then
                log_success "Extension installed: $extension"
            else
                log_error "Failed to install extension: $extension"
                return 1
            fi
        else
            log_debug "Extension already installed: $extension"
        fi
    done
    
    return 0
}

# Validate resource group access
validate_resource_groups() {
    local subscription_id="$1"
    local resource_groups="$2"
    
    if [[ -z "$resource_groups" ]]; then
        log_debug "No specific resource groups specified - will audit all"
        return 0
    fi
    
    log_info "Validating resource group access..."
    
    IFS=',' read -ra RG_ARRAY <<< "$resource_groups"
    local invalid_rgs=()
    
    for rg in "${RG_ARRAY[@]}"; do
        rg=$(echo "$rg" | xargs)  # Trim whitespace
        
        if ! az group show --name "$rg" --subscription "$subscription_id" &>/dev/null; then
            invalid_rgs+=("$rg")
            log_warn "Resource group not found or not accessible: $rg"
        else
            log_debug "Resource group validated: $rg"
        fi
    done
    
    if [[ ${#invalid_rgs[@]} -gt 0 ]]; then
        log_error "Invalid resource groups found: ${invalid_rgs[*]}"
        log_info "Available resource groups:"
        az group list --subscription "$subscription_id" --query '[].name' -o table
        return 1
    fi
    
    log_success "All specified resource groups are accessible"
    return 0
}

# Get Azure locations
get_azure_locations() {
    log_debug "Retrieving Azure locations..."
    az account list-locations --query '[].name' -o tsv
}

# Execute Azure CLI command with retry logic
az_execute_with_retry() {
    local command="$1"
    local max_retries="${2:-3}"
    local retry_delay="${3:-5}"
    
    local attempt=1
    
    while [[ $attempt -le $max_retries ]]; do
        log_command "$command"
        
        if eval "$command"; then
            return 0
        else
            local exit_code=$?
            log_warn "Command failed (attempt $attempt/$max_retries): $command"
            
            if [[ $attempt -lt $max_retries ]]; then
                log_info "Retrying in ${retry_delay} seconds..."
                sleep "$retry_delay"
            fi
            
            ((attempt++))
        fi
    done
    
    log_error "Command failed after $max_retries attempts: $command"
    return 1
}

# Export functions for use in other scripts
export -f check_azure_cli version_compare check_azure_auth authenticate_azure
export -f set_subscription validate_subscription check_azure_extensions
export -f validate_resource_groups get_azure_locations az_execute_with_retry