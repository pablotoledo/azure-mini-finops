#!/bin/bash
# Azure Cleanup Manager
# Generates cleanup recommendations with safety features

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/../lib"

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/azure-helpers.sh"

SUBSCRIPTION_ID=""
INPUT_DIR=""
OUTPUT_FILE=""
REPORT_DATE=""
DRY_RUN="true"
ENABLE_SAFETY_TAGS="true"

parse_parameters() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --subscription)
                SUBSCRIPTION_ID="$2"
                shift 2
                ;;
            --input-dir)
                INPUT_DIR="$2"
                shift 2
                ;;
            --output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --report-date)
                REPORT_DATE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="$2"
                shift 2
                ;;
            --enable-safety-tags)
                ENABLE_SAFETY_TAGS="$2"
                shift 2
                ;;
        esac
    done
}

# Main cleanup management function
manage_cleanup() {
    log_script_start "Cleanup Manager"
    log_info "Generating cleanup recommendations for subscription: $SUBSCRIPTION_ID"
    log_info "Safety mode: $DRY_RUN"
    
    # Find input files
    find_input_files
    
    # Generate comprehensive cleanup recommendations
    generate_cleanup_recommendations
    
    # Apply safety tags if enabled
    if [[ "$ENABLE_SAFETY_TAGS" == "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
        apply_safety_tags
    fi
    
    # Generate cleanup scripts
    generate_cleanup_scripts
    
    # Create cleanup summary
    generate_cleanup_summary
    
    log_script_end "Cleanup Manager" 0
}

# Find and validate input files
find_input_files() {
    log_info "Looking for input files in: $INPUT_DIR"
    
    # Look for the audit files from this run
    local base_pattern="azure-audit-${REPORT_DATE}"
    
    INVENTORY_FILE=$(find "$INPUT_DIR" -name "${base_pattern}-inventory.csv" | head -1)
    ORPHAN_FILE=$(find "$INPUT_DIR" -name "${base_pattern}-orphans.csv" | head -1)
    COST_FILE=$(find "$INPUT_DIR" -name "${base_pattern}-costs.csv" | head -1)
    ACTIVITY_FILE=$(find "$INPUT_DIR" -name "${base_pattern}-activity.csv" | head -1)
    
    # Log which files were found
    [[ -f "$INVENTORY_FILE" ]] && log_info "Found inventory file: $(basename "$INVENTORY_FILE")" || log_warn "Inventory file not found"
    [[ -f "$ORPHAN_FILE" ]] && log_info "Found orphan file: $(basename "$ORPHAN_FILE")" || log_warn "Orphan file not found"
    [[ -f "$COST_FILE" ]] && log_info "Found cost file: $(basename "$COST_FILE")" || log_warn "Cost file not found"
    [[ -f "$ACTIVITY_FILE" ]] && log_info "Found activity file: $(basename "$ACTIVITY_FILE")" || log_warn "Activity file not found"
}

# Generate comprehensive cleanup recommendations
generate_cleanup_recommendations() {
    log_info "Generating cleanup recommendations..."
    
    # Initialize recommendations file
    {
        echo "Priority,ResourceName,ResourceType,ResourceGroup,Location,RecommendationType,EstimatedSavings,RiskLevel,SafetyChecks,CleanupAction,Tags"
    } > "$OUTPUT_FILE"
    
    # Process orphaned resources
    process_orphaned_resources
    
    # Process high-cost resources
    process_high_cost_resources
    
    # Process unused resources from inventory
    process_unused_resources
    
    # Process stopped VMs
    process_stopped_vms
    
    # Process old snapshots
    process_old_snapshots
    
    # Sort recommendations by priority and estimated savings
    sort_recommendations
    
    local rec_count
    rec_count=$(tail -n +2 "$OUTPUT_FILE" 2>/dev/null | wc -l || echo "0")
    log_success "Cleanup recommendations generated: $rec_count recommendations"
}

# Process orphaned resources
process_orphaned_resources() {
    if [[ ! -f "$ORPHAN_FILE" ]]; then
        log_debug "No orphan file available, skipping orphaned resource processing"
        return 0
    fi
    
    log_info "Processing orphaned resources..."
    
    tail -n +2 "$ORPHAN_FILE" | while IFS=',' read -r sub_id rg name type location orphan_type cost_impact details tags; do
        # Clean quoted fields
        name=$(echo "$name" | sed 's/^"//;s/"$//')
        type=$(echo "$type" | sed 's/^"//;s/"$//')
        rg=$(echo "$rg" | sed 's/^"//;s/"$//')
        location=$(echo "$location" | sed 's/^"//;s/"$//')
        orphan_type=$(echo "$orphan_type" | sed 's/^"//;s/"$//')
        cost_impact=$(echo "$cost_impact" | sed 's/^"//;s/"$//')
        details=$(echo "$details" | sed 's/^"//;s/"$//')
        tags=$(echo "$tags" | sed 's/^"//;s/"$//')
        
        # Determine priority based on cost impact
        local priority
        case "$cost_impact" in
            "High") priority="1" ;;
            "Medium") priority="2" ;;
            *) priority="3" ;;
        esac
        
        # Estimate savings
        local estimated_savings
        case "$cost_impact" in
            "High") estimated_savings="\$100-500/month" ;;
            "Medium") estimated_savings="\$25-100/month" ;;
            *) estimated_savings="\$5-25/month" ;;
        esac
        
        # Determine risk level
        local risk_level="Low"
        if [[ "$type" =~ virtualmachines|databases ]]; then
            risk_level="Medium"
        fi
        
        # Safety checks
        local safety_checks="Check dependencies;Verify not in use;Backup if needed"
        
        # Cleanup action
        local cleanup_action="Delete resource"
        if [[ "$type" =~ disk ]]; then
            cleanup_action="Create snapshot then delete"
        fi
        
        # Add to recommendations
        echo "$priority,\"$name\",\"$type\",\"$rg\",\"$location\",\"Orphaned Resource\",\"$estimated_savings\",\"$risk_level\",\"$safety_checks\",\"$cleanup_action\",\"$tags\"" >> "$OUTPUT_FILE"
        
    done
    
    log_debug "Orphaned resource processing completed"
}

