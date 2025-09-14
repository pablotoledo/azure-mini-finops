#!/bin/bash
# Azure Orphaned Resource Detection Module
# Identifies unused resources for potential cleanup

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/../lib"

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/azure-helpers.sh"

SUBSCRIPTION_ID=""
OUTPUT_FILE=""

parse_parameters() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --subscription)
                SUBSCRIPTION_ID="$2"
                shift 2
                ;;
            --output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
        esac
    done
}

# Main orphan detection
detect_orphaned_resources() {
    log_script_start "Orphaned Resource Detection"
    log_info "Detecting orphaned resources in subscription: $SUBSCRIPTION_ID"
    
    # Combined query for multiple orphaned resource types
    local orphan_query='
    // Unattached managed disks
    Resources 
    | where type =~ "microsoft.compute/disks" 
    | where managedBy == "" or isnull(managedBy)
    | extend OrphanType = "Unattached Disk",
             CostImpact = case(
                 toint(properties.diskSizeGB) > 512, "High",
                 toint(properties.diskSizeGB) > 128, "Medium", 
                 "Low"
             ),
             Details = strcat("Size: ", tostring(properties.diskSizeGB), "GB, SKU: ", sku.name)
    | project SubscriptionId = subscriptionId, ResourceGroup = resourceGroup, Name = name, 
              Type = type, Location = location, OrphanType, CostImpact, Details, Tags = tags
    
    | union (
        // Orphaned Public IP Addresses (Standard SKU only cost money)
        Resources
        | where type =~ "microsoft.network/publicipaddresses"
        | where isnull(properties.ipConfiguration) or properties.ipConfiguration == ""
        | extend OrphanType = "Unassociated Public IP",
                 CostImpact = case(sku.name =~ "Standard", "Medium", "Low"),
                 Details = strcat("SKU: ", sku.name, ", Tier: ", sku.tier)
        | project SubscriptionId = subscriptionId, ResourceGroup = resourceGroup, Name = name,
                  Type = type, Location = location, OrphanType, CostImpact, Details, Tags = tags
    )
    
    | union (
        // Unused Network Security Groups
        Resources 
        | where type =~ "microsoft.network/networksecuritygroups" 
        | where isnull(properties.networkInterfaces) and isnull(properties.subnets)
        | extend OrphanType = "Unused NSG",
                 CostImpact = "Low",
                 Details = "No associated NICs or subnets"
        | project SubscriptionId = subscriptionId, ResourceGroup = resourceGroup, Name = name,
                  Type = type, Location = location, OrphanType, CostImpact, Details, Tags = tags
    )
    
    | union (
        // Orphaned Network Interfaces
        Resources 
        | where type =~ "microsoft.network/networkinterfaces" 
        | where isnull(properties.virtualMachine)
        | extend OrphanType = "Orphaned NIC",
                 CostImpact = "Low", 
                 Details = "Not attached to VM"
        | project SubscriptionId = subscriptionId, ResourceGroup = resourceGroup, Name = name,
                  Type = type, Location = location, OrphanType, CostImpact, Details, Tags = tags
    )
    
    | union (
        // Unused Load Balancers
        Resources
        | where type =~ "microsoft.network/loadbalancers"
        | where array_length(properties.backendAddressPools) == 0
        | extend OrphanType = "Unused Load Balancer",
                 CostImpact = "High",
                 Details = strcat("SKU: ", sku.name, ", No backend pools")
        | project SubscriptionId = subscriptionId, ResourceGroup = resourceGroup, Name = name,
                  Type = type, Location = location, OrphanType, CostImpact, Details, Tags = tags
    )
    
    | order by CostImpact desc, OrphanType asc, Name asc
    '
    
    log_info "Executing orphan detection query..."
    
    local temp_json="${OUTPUT_FILE%.csv}.json"
    
    if az graph query \
        -q "$orphan_query" \
        --subscriptions "$SUBSCRIPTION_ID" \
        --output json > "$temp_json"; then
        
        log_success "Orphan detection query completed"
        
        # Convert to CSV
        convert_orphan_data_to_csv "$temp_json" "$OUTPUT_FILE"
        
        # Detect empty resource groups
        detect_empty_resource_groups
        
        # Detect stopped VMs
        detect_stopped_vms
        
        # Detect unused storage accounts
        detect_unused_storage
        
        # Clean up
        rm -f "$temp_json"
        
        local count
        count=$(tail -n +2 "$OUTPUT_FILE" 2>/dev/null | wc -l || echo "0")
        log_success "Orphaned resource detection complete: $count resources found"
        log_info "Results saved to: $OUTPUT_FILE"
        
    else
        log_error "Orphan detection query failed"
        return 1
    fi
}

