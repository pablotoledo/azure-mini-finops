#!/bin/bash
# Azure Resource Inventory Collector
# Comprehensive resource listing with usage status detection

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/../lib"

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/azure-helpers.sh"
source "${LIB_DIR}/csv-export.sh"

# Configuration
SUBSCRIPTION_ID=""
RESOURCE_GROUPS=""
OUTPUT_FILE=""
PARALLEL_JOBS=5

# Parameter parsing
parse_parameters() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --subscription)
                SUBSCRIPTION_ID="$2"
                shift 2
                ;;
            --resource-groups)
                RESOURCE_GROUPS="$2"
                shift 2
                ;;
            --output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --parallel-jobs)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
        esac
    done
}

# Main inventory collection
collect_inventory() {
    log_script_start "Resource Inventory Collection"
    
    # Build Resource Graph query
    local query='
    Resources
    | join kind=leftouter (
        ResourceContainers 
        | where type == "microsoft.resources/subscriptions" 
        | project subscriptionName = name, subscriptionId
    ) on subscriptionId
    | extend 
        resourceType = type,
        creationTime = case(
            isnotempty(properties.timeCreated), tostring(properties.timeCreated),
            isnotempty(properties.creationDate), tostring(properties.creationDate),
            ""
        ),
        powerState = case(
            type =~ "microsoft.compute/virtualmachines" and isnotempty(properties.extended.instanceView.powerState.code),
            tostring(properties.extended.instanceView.powerState.code),
            type =~ "microsoft.compute/virtualmachines",
            "Unknown",
            type =~ "microsoft.web/sites" and isnotempty(properties.state),
            tostring(properties.state),
            ""
        ),
        skuName = case(
            isnotempty(sku.name), tostring(sku.name),
            isnotempty(properties.sku.name), tostring(properties.sku.name),
            ""
        ),
        provisioningState = tostring(properties.provisioningState),
        size = case(
            type =~ "microsoft.compute/virtualmachines" and isnotempty(properties.hardwareProfile.vmSize),
            tostring(properties.hardwareProfile.vmSize),
            type =~ "microsoft.compute/disks" and isnotempty(properties.diskSizeGB),
            strcat(tostring(properties.diskSizeGB), " GB"),
            type =~ "microsoft.storage/storageaccounts" and isnotempty(properties.primaryEndpoints),
            "Storage Account",
            ""
        )
    | project 
        SubscriptionName = subscriptionName,
        SubscriptionId = subscriptionId,
        ResourceGroup = resourceGroup,
        Name = name,
        Type = resourceType,
        Location = location,
        PowerState = powerState,
        ProvisioningState = provisioningState,
        CreationTime = creationTime,
        SkuName = skuName,
        Size = size,
        Tags = tags
    | order by SubscriptionName asc, ResourceGroup asc, Name asc
    '
    
    # Add resource group filter if specified
    if [[ -n "$RESOURCE_GROUPS" ]]; then
        IFS=',' read -ra RG_ARRAY <<< "$RESOURCE_GROUPS"
        local rg_filter=""
        for rg in "${RG_ARRAY[@]}"; do
            rg=$(echo "$rg" | xargs)  # Trim whitespace
            if [[ -n "$rg_filter" ]]; then
                rg_filter+=","
            fi
            rg_filter+="\"$rg\""
        done
        
        # Insert the filter into the query
        query=$(echo "$query" | sed "/| project SubscriptionName/i\\
        | where resourceGroup in ($rg_filter)")
    fi
    
    # Execute query and export to CSV
    log_info "Executing Resource Graph query for inventory..."
    
    local temp_json="${OUTPUT_FILE%.csv}.json"
    
    if az graph query \
        --query "$query" \
        --subscriptions "$SUBSCRIPTION_ID" \
        --output json > "$temp_json"; then
        
        log_success "Resource Graph query completed"
        
        # Convert to CSV format
        log_info "Converting inventory data to CSV format..."
        convert_json_to_csv "$temp_json" "$OUTPUT_FILE"
        
        # Get additional status information for VMs
        log_info "Collecting additional VM status information..."
        collect_vm_status
        
        # Clean up temporary files
        rm -f "$temp_json"
        
        local resource_count
        resource_count=$(tail -n +2 "$OUTPUT_FILE" 2>/dev/null | wc -l || echo "0")
        log_success "Resource inventory saved to: $OUTPUT_FILE"
        log_info "Total resources found: $resource_count"
    else
        log_error "Resource Graph query failed"
        return 1
    fi
}

# VM status collection
collect_vm_status() {
    local vm_status_file="${OUTPUT_FILE%.csv}-vm-status.csv"
    
    log_debug "Collecting detailed VM status information..."
    
    local vm_query=""
    if [[ -n "$RESOURCE_GROUPS" ]]; then
        IFS=',' read -ra RG_ARRAY <<< "$RESOURCE_GROUPS"
        for rg in "${RG_ARRAY[@]}"; do
            rg=$(echo "$rg" | xargs)  # Trim whitespace
            vm_query+=" --resource-group \"$rg\""
        done
    fi
    
    local vm_cmd="az vm list --subscription \"$SUBSCRIPTION_ID\" $vm_query --show-details --output json"
    
    if eval "$vm_cmd" | \
    jq -r '
        ["VMName","ResourceGroup","PowerState","ProvisioningState","Location","VmSize","OS","PrivateIPs","PublicIPs","AdminUsername"] as $headers |
        $headers,
        (.[] | [
            .name,
            .resourceGroup,
            .powerState // "",
            .provisioningState // "",
            .location,
            .hardwareProfile.vmSize // "",
            .storageProfile.osDisk.osType // "",
            (.privateIps // [] | join(";")),
            (.publicIps // [] | join(";")),
            .osProfile.adminUsername // ""
        ]) |
        @csv
    ' > "$vm_status_file"; then
        
        local vm_count
        vm_count=$(tail -n +2 "$vm_status_file" 2>/dev/null | wc -l || echo "0")
        log_info "VM status details saved to: $vm_status_file ($vm_count VMs)"
    else
        log_warn "Failed to collect VM status details"
    fi
}

# JSON to CSV conversion
convert_json_to_csv() {
    local json_file="$1"
    local csv_file="$2"
    
    log_debug "Converting JSON to CSV: $json_file -> $csv_file"
    
    # Check if JSON file has data
    local record_count
    record_count=$(jq '. | length' "$json_file" 2>/dev/null || echo "0")
    
    if [[ "$record_count" -eq 0 ]]; then
        log_warn "No resources found in query results"
        # Create empty CSV with headers
        echo "SubscriptionName,SubscriptionId,ResourceGroup,Name,Type,Location,PowerState,ProvisioningState,CreationTime,SkuName,Size,Tags" > "$csv_file"
        return 0
    fi
    
    jq -r '
        (["SubscriptionName","SubscriptionId","ResourceGroup","Name","Type","Location","PowerState","ProvisioningState","CreationTime","SkuName","Size","Tags"]), 
        (.[] | [
            .SubscriptionName // "",
            .SubscriptionId // "",
            .ResourceGroup // "",
            .Name // "",
            .Type // "",
            .Location // "",
            .PowerState // "",
            .ProvisioningState // "",
            .CreationTime // "",
            .SkuName // "",
            .Size // "",
            (.Tags // {} | to_entries | map("\(.key)=\(.value)") | join(";"))
        ] | @csv)
    ' "$json_file" > "$csv_file"
    
    if validate_csv "$csv_file"; then
        log_success "JSON to CSV conversion completed"
    else
        log_error "CSV validation failed"
        return 1
    fi
}

# Collect additional resource details
collect_additional_details() {
    log_info "Collecting additional resource details..."
    
    # Storage account details
    collect_storage_details
    
    # Network details
    collect_network_details
    
    # Database details
    collect_database_details
}

# Storage account details
collect_storage_details() {
    local storage_file="${OUTPUT_FILE%.csv}-storage-details.csv"
    
    log_debug "Collecting storage account details..."
    
    local storage_cmd="az storage account list --subscription \"$SUBSCRIPTION_ID\" --output json"
    
    if eval "$storage_cmd" | \
    jq -r '
        ["StorageAccount","ResourceGroup","Kind","SkuName","SkuTier","AccessTier","Location","CreationTime","PrimaryLocation","SecondaryLocation"] as $headers |
        $headers,
        (.[] | [
            .name,
            .resourceGroup,
            .kind // "",
            .sku.name // "",
            .sku.tier // "",
            .accessTier // "",
            .location,
            .creationTime // "",
            .primaryLocation // "",
            .secondaryLocation // ""
        ]) |
        @csv
    ' > "$storage_file"; then
        
        local storage_count
        storage_count=$(tail -n +2 "$storage_file" 2>/dev/null | wc -l || echo "0")
        log_info "Storage account details saved: $storage_count accounts"
    else
        log_warn "Failed to collect storage account details"
    fi
}

# Network details
collect_network_details() {
    local network_file="${OUTPUT_FILE%.csv}-network-details.csv"
    
    log_debug "Collecting network resource details..."
    
    # Collect VNets, subnets, NSGs, etc.
    local network_cmd="az network vnet list --subscription \"$SUBSCRIPTION_ID\" --output json"
    
    if eval "$network_cmd" | \
    jq -r '
        ["VNetName","ResourceGroup","Location","AddressSpace","SubnetCount","DnsServers"] as $headers |
        $headers,
        (.[] | [
            .name,
            .resourceGroup,
            .location,
            (.addressSpace.addressPrefixes // [] | join(";")),
            (.subnets // [] | length),
            (.dhcpOptions.dnsServers // [] | join(";"))
        ]) |
        @csv
    ' > "$network_file"; then
        
        local vnet_count
        vnet_count=$(tail -n +2 "$network_file" 2>/dev/null | wc -l || echo "0")
        log_info "Network details saved: $vnet_count VNets"
    else
        log_warn "Failed to collect network details"
    fi
}

# Database details
collect_database_details() {
    local db_file="${OUTPUT_FILE%.csv}-database-details.csv"
    
    log_debug "Collecting database details..."
    
    # SQL databases
    local sql_cmd="az sql db list --subscription \"$SUBSCRIPTION_ID\" --output json 2>/dev/null || echo '[]'"
    
    if eval "$sql_cmd" | \
    jq -r '
        ["DatabaseName","ServerName","ResourceGroup","Edition","ServiceObjective","MaxSizeBytes","Status","CreationDate"] as $headers |
        $headers,
        (.[] | [
            .name,
            .serverName // "",
            .resourceGroup,
            .edition // "",
            .currentServiceObjectiveName // "",
            .maxSizeBytes // "",
            .status // "",
            .creationDate // ""
        ]) |
        @csv
    ' > "$db_file"; then
        
        local db_count
        db_count=$(tail -n +2 "$db_file" 2>/dev/null | wc -l || echo "0")
        log_info "Database details saved: $db_count databases"
    else
        log_warn "Failed to collect database details"
    fi
}

# Main execution
main() {
    parse_parameters "$@"
    validate_required_params
    collect_inventory
    collect_additional_details
    log_script_end "Resource Inventory Collection" 0
}

validate_required_params() {
    [[ -z "$SUBSCRIPTION_ID" ]] && { log_error "Subscription ID required"; exit 1; }
    [[ -z "$OUTPUT_FILE" ]] && { log_error "Output file required"; exit 1; }
    
    # Validate output directory
    local output_dir
    output_dir=$(dirname "$OUTPUT_FILE")
    mkdir -p "$output_dir"
}

main "$@"