# Process high-cost resources
process_high_cost_resources() {
    if [[ ! -f "$COST_FILE" ]]; then
        log_debug "No cost file available, skipping high-cost resource processing"
        return 0
    fi
    
    log_info "Processing high-cost resources..."
    
    # Look for cost breakdown file
    local cost_breakdown="${COST_FILE%.csv}-breakdown.csv"
    
    if [[ -f "$cost_breakdown" ]]; then
        tail -n +2 "$cost_breakdown" | while IFS=',' read -r resource_id total_cost resource_type location; do
            # Clean quoted fields
            resource_id=$(echo "$resource_id" | sed 's/^"//;s/"$//')
            total_cost=$(echo "$total_cost" | sed 's/^"//;s/"$//')
            resource_type=$(echo "$resource_type" | sed 's/^"//;s/"$//')
            location=$(echo "$location" | sed 's/^"//;s/"$//')
            
            # Extract resource name and resource group from resource ID
            local resource_name resource_group
            resource_name=$(echo "$resource_id" | awk -F'/' '{print $NF}')
            resource_group=$(echo "$resource_id" | grep -o '/resourceGroups/[^/]*' | cut -d'/' -f3 || echo "Unknown")
            
            # Check if cost is above threshold
            local cost_num
            cost_num=$(echo "$total_cost" | grep -o '[0-9.]*' | head -1)
            
            if (( $(echo "$cost_num > ${COST_THRESHOLD_HIGH:-500}" | bc -l 2>/dev/null || echo "0") )); then
                local priority="2"
                local estimated_savings="\$$(echo "$cost_num * 0.3" | bc -l | cut -d. -f1)/month"
                local risk_level="Medium"
                local safety_checks="Review utilization;Check business requirements;Validate with owner"
                local cleanup_action="Right-size or optimize configuration"
                
                echo "$priority,\"$resource_name\",\"$resource_type\",\"$resource_group\",\"$location\",\"High Cost Resource\",\"$estimated_savings\",\"$risk_level\",\"$safety_checks\",\"$cleanup_action\",\"\"" >> "$OUTPUT_FILE"
            fi
        done
    fi
    
    log_debug "High-cost resource processing completed"
}