convert_orphan_data_to_csv() {
    local json_file="$1"
    local csv_file="$2"
    
    log_debug "Converting orphan data to CSV: $json_file -> $csv_file"
    
    # Check if we have data
    local record_count
    record_count=$(jq '. | length' "$json_file" 2>/dev/null || echo "0")
    
    if [[ "$record_count" -eq 0 ]]; then
        log_info "No orphaned resources found"
        # Create empty CSV with headers
        echo "SubscriptionId,ResourceGroup,Name,Type,Location,OrphanType,CostImpact,Details,Tags" > "$csv_file"
        return 0
    fi
    
    jq -r '
        ["SubscriptionId","ResourceGroup","Name","Type","Location","OrphanType","CostImpact","Details","Tags"] as $headers |
        $headers,
        (.[] | [
            .SubscriptionId // "",
            .ResourceGroup // "",
            .Name // "",
            .Type // "",
            .Location // "",
            .OrphanType // "",
            .CostImpact // "",
            .Details // "",
            (.Tags // {} | to_entries | map("\(.key)=\(.value)") | join(";"))
        ]) | @csv
    ' "$json_file" > "$csv_file"
    
    log_success "Orphan data conversion completed"
}

# Detect empty resource groups
detect_empty_resource_groups() {
    log_info "Detecting empty resource groups..."
    
    local empty_rg_file="${OUTPUT_FILE%.csv}-empty-rgs.csv"
    
    # Query for empty resource groups
    local empty_rg_query='
    ResourceContainers 
    | where type =~ "microsoft.resources/subscriptions/resourcegroups" 
    | extend rgAndSub = strcat(resourceGroup, "--", subscriptionId) 
    | join kind=leftouter (
        Resources 
        | extend rgAndSub = strcat(resourceGroup, "--", subscriptionId) 
        | summarize count() by rgAndSub
    ) on rgAndSub 
    | where isnull(count_) 
    | project SubscriptionId = subscriptionId, ResourceGroup = name, 
              Location = location, Tags = tags
    | order by ResourceGroup asc
    '
    
    local temp_json="${empty_rg_file%.csv}.json"
    
    if az graph query \
        -q "$empty_rg_query" \
        --subscriptions "$SUBSCRIPTION_ID" \
        --output json > "$temp_json"; then
        
        jq -r '
            ["SubscriptionId","ResourceGroup","Location","Tags"] as $headers |
            $headers,
            (.[] | [
                .SubscriptionId // "",
                .ResourceGroup // "",
                .Location // "",
                (.Tags // {} | to_entries | map("\(.key)=\(.value)") | join(";"))
            ]) | @csv
        ' "$temp_json" > "$empty_rg_file"
        
        rm -f "$temp_json"
        
        local empty_count
        empty_count=$(tail -n +2 "$empty_rg_file" 2>/dev/null | wc -l || echo "0")
        log_info "Empty resource groups found: $empty_count"
        
        if [[ $empty_count -gt 0 ]]; then
            log_info "Empty resource groups saved to: $empty_rg_file"
        fi
    else
        log_warn "Failed to detect empty resource groups"
    fi
}

# Detect stopped VMs that might be candidates for deletion
detect_stopped_vms() {
    log_info "Detecting stopped VMs..."
    
    local stopped_vm_file="${OUTPUT_FILE%.csv}-stopped-vms.csv"
    
    if az vm list --subscription "$SUBSCRIPTION_ID" --show-details --output json | \
    jq -r '
        ["VMName","ResourceGroup","PowerState","Location","VMSize","OS","StoppedSince","CostImpact"] as $headers |
        $headers,
        (.[] | 
         select(.powerState == "VM deallocated" or .powerState == "VM stopped") |
         [
            .name,
            .resourceGroup,
            .powerState,
            .location,
            .hardwareProfile.vmSize // "",
            .storageProfile.osDisk.osType // "",
            "Unknown",
            (if (.hardwareProfile.vmSize | contains("Standard_D")) then "High"
             elif (.hardwareProfile.vmSize | contains("Standard_B")) then "Medium"
             else "Low" end)
         ]) | @csv
    ' > "$stopped_vm_file"; then
        
        local stopped_count
        stopped_count=$(tail -n +2 "$stopped_vm_file" 2>/dev/null | wc -l || echo "0")
        log_info "Stopped VMs found: $stopped_count"
        
        if [[ $stopped_count -gt 0 ]]; then
            log_info "Stopped VMs saved to: $stopped_vm_file"
        fi
    else
        log_warn "Failed to detect stopped VMs"
    fi
}

# Detect potentially unused storage accounts
detect_unused_storage() {
    log_info "Detecting potentially unused storage accounts..."
    
    local unused_storage_file="${OUTPUT_FILE%.csv}-unused-storage.csv"
    
    # Get storage accounts and check for recent activity
    if az storage account list --subscription "$SUBSCRIPTION_ID" --output json | \
    jq -r '
        ["StorageAccount","ResourceGroup","Kind","AccessTier","Location","CreationTime","SuspiciousActivity"] as $headers |
        $headers,
        (.[] | [
            .name,
            .resourceGroup,
            .kind // "",
            .accessTier // "",
            .location,
            .creationTime // "",
            (if (.accessTier == "Archive") then "Archive tier - rarely accessed"
             elif (.kind == "BlobStorage" and (.accessTier // "") == "") then "No access tier set"
             else "Normal" end)
        ]) | @csv
    ' > "$unused_storage_file"; then
        
        local storage_count
        storage_count=$(tail -n +2 "$unused_storage_file" 2>/dev/null | wc -l || echo "0")
        log_info "Storage accounts analyzed: $storage_count"
        
        # Filter for potentially unused ones
        local suspicious_count
        suspicious_count=$(tail -n +2 "$unused_storage_file" | grep -v "Normal" | wc -l || echo "0")
        
        if [[ $suspicious_count -gt 0 ]]; then
            log_info "Potentially unused storage accounts: $suspicious_count"
            log_info "Storage analysis saved to: $unused_storage_file"
        fi
    else
        log_warn "Failed to analyze storage accounts"
    fi
}

# Detect orphaned snapshots
detect_orphaned_snapshots() {
    log_info "Detecting orphaned snapshots..."
    
    local snapshot_file="${OUTPUT_FILE%.csv}-snapshots.csv"
    
    # Query for snapshots without corresponding VMs
    local snapshot_query='
    Resources
    | where type =~ "microsoft.compute/snapshots"
    | extend 
        sourceResourceId = tostring(properties.creationData.sourceResourceId),
        diskSizeGB = toint(properties.diskSizeGB),
        ageInDays = datetime_diff("day", now(), todatetime(properties.timeCreated))
    | join kind=leftouter (
        Resources
        | where type =~ "microsoft.compute/disks" or type =~ "microsoft.compute/virtualmachines"
        | project id, name
    ) on $left.sourceResourceId == $right.id
    | where isnull(id1)  // No corresponding disk/VM found
    | project 
        SubscriptionId = subscriptionId,
        ResourceGroup = resourceGroup,
        Name = name,
        Type = type,
        Location = location,
        OrphanType = "Orphaned Snapshot",
        CostImpact = case(diskSizeGB > 100, "Medium", "Low"),
        Details = strcat("Size: ", tostring(diskSizeGB), "GB, Age: ", tostring(ageInDays), " days"),
        Tags = tags
    | order by diskSizeGB desc
    '
    
    local temp_json="${snapshot_file%.csv}.json"
    
    if az graph query \
        -q "$snapshot_query" \
        --subscriptions "$SUBSCRIPTION_ID" \
        --output json > "$temp_json"; then
        
        jq -r '
            ["SubscriptionId","ResourceGroup","Name","Type","Location","OrphanType","CostImpact","Details","Tags"] as $headers |
            $headers,
            (.[] | [
                .SubscriptionId // "",
                .ResourceGroup // "",
                .Name // "",
                .Type // "",
                .Location // "",
                .OrphanType // "",
                .CostImpact // "",
                .Details // "",
                (.Tags // {} | to_entries | map("\(.key)=\(.value)") | join(";"))
            ]) | @csv
        ' "$temp_json" > "$snapshot_file"
        
        rm -f "$temp_json"
        
        local snapshot_count
        snapshot_count=$(tail -n +2 "$snapshot_file" 2>/dev/null | wc -l || echo "0")
        log_info "Orphaned snapshots found: $snapshot_count"
        
        if [[ $snapshot_count -gt 0 ]]; then
            log_info "Orphaned snapshots saved to: $snapshot_file"
        fi
    else
        log_warn "Failed to detect orphaned snapshots"
    fi
}

# Generate orphan summary report
generate_orphan_summary() {
    log_info "Generating orphan detection summary..."
    
    local summary_file="${OUTPUT_FILE%.csv}-summary.txt"
    
    cat > "$summary_file" << EOF
Orphaned Resource Detection Summary
===================================
Generated: $(date)
Subscription: $SUBSCRIPTION_ID

Report Files:
EOF
    
    # Count resources in each category
    local main_count empty_rg_count stopped_vm_count storage_count snapshot_count
    
    main_count=$(tail -n +2 "$OUTPUT_FILE" 2>/dev/null | wc -l || echo "0")
    empty_rg_count=$(tail -n +2 "${OUTPUT_FILE%.csv}-empty-rgs.csv" 2>/dev/null | wc -l || echo "0")
    stopped_vm_count=$(tail -n +2 "${OUTPUT_FILE%.csv}-stopped-vms.csv" 2>/dev/null | wc -l || echo "0")
    storage_count=$(tail -n +2 "${OUTPUT_FILE%.csv}-unused-storage.csv" 2>/dev/null | wc -l || echo "0")
    snapshot_count=$(tail -n +2 "${OUTPUT_FILE%.csv}-snapshots.csv" 2>/dev/null | wc -l || echo "0")
    
    cat >> "$summary_file" << EOF
- Orphaned Resources: $main_count
- Empty Resource Groups: $empty_rg_count  
- Stopped VMs: $stopped_vm_count
- Storage Accounts Analyzed: $storage_count
- Orphaned Snapshots: $snapshot_count

High Priority Items:
EOF
    
    # Extract high-impact items
    if [[ -f "$OUTPUT_FILE" ]]; then
        tail -n +2 "$OUTPUT_FILE" | grep "High" | cut -d',' -f3,6,7 | head -5 | \
        awk -F',' '{ print "- " $1 " (" $2 ", " $3 ")" }' >> "$summary_file"
    fi
    
    cat >> "$summary_file" << EOF

Recommendations:
1. Review high-impact orphaned resources first
2. Verify stopped VMs are not needed before deletion
3. Check empty resource groups for hidden dependencies
4. Test storage account access before cleanup
5. Use safety tags before deletion operations
EOF
    
    log_success "Orphan summary saved to: $summary_file"
}

main() {
    parse_parameters "$@"
    [[ -z "$SUBSCRIPTION_ID" ]] && { log_error "Subscription ID required"; exit 1; }
    [[ -z "$OUTPUT_FILE" ]] && { log_error "Output file required"; exit 1; }
    
    # Create output directory
    local output_dir
    output_dir=$(dirname "$OUTPUT_FILE")
    mkdir -p "$output_dir"
    
    detect_orphaned_resources
    detect_orphaned_snapshots
    generate_orphan_summary
    
    log_script_end "Orphaned Resource Detection" 0
}

main "$@"