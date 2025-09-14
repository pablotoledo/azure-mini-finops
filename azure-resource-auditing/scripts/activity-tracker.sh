#!/bin/bash
# Azure Activity Log Analysis Module
# Resource creator identification and change tracking

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/../lib"

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/azure-helpers.sh"

SUBSCRIPTION_ID=""
OUTPUT_FILE=""
DAYS_BACK=30

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
            --days-back)
                DAYS_BACK="$2"
                shift 2
                ;;
        esac
    done
}

# Main activity tracking function
track_activity() {
    log_script_start "Activity Log Analysis"
    log_info "Analyzing activity logs for subscription: $SUBSCRIPTION_ID"
    log_info "Looking back $DAYS_BACK days"
    
    # Calculate start date
    local start_date
    start_date=$(date -d "$DAYS_BACK days ago" +%Y-%m-%d)
    local end_date
    end_date=$(date +%Y-%m-%d)
    
    log_info "Analysis period: $start_date to $end_date"
    
    # Get activity log data
    collect_activity_logs "$start_date" "$end_date"
    
    # Analyze resource creation patterns
    analyze_resource_creation
    
    # Analyze resource modifications
    analyze_resource_modifications
    
    # Analyze deletion activities
    analyze_deletion_activities
    
    # Generate creator summary
    generate_creator_summary
    
    # Generate activity summary
    generate_activity_summary
    
    log_script_end "Activity Log Analysis" 0
}

# Collect activity logs
collect_activity_logs() {
    local start_date="$1"
    local end_date="$2"
    
    log_info "Collecting activity logs from $start_date to $end_date..."
    
    local temp_activity="${OUTPUT_FILE%.csv}-raw-activity.json"
    
    # Get activity logs for resource creation and modification
    if az monitor activity-log list \
        --subscription "$SUBSCRIPTION_ID" \
        --start-time "${start_date}T00:00:00Z" \
        --end-time "${end_date}T23:59:59Z" \
        --status "Succeeded" \
        --output json > "$temp_activity"; then
        
        log_success "Activity log collection completed"
        
        # Process and convert to CSV
        process_activity_logs "$temp_activity" "$OUTPUT_FILE"
        
        # Clean up
        rm -f "$temp_activity"
        
    else
        log_error "Failed to collect activity logs"
        log_warn "This might be due to permissions or data retention limits"
        
        # Create fallback activity analysis
        create_fallback_activity_data
    fi
}