# Process unused resources from inventory
process_unused_resources() {
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_debug "No inventory file available, skipping unused resource processing"
        return 0
    fi
    
    log_info "Processing potentially unused resources from inventory..."
    
    # Look for stopped/deallocated VMs
    tail -n +2 "$INVENTORY_FILE" | while IFS=',' read -r sub_name sub_id rg name type location power_state prov_state creation_time sku_name size tags; do
        # Clean quoted fields
        name=$(echo "$name" | sed 's/^"//;s/"$//')
        type=$(echo "$type" | sed 's/^"//;s/"$//')
        rg=$(echo "$rg" | sed 's/^"//;s/"$//')
        location=$(echo "$location" | sed 's/^"//;s/"$//')
        power_state=$(echo "$power_state" | sed 's/^"//;s/"$//')
        tags=$(echo "$tags" | sed 's/^"//;s/"$//')
        
        # Check for deallocated VMs
        if [[ "$type" =~ virtualmachines ]] && [[ "$power_state" =~ deallocated|stopped ]]; then
            local priority="2"
            local estimated_savings="\$50-300/month"
            local risk_level="High"
            local safety_checks="Confirm not needed;Check with owner;Backup VM state"
            local cleanup_action="Delete if confirmed unused"
            
            echo "$priority,\"$name\",\"$type\",\"$rg\",\"$location\",\"Stopped VM\",\"$estimated_savings\",\"$risk_level\",\"$safety_checks\",\"$cleanup_action\",\"$tags\"" >> "$OUTPUT_FILE"
        fi
        
        # Check for old resources that might be unused
        if [[ -n "$creation_time" ]] && [[ "$creation_time" != '""' ]]; then
            local creation_date
            creation_date=$(echo "$creation_time" | cut -dT -f1)
            
            if [[ -n "$creation_date" ]]; then
                local days_old
                days_old=$(( ($(date +%s) - $(date -d "$creation_date" +%s 2>/dev/null || echo "0")) / 86400 ))
                
                if (( days_old > 365 )); then
                    local priority="3"
                    local estimated_savings="\$10-50/month"
                    local risk_level="Low"
                    local safety_checks="Review usage logs;Check last access;Verify still needed"
                    local cleanup_action="Archive or delete if unused"
                    
                    echo "$priority,\"$name\",\"$type\",\"$rg\",\"$location\",\"Old Resource (>1 year)\",\"$estimated_savings\",\"$risk_level\",\"$safety_checks\",\"$cleanup_action\",\"$tags\"" >> "$OUTPUT_FILE"
                fi
            fi
        fi
    done
    
    log_debug "Unused resource processing completed"
}

# Process stopped VMs specifically
process_stopped_vms() {
    local stopped_vm_file="${ORPHAN_FILE%.csv}-stopped-vms.csv"
    
    if [[ ! -f "$stopped_vm_file" ]]; then
        log_debug "No stopped VM file available, skipping"
        return 0
    fi
    
    log_info "Processing stopped VMs..."
    
    tail -n +2 "$stopped_vm_file" | while IFS=',' read -r vm_name rg power_state location vm_size os stopped_since cost_impact; do
        # Clean quoted fields
        vm_name=$(echo "$vm_name" | sed 's/^"//;s/"$//')
        rg=$(echo "$rg" | sed 's/^"//;s/"$//')
        power_state=$(echo "$power_state" | sed 's/^"//;s/"$//')
        location=$(echo "$location" | sed 's/^"//;s/"$//')
        vm_size=$(echo "$vm_size" | sed 's/^"//;s/"$//')
        cost_impact=$(echo "$cost_impact" | sed 's/^"//;s/"$//')
        
        local priority
        case "$cost_impact" in
            "High") priority="1" ;;
            "Medium") priority="2" ;;
            *) priority="3" ;;
        esac
        
        local estimated_savings
        case "$cost_impact" in
            "High") estimated_savings="\$200-500/month" ;;
            "Medium") estimated_savings="\$50-200/month" ;;
            *) estimated_savings="\$10-50/month" ;;
        esac
        
        local safety_checks="Verify VM purpose;Check with business owner;Create VM image backup"
        local cleanup_action="Delete VM and associated resources"
        
        echo "$priority,\"$vm_name\",\"Microsoft.Compute/virtualMachines\",\"$rg\",\"$location\",\"Stopped VM\",\"$estimated_savings\",\"High\",\"$safety_checks\",\"$cleanup_action\",\"\"" >> "$OUTPUT_FILE"
    done
    
    log_debug "Stopped VM processing completed"
}

