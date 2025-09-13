#!/bin/bash
# Input Validation Functions
# Utilities for parameter validation and safety checks

# Source logging if available
if [[ -f "${LIB_DIR:-./}/logging.sh" ]]; then
    source "${LIB_DIR:-./}/logging.sh"
fi

# Validate Azure subscription ID format
validate_subscription_id() {
    local subscription_id="$1"
    
    if [[ -z "$subscription_id" ]]; then
        log_error "Subscription ID cannot be empty"
        return 1
    fi
    
    # Check for GUID format (8-4-4-4-12 characters)
    if [[ "$subscription_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        log_debug "Valid GUID format subscription ID: $subscription_id"
        return 0
    fi
    
    # Allow subscription names (non-GUID format)
    if [[ "$subscription_id" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
        log_debug "Subscription name format detected: $subscription_id"
        return 0
    fi
    
    log_error "Invalid subscription ID format: $subscription_id"
    log_error "Expected: GUID format (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx) or subscription name"
    return 1
}

# Validate resource group names
validate_resource_group_names() {
    local resource_groups="$1"
    
    if [[ -z "$resource_groups" ]]; then
        log_debug "No resource groups specified - will audit all"
        return 0
    fi
    
    IFS=',' read -ra RG_ARRAY <<< "$resource_groups"
    local invalid_rgs=()
    
    for rg in "${RG_ARRAY[@]}"; do
        rg=$(echo "$rg" | xargs)  # Trim whitespace
        
        # Azure resource group naming rules:
        # - 1-90 characters
        # - Alphanumeric, underscore, parentheses, hyphen, period (except at end)
        # - Can't end with period
        if [[ -z "$rg" ]]; then
            invalid_rgs+=("(empty)")
            continue
        fi
        
        if [[ ${#rg} -gt 90 ]]; then
            invalid_rgs+=("$rg (too long)")
            continue
        fi
        
        if [[ "$rg" =~ \.$ ]]; then
            invalid_rgs+=("$rg (ends with period)")
            continue
        fi
        
        if [[ ! "$rg" =~ ^[a-zA-Z0-9._()[-]+$ ]]; then
            invalid_rgs+=("$rg (invalid characters)")
            continue
        fi
        
        log_debug "Valid resource group name: $rg"
    done
    
    if [[ ${#invalid_rgs[@]} -gt 0 ]]; then
        log_error "Invalid resource group names found:"
        for invalid_rg in "${invalid_rgs[@]}"; do
            log_error "  - $invalid_rg"
        done
        return 1
    fi
    
    log_debug "All resource group names are valid"
    return 0
}

# Validate file path and permissions
validate_output_path() {
    local output_path="$1"
    local check_write="${2:-true}"
    
    if [[ -z "$output_path" ]]; then
        log_error "Output path cannot be empty"
        return 1
    fi
    
    # Get directory path
    local dir_path
    dir_path=$(dirname "$output_path")
    
    # Check if directory exists or can be created
    if [[ ! -d "$dir_path" ]]; then
        log_debug "Creating output directory: $dir_path"
        if ! mkdir -p "$dir_path" 2>/dev/null; then
            log_error "Cannot create output directory: $dir_path"
            return 1
        fi
    fi
    
    # Check write permissions if requested
    if [[ "$check_write" == "true" ]]; then
        if [[ ! -w "$dir_path" ]]; then
            log_error "No write permission for directory: $dir_path"
            return 1
        fi
        
        # Test file creation
        local test_file="${output_path}.test.$$"
        if ! touch "$test_file" 2>/dev/null; then
            log_error "Cannot create files in directory: $dir_path"
            return 1
        fi
        rm -f "$test_file"
    fi
    
    log_debug "Output path validated: $output_path"
    return 0
}

# Validate output format
validate_output_format() {
    local format="$1"
    local valid_formats=("csv" "json" "tsv")
    
    if [[ -z "$format" ]]; then
        log_error "Output format cannot be empty"
        return 1
    fi
    
    format=$(echo "$format" | tr '[:upper:]' '[:lower:]')
    
    for valid_format in "${valid_formats[@]}"; do
        if [[ "$format" == "$valid_format" ]]; then
            log_debug "Valid output format: $format"
            return 0
        fi
    done
    
    log_error "Invalid output format: $format"
    log_error "Valid formats: ${valid_formats[*]}"
    return 1
}

# Validate parallel jobs count
validate_parallel_jobs() {
    local jobs="$1"
    
    if [[ -z "$jobs" ]]; then
        log_error "Parallel jobs count cannot be empty"
        return 1
    fi
    
    # Check if it's a positive integer
    if ! [[ "$jobs" =~ ^[1-9][0-9]*$ ]]; then
        log_error "Parallel jobs must be a positive integer: $jobs"
        return 1
    fi
    
    # Check reasonable limits (1-50)
    if [[ $jobs -lt 1 || $jobs -gt 50 ]]; then
        log_error "Parallel jobs count should be between 1 and 50: $jobs"
        return 1
    fi
    
    log_debug "Valid parallel jobs count: $jobs"
    return 0
}

# Validate date format (ISO 8601)
validate_date_format() {
    local date_string="$1"
    local param_name="${2:-date}"
    
    if [[ -z "$date_string" ]]; then
        log_debug "No $param_name specified"
        return 0
    fi
    
    # Check ISO 8601 date format (YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS)
    if [[ "$date_string" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2}:[0-9]{2}:[0-9]{2}(Z|[+-][0-9]{2}:[0-9]{2})?)?$ ]]; then
        # Validate actual date using date command
        if date -d "$date_string" &>/dev/null; then
            log_debug "Valid $param_name format: $date_string"
            return 0
        fi
    fi
    
    log_error "Invalid $param_name format: $date_string"
    log_error "Expected ISO 8601 format: YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS"
    return 1
}

# Validate time period for cost analysis
validate_time_period() {
    local time_period="$1"
    local valid_periods=("MonthToDate" "BillingMonthToDate" "TheLastMonth" "TheLastBillingMonth" "Custom")
    
    if [[ -z "$time_period" ]]; then
        log_error "Time period cannot be empty"
        return 1
    fi
    
    for valid_period in "${valid_periods[@]}"; do
        if [[ "$time_period" == "$valid_period" ]]; then
            log_debug "Valid time period: $time_period"
            return 0
        fi
    done
    
    log_error "Invalid time period: $time_period"
    log_error "Valid periods: ${valid_periods[*]}"
    return 1
}

# Validate boolean parameter
validate_boolean() {
    local value="$1"
    local param_name="${2:-parameter}"
    
    if [[ -z "$value" ]]; then
        log_error "$param_name cannot be empty"
        return 1
    fi
    
    case "${value,,}" in
        true|false|yes|no|1|0|on|off)
            log_debug "Valid boolean $param_name: $value"
            return 0
            ;;
        *)
            log_error "Invalid boolean $param_name: $value"
            log_error "Valid values: true, false, yes, no, 1, 0, on, off"
            return 1
            ;;
    esac
}

# Convert boolean string to standardized form
normalize_boolean() {
    local value="$1"
    
    case "${value,,}" in
        true|yes|1|on)
            echo "true"
            ;;
        false|no|0|off)
            echo "false"
            ;;
        *)
            echo "$value"  # Return original if not recognized
            ;;
    esac
}

# Validate configuration file
validate_config_file() {
    local config_file="$1"
    
    if [[ -z "$config_file" ]]; then
        log_debug "No config file specified"
        return 0
    fi
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    if [[ ! -r "$config_file" ]]; then
        log_error "Cannot read configuration file: $config_file"
        return 1
    fi
    
    # Basic syntax validation for shell environment files
    if ! bash -n "$config_file" 2>/dev/null; then
        log_error "Configuration file has syntax errors: $config_file"
        return 1
    fi
    
    log_debug "Configuration file validated: $config_file"
    return 0
}

# Validate required commands are available
validate_required_commands() {
    local -a required_commands=("$@")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Required commands not found:"
        for cmd in "${missing_commands[@]}"; do
            log_error "  - $cmd"
        done
        return 1
    fi
    
    log_debug "All required commands are available"
    return 0
}

# Comprehensive parameter validation for main script
validate_main_parameters() {
    local subscription_id="$1"
    local resource_groups="$2"
    local output_dir="$3"
    local output_format="$4"
    local parallel_jobs="$5"
    local config_file="$6"
    
    local validation_errors=0
    
    # Validate required parameters
    if ! validate_subscription_id "$subscription_id"; then
        ((validation_errors++))
    fi
    
    if ! validate_resource_group_names "$resource_groups"; then
        ((validation_errors++))
    fi
    
    if ! validate_output_path "$output_dir"; then
        ((validation_errors++))
    fi
    
    if ! validate_output_format "$output_format"; then
        ((validation_errors++))
    fi
    
    if ! validate_parallel_jobs "$parallel_jobs"; then
        ((validation_errors++))
    fi
    
    if ! validate_config_file "$config_file"; then
        ((validation_errors++))
    fi
    
    # Check required commands
    if ! validate_required_commands "az" "jq"; then
        ((validation_errors++))
    fi
    
    if [[ $validation_errors -gt 0 ]]; then
        log_error "Parameter validation failed with $validation_errors error(s)"
        return 1
    fi
    
    log_success "All parameters validated successfully"
    return 0
}

# Export functions for use in other scripts
export -f validate_subscription_id validate_resource_group_names validate_output_path
export -f validate_output_format validate_parallel_jobs validate_date_format
export -f validate_time_period validate_boolean normalize_boolean validate_config_file
export -f validate_required_commands validate_main_parameters