# Process activity logs and convert to CSV
process_activity_logs() {
    local json_file="$1"
    local csv_file="$2"
    
    log_info "Processing activity log data..."
    
    # Check if we have data
    local record_count
    record_count=$(jq '. | length' "$json_file" 2>/dev/null || echo "0")
    
    if [[ "$record_count" -eq 0 ]]; then
        log_warn "No activity log data found"
        create_empty_activity_csv "$csv_file"
        return 0
    fi
    
    log_info "Processing $record_count activity log entries..."
    
    # Convert activity logs to structured CSV
    jq -r '
        ["EventTime","Operation","Status","Caller","ResourceType","ResourceName","ResourceGroup","SubscriptionId","Level"] as $headers |
        $headers,
        (.[] | 
         select(.operationName.value != null and .caller != null) |
         [
            .eventTimestamp,
            .operationName.value,
            .status.value // "",
            .caller // "",
            (.resourceType.value // ""),
            (.resourceId | split("/")[-1] // ""),
            (.resourceGroupName // ""),
            .subscriptionId,
            .level
         ]) | @csv
    ' "$json_file" > "$csv_file"
    
    local processed_count
    processed_count=$(tail -n +2 "$csv_file" 2>/dev/null | wc -l || echo "0")
    log_success "Activity log processing completed: $processed_count events processed"
}

# Create empty activity CSV when no data is available
create_empty_activity_csv() {
    local csv_file="$1"
    
    echo "EventTime,Operation,Status,Caller,ResourceType,ResourceName,ResourceGroup,SubscriptionId,Level" > "$csv_file"
    log_info "Created empty activity log CSV due to no data"
}

# Create fallback activity data using resource metadata
create_fallback_activity_data() {
    log_info "Creating fallback activity analysis using resource metadata..."
    
    local fallback_file="${OUTPUT_FILE%.csv}-fallback.csv"
    
    # Use Resource Graph to get creation information where available
    local creation_query='
    Resources
    | extend 
        creationTime = case(
            isnotempty(properties.timeCreated), tostring(properties.timeCreated),
            isnotempty(properties.creationDate), tostring(properties.creationDate),
            isnotempty(properties.createdTime), tostring(properties.createdTime),
            ""
        ),
        createdBy = case(
            isnotempty(tags["created-by"]), tostring(tags["created-by"]),
            isnotempty(tags["CreatedBy"]), tostring(tags["CreatedBy"]),
            isnotempty(tags["owner"]), tostring(tags["owner"]),
            "Unknown"
        )
    | where isnotempty(creationTime)
    | project 
        EventTime = creationTime,
        Operation = "Resource Creation (Inferred)",
        Status = "Succeeded",
        Caller = createdBy,
        ResourceType = type,
        ResourceName = name,
        ResourceGroup = resourceGroup,
        SubscriptionId = subscriptionId,
        Level = "Informational"
    | order by EventTime desc
    '
    
    local temp_json="${fallback_file%.csv}.json"
    
    if az graph query \
        -q "$creation_query" \
        --subscriptions "$SUBSCRIPTION_ID" \
        --output json > "$temp_json"; then
        
        # Convert to CSV
        jq -r '
            ["EventTime","Operation","Status","Caller","ResourceType","ResourceName","ResourceGroup","SubscriptionId","Level"] as $headers |
            $headers,
            (.[] | [
                .EventTime // "",
                .Operation // "",
                .Status // "",
                .Caller // "",
                .ResourceType // "",
                .ResourceName // "",
                .ResourceGroup // "",
                .SubscriptionId // "",
                .Level // ""
            ]) | @csv
        ' "$temp_json" > "$fallback_file"
        
        rm -f "$temp_json"
        
        local fallback_count
        fallback_count=$(tail -n +2 "$fallback_file" 2>/dev/null | wc -l || echo "0")
        log_info "Fallback activity data created: $fallback_count entries"
        
        # Use fallback as main output if no real activity data
        if [[ ! -s "$OUTPUT_FILE" ]]; then
            cp "$fallback_file" "$OUTPUT_FILE"
            log_info "Using fallback data as primary activity log"
        fi
        
    else
        log_warn "Failed to create fallback activity data"
        create_empty_activity_csv "$OUTPUT_FILE"
    fi
}

# Analyze resource creation patterns
analyze_resource_creation() {
    log_info "Analyzing resource creation patterns..."
    
    local creation_file="${OUTPUT_FILE%.csv}-creation-analysis.csv"
    
    if [[ ! -f "$OUTPUT_FILE" ]] || [[ ! -s "$OUTPUT_FILE" ]]; then
        log_warn "No activity data available for creation analysis"
        return 1
    fi
    
    # Analyze creation patterns by user and resource type
    {
        echo "Caller,ResourceType,CreationCount,FirstCreation,LastCreation"
        tail -n +2 "$OUTPUT_FILE" | \
        grep -i "create\|write" | \
        awk -F',' '
        BEGIN { OFS="," }
        {
            caller = $4
            resource_type = $5
            date = $1
            
            key = caller "," resource_type
            count[key]++
            
            if (first[key] == "" || date < first[key]) {
                first[key] = date
            }
            if (last[key] == "" || date > last[key]) {
                last[key] = date
            }
        }
        END {
            for (k in count) {
                print k "," count[k] "," first[k] "," last[k]
            }
        }' | sort -t',' -k3 -nr
    } > "$creation_file"
    
    local creation_count
    creation_count=$(tail -n +2 "$creation_file" 2>/dev/null | wc -l || echo "0")
    log_info "Resource creation analysis saved: $creation_file ($creation_count patterns)"
}

# Analyze resource modifications
analyze_resource_modifications() {
    log_info "Analyzing resource modification patterns..."
    
    local modification_file="${OUTPUT_FILE%.csv}-modification-analysis.csv"
    
    if [[ ! -f "$OUTPUT_FILE" ]] || [[ ! -s "$OUTPUT_FILE" ]]; then
        log_warn "No activity data available for modification analysis"
        return 1
    fi
    
    # Analyze modification patterns
    {
        echo "ResourceName,ResourceType,ModificationCount,LastModified,LastModifier,Operations"
        tail -n +2 "$OUTPUT_FILE" | \
        grep -v -i "create\|delete" | \
        awk -F',' '
        BEGIN { OFS="," }
        {
            resource_name = $6
            resource_type = $5
            caller = $4
            operation = $2
            date = $1
            
            key = resource_name "," resource_type
            count[key]++
            
            if (last_date[key] == "" || date > last_date[key]) {
                last_date[key] = date
                last_modifier[key] = caller
            }
            
            if (operations[key] == "") {
                operations[key] = operation
            } else if (index(operations[key], operation) == 0) {
                operations[key] = operations[key] ";" operation
            }
        }
        END {
            for (k in count) {
                print k "," count[k] "," last_date[k] "," last_modifier[k] "," operations[k]
            }
        }' | sort -t',' -k3 -nr
    } > "$modification_file"
    
    local mod_count
    mod_count=$(tail -n +2 "$modification_file" 2>/dev/null | wc -l || echo "0")
    log_info "Resource modification analysis saved: $modification_file ($mod_count resources)"
}

# Analyze deletion activities
analyze_deletion_activities() {
    log_info "Analyzing resource deletion activities..."
    
    local deletion_file="${OUTPUT_FILE%.csv}-deletion-analysis.csv"
    
    if [[ ! -f "$OUTPUT_FILE" ]] || [[ ! -s "$OUTPUT_FILE" ]]; then
        log_warn "No activity data available for deletion analysis"
        return 1
    fi
    
    # Analyze deletion patterns
    {
        echo "DeletionTime,ResourceName,ResourceType,DeletedBy,ResourceGroup,Operation"
        tail -n +2 "$OUTPUT_FILE" | \
        grep -i "delete" | \
        awk -F',' '
        BEGIN { OFS="," }
        {
            print $1 "," $6 "," $5 "," $4 "," $7 "," $2
        }' | sort -t',' -k1 -r
    } > "$deletion_file"
    
    local deletion_count
    deletion_count=$(tail -n +2 "$deletion_file" 2>/dev/null | wc -l || echo "0")
    log_info "Resource deletion analysis saved: $deletion_file ($deletion_count deletions)"
}

# Generate creator summary
generate_creator_summary() {
    log_info "Generating resource creator summary..."
    
    local creator_file="${OUTPUT_FILE%.csv}-creator-summary.csv"
    
    if [[ ! -f "$OUTPUT_FILE" ]] || [[ ! -s "$OUTPUT_FILE" ]]; then
        log_warn "No activity data available for creator summary"
        return 1
    fi
    
    # Summarize by creator
    {
        echo "Creator,TotalActions,CreationActions,ModificationActions,DeletionActions,ResourceTypes,LastActivity"
        tail -n +2 "$OUTPUT_FILE" | \
        awk -F',' '
        BEGIN { OFS="," }
        {
            caller = $4
            operation = $2
            resource_type = $5
            date = $1
            
            total[caller]++
            
            if (operation ~ /[Cc]reate|[Ww]rite/) {
                create[caller]++
            } else if (operation ~ /[Dd]elete/) {
                delete[caller]++
            } else {
                modify[caller]++
            }
            
            if (last_activity[caller] == "" || date > last_activity[caller]) {
                last_activity[caller] = date
            }
            
            if (resource_types[caller] == "") {
                resource_types[caller] = resource_type
            } else if (index(resource_types[caller], resource_type) == 0) {
                resource_types[caller] = resource_types[caller] ";" resource_type
            }
        }
        END {
            for (c in total) {
                print c "," total[c] "," (create[c] + 0) "," (modify[c] + 0) "," (delete[c] + 0) "," resource_types[c] "," last_activity[c]
            }
        }' | sort -t',' -k2 -nr
    } > "$creator_file"
    
    local creator_count
    creator_count=$(tail -n +2 "$creator_file" 2>/dev/null | wc -l || echo "0")
    log_info "Creator summary saved: $creator_file ($creator_count unique creators)"
}

# Generate activity summary report
generate_activity_summary() {
    log_info "Generating activity summary report..."
    
    local summary_file="${OUTPUT_FILE%.csv}-summary.txt"
    
    # Count various metrics
    local total_events creation_events modification_events deletion_events unique_callers
    
    if [[ -f "$OUTPUT_FILE" ]] && [[ -s "$OUTPUT_FILE" ]]; then
        total_events=$(tail -n +2 "$OUTPUT_FILE" | wc -l)
        creation_events=$(tail -n +2 "$OUTPUT_FILE" | grep -i "create\|write" | wc -l || echo "0")
        modification_events=$(tail -n +2 "$OUTPUT_FILE" | grep -v -i "create\|delete" | wc -l || echo "0")
        deletion_events=$(tail -n +2 "$OUTPUT_FILE" | grep -i "delete" | wc -l || echo "0")
        unique_callers=$(tail -n +2 "$OUTPUT_FILE" | cut -d',' -f4 | sort -u | wc -l || echo "0")
    else
        total_events=0
        creation_events=0
        modification_events=0
        deletion_events=0
        unique_callers=0
    fi
    
    cat > "$summary_file" << EOF
Activity Log Analysis Summary
=============================
Generated: $(date)
Subscription: $SUBSCRIPTION_ID
Analysis Period: $DAYS_BACK days

Activity Statistics:
- Total Events: $total_events
- Creation Events: $creation_events
- Modification Events: $modification_events
- Deletion Events: $deletion_events
- Unique Callers: $unique_callers

Top Resource Creators:
EOF
    
    # Add top creators if data is available
    if [[ -f "${OUTPUT_FILE%.csv}-creator-summary.csv" ]]; then
        tail -n +2 "${OUTPUT_FILE%.csv}-creator-summary.csv" | head -5 | \
        cut -d',' -f1,2,3 | \
        awk -F',' '{ print "- " $1 " (" $2 " total actions, " $3 " creations)" }' >> "$summary_file"
    fi
    
    cat >> "$summary_file" << EOF

Recent Deletions:
EOF
    
    # Add recent deletions if data is available
    if [[ -f "${OUTPUT_FILE%.csv}-deletion-analysis.csv" ]]; then
        tail -n +2 "${OUTPUT_FILE%.csv}-deletion-analysis.csv" | head -5 | \
        cut -d',' -f1,2,4 | \
        awk -F',' '{ print "- " $2 " deleted by " $3 " on " $1 }' >> "$summary_file"
    else
        echo "- No recent deletions found" >> "$summary_file"
    fi
    
    cat >> "$summary_file" << EOF

Data Quality Notes:
- Activity log retention: 90 days
- Some creation times inferred from resource metadata
- Modify operations may include routine maintenance
- Service principal activities included

Report Files Generated:
EOF
    
    # List generated files
    for file in "${OUTPUT_FILE%.csv}"*.csv; do
        if [[ -f "$file" ]]; then
            local basename=$(basename "$file")
            local count=$(tail -n +2 "$file" 2>/dev/null | wc -l || echo "0")
            echo "- $basename ($count records)" >> "$summary_file"
        fi
    done
    
    log_success "Activity summary saved to: $summary_file"
}

main() {
    parse_parameters "$@"
    [[ -z "$SUBSCRIPTION_ID" ]] && { log_error "Subscription ID required"; exit 1; }
    [[ -z "$OUTPUT_FILE" ]] && { log_error "Output file required"; exit 1; }
    
    # Validate days back parameter
    if ! [[ "$DAYS_BACK" =~ ^[0-9]+$ ]] || [[ "$DAYS_BACK" -gt 90 ]]; then
        log_error "Days back must be a number between 1 and 90"
        exit 1
    fi
    
    # Create output directory
    local output_dir
    output_dir=$(dirname "$OUTPUT_FILE")
    mkdir -p "$output_dir"
    
    track_activity
}

main "$@"