# Process old snapshots
process_old_snapshots() {
    local snapshot_file="${ORPHAN_FILE%.csv}-snapshots.csv"
    
    if [[ ! -f "$snapshot_file" ]]; then
        log_debug "No snapshot file available, skipping"
        return 0
    fi
    
    log_info "Processing old snapshots..."
    
    tail -n +2 "$snapshot_file" | while IFS=',' read -r sub_id rg name type location orphan_type cost_impact details tags; do
        # Clean quoted fields
        name=$(echo "$name" | sed 's/^"//;s/"$//')
        type=$(echo "$type" | sed 's/^"//;s/"$//')
        rg=$(echo "$rg" | sed 's/^"//;s/"$//')
        location=$(echo "$location" | sed 's/^"//;s/"$//')
        cost_impact=$(echo "$cost_impact" | sed 's/^"//;s/"$//')
        details=$(echo "$details" | sed 's/^"//;s/"$//')
        tags=$(echo "$tags" | sed 's/^"//;s/"$//')
        
        local priority="3"
        local estimated_savings="\$5-25/month"
        local risk_level="Low"
        local safety_checks="Verify snapshot purpose;Check retention requirements"
        local cleanup_action="Delete old snapshot"
        
        echo "$priority,\"$name\",\"$type\",\"$rg\",\"$location\",\"Old Snapshot\",\"$estimated_savings\",\"$risk_level\",\"$safety_checks\",\"$cleanup_action\",\"$tags\"" >> "$OUTPUT_FILE"
    done
    
    log_debug "Old snapshot processing completed"
}

# Sort recommendations by priority
sort_recommendations() {
    log_info "Sorting recommendations by priority and estimated savings..."
    
    local temp_file="${OUTPUT_FILE}.tmp"
    
    # Extract header
    head -1 "$OUTPUT_FILE" > "$temp_file"
    
    # Sort data rows by priority (ascending) then by estimated savings (descending)
    tail -n +2 "$OUTPUT_FILE" | sort -t',' -k1,1n -k7,7r >> "$temp_file"
    
    mv "$temp_file" "$OUTPUT_FILE"
    
    log_debug "Recommendations sorted"
}

# Apply safety tags to resources
apply_safety_tags() {
    log_info "Applying safety tags to recommended resources..."
    
    local tagged_count=0
    
    tail -n +2 "$OUTPUT_FILE" | while IFS=',' read -r priority name type rg location rec_type savings risk checks action tags; do
        # Clean quoted fields
        name=$(echo "$name" | sed 's/^"//;s/"$//')
        type=$(echo "$type" | sed 's/^"//;s/"$//')
        rg=$(echo "$rg" | sed 's/^"//;s/"$//')
        
        # Skip if high risk
        if [[ "$risk" =~ High ]]; then
            log_debug "Skipping high-risk resource for tagging: $name"
            continue
        fi
        
        # Apply safety tag
        if apply_safety_tag "$name" "$type" "$rg"; then
            ((tagged_count++))
        fi
    done
    
    log_info "Applied safety tags to $tagged_count resources"
}

# Apply safety tag to a specific resource
apply_safety_tag() {
    local resource_name="$1"
    local resource_type="$2"
    local resource_group="$3"
    
    log_debug "Applying safety tag to: $resource_name"
    
    # Determine Azure CLI command based on resource type
    local tag_command=""
    
    case "$resource_type" in
        *virtualmachines*)
            tag_command="az vm update --name \"$resource_name\" --resource-group \"$resource_group\" --set tags.audit-candidate=true tags.audit-date=$(date +%Y-%m-%d)"
            ;;
        *disks*)
            tag_command="az disk update --name \"$resource_name\" --resource-group \"$resource_group\" --set tags.audit-candidate=true tags.audit-date=$(date +%Y-%m-%d)"
            ;;
        *publicipaddresses*)
            tag_command="az network public-ip update --name \"$resource_name\" --resource-group \"$resource_group\" --set tags.audit-candidate=true tags.audit-date=$(date +%Y-%m-%d)"
            ;;
        *)
            # Generic resource tagging
            tag_command="az resource tag --name \"$resource_name\" --resource-group \"$resource_group\" --resource-type \"$resource_type\" --tags audit-candidate=true audit-date=$(date +%Y-%m-%d)"
            ;;
    esac
    
    if [[ -n "$tag_command" ]]; then
        if eval "$tag_command" &>/dev/null; then
            log_debug "Successfully tagged: $resource_name"
            return 0
        else
            log_warn "Failed to tag: $resource_name"
            return 1
        fi
    else
        log_warn "No tagging method for resource type: $resource_type"
        return 1
    fi
}

# Generate cleanup scripts
generate_cleanup_scripts() {
    log_info "Generating cleanup scripts..."
    
    local script_file="${OUTPUT_FILE%.csv}-cleanup-script.sh"
    
    cat > "$script_file" << 'EOF'
#!/bin/bash
# Auto-generated Azure Resource Cleanup Script
# IMPORTANT: Review carefully before execution!

set -euo pipefail

# Configuration
DRY_RUN="true"  # Set to "false" to execute actual deletions
REQUIRE_CONFIRMATION="true"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

confirm_action() {
    if [[ "$REQUIRE_CONFIRMATION" == "true" ]]; then
        echo -n "Proceed with this action? (y/N): "
        read -r response
        [[ "$response" =~ ^[Yy]$ ]]
    else
        return 0
    fi
}

EOF
    
    # Add individual cleanup commands
    local priority_1_count=0
    local priority_2_count=0
    local priority_3_count=0
    
    tail -n +2 "$OUTPUT_FILE" | while IFS=',' read -r priority name type rg location rec_type savings risk checks action tags; do
        # Clean quoted fields
        name=$(echo "$name" | sed 's/^"//;s/"$//')
        type=$(echo "$type" | sed 's/^"//;s/"$//')
        rg=$(echo "$rg" | sed 's/^"//;s/"$//')
        rec_type=$(echo "$rec_type" | sed 's/^"//;s/"$//')
        action=$(echo "$action" | sed 's/^"//;s/"$//')
        
        case "$priority" in
            1) ((priority_1_count++)) ;;
            2) ((priority_2_count++)) ;;
            3) ((priority_3_count++)) ;;
        esac
        
        cat >> "$script_file" << EOF

# Priority $priority: $rec_type - $name
cleanup_${name//[^a-zA-Z0-9]/_}() {
    log_info "Processing: $name ($rec_type)"
    log_warn "Action: $action"
    
    if confirm_action; then
        if [[ "\$DRY_RUN" == "true" ]]; then
            log_info "DRY RUN: Would execute cleanup for $name"
        else
            # Add actual Azure CLI delete command here
            # Example: az vm delete --name "$name" --resource-group "$rg" --yes
            log_warn "Actual deletion not implemented - add specific commands"
        fi
    else
        log_info "Skipped: $name"
    fi
}

EOF
    done
    
    # Add main execution section
    cat >> "$script_file" << EOF

# Main execution
main() {
    log_info "Azure Resource Cleanup Script"
    log_info "DRY RUN mode: \$DRY_RUN"
    
    if [[ "\$DRY_RUN" != "true" ]]; then
        log_warn "WARNING: This will perform actual deletions!"
        log_warn "Make sure you have backups and approvals!"
        echo -n "Continue with actual deletions? (type 'DELETE' to confirm): "
        read -r confirmation
        if [[ "\$confirmation" != "DELETE" ]]; then
            log_info "Aborted by user"
            exit 0
        fi
    fi
    
    # Execute cleanup functions (uncomment as needed)
    # Priority 1 items ($priority_1_count items)
    # cleanup_function_name
    
    # Priority 2 items ($priority_2_count items)
    # cleanup_function_name
    
    # Priority 3 items ($priority_3_count items)
    # cleanup_function_name
    
    log_info "Cleanup script completed"
}

# Uncomment the following line to execute the script
# main "\$@"

EOF
    
    chmod +x "$script_file"
    log_success "Cleanup script generated: $script_file"
}

# Generate cleanup summary
generate_cleanup_summary() {
    log_info "Generating cleanup summary..."
    
    local summary_file="${OUTPUT_FILE%.csv}-summary.txt"
    
    # Count recommendations by priority and type
    local total_recs priority_1 priority_2 priority_3
    local orphaned_count stopped_vm_count high_cost_count
    
    if [[ -f "$OUTPUT_FILE" ]]; then
        total_recs=$(tail -n +2 "$OUTPUT_FILE" | wc -l)
        priority_1=$(tail -n +2 "$OUTPUT_FILE" | grep "^1," | wc -l || echo "0")
        priority_2=$(tail -n +2 "$OUTPUT_FILE" | grep "^2," | wc -l || echo "0")
        priority_3=$(tail -n +2 "$OUTPUT_FILE" | grep "^3," | wc -l || echo "0")
        
        orphaned_count=$(tail -n +2 "$OUTPUT_FILE" | grep "Orphaned Resource" | wc -l || echo "0")
        stopped_vm_count=$(tail -n +2 "$OUTPUT_FILE" | grep "Stopped VM" | wc -l || echo "0")
        high_cost_count=$(tail -n +2 "$OUTPUT_FILE" | grep "High Cost Resource" | wc -l || echo "0")
    else
        total_recs=0
        priority_1=0
        priority_2=0
        priority_3=0
        orphaned_count=0
        stopped_vm_count=0
        high_cost_count=0
    fi
    
    cat > "$summary_file" << EOF
Azure Resource Cleanup Summary
==============================
Generated: $(date)
Subscription: $SUBSCRIPTION_ID

Cleanup Recommendations: $total_recs total
- Priority 1 (High Impact): $priority_1
- Priority 2 (Medium Impact): $priority_2  
- Priority 3 (Low Impact): $priority_3

Resource Categories:
- Orphaned Resources: $orphaned_count
- Stopped VMs: $stopped_vm_count
- High Cost Resources: $high_cost_count

Safety Features:
- Dry run mode: $DRY_RUN
- Safety tagging: $ENABLE_SAFETY_TAGS
- Risk assessment included
- Manual confirmation required

Top Priority Items:
EOF
    
    # Add top 5 priority items
    if [[ -f "$OUTPUT_FILE" ]]; then
        tail -n +2 "$OUTPUT_FILE" | head -5 | \
        cut -d',' -f2,6,7 | \
        awk -F',' '{ gsub(/"/, "", $1); gsub(/"/, "", $2); gsub(/"/, "", $3); print "- " $1 " (" $2 ", " $3 ")" }' >> "$summary_file"
    fi
    
    cat >> "$summary_file" << EOF

Next Steps:
1. Review all recommendations carefully
2. Validate with resource owners
3. Test cleanup in non-production environment
4. Execute high-priority items first
5. Monitor for any issues after cleanup

Safety Reminders:
- Always backup critical data first
- Test deletions in non-production
- Have rollback plan ready
- Verify resource dependencies
- Check compliance requirements

Files Generated:
- $(basename "$OUTPUT_FILE") - Detailed recommendations
- $(basename "${OUTPUT_FILE%.csv}-cleanup-script.sh") - Executable cleanup script
- $(basename "$summary_file") - This summary
EOF
    
    log_success "Cleanup summary saved to: $summary_file"
}

main() {
    parse_parameters "$@"
    [[ -z "$SUBSCRIPTION_ID" ]] && { log_error "Subscription ID required"; exit 1; }
    [[ -z "$INPUT_DIR" ]] && { log_error "Input directory required"; exit 1; }
    [[ -z "$OUTPUT_FILE" ]] && { log_error "Output file required"; exit 1; }
    [[ -z "$REPORT_DATE" ]] && { log_error "Report date required"; exit 1; }
    
    # Create output directory
    local output_dir
    output_dir=$(dirname "$OUTPUT_FILE")
    mkdir -p "$output_dir"
    
    manage_cleanup
}

main "$@"