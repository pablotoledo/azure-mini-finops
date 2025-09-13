#!/bin/bash
# Azure Cost Analysis Module
# Resource-level cost analysis using Cost Management API

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/../lib"

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/azure-helpers.sh"

SUBSCRIPTION_ID=""
OUTPUT_FILE=""
TIME_PERIOD="MonthToDate"

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
            --time-period)
                TIME_PERIOD="$2"
                shift 2
                ;;
        esac
    done
}

# Cost analysis using modern Cost Management API
analyze_costs() {
    log_script_start "Cost Analysis"
    log_info "Analyzing costs for subscription: $SUBSCRIPTION_ID"
    log_info "Time period: $TIME_PERIOD"
    
    # Current month costs by resource
    local cost_query='{
        "type": "ActualCost",
        "timeframe": "'$TIME_PERIOD'",
        "dataset": {
            "granularity": "Daily",
            "aggregation": {
                "totalCost": {
                    "name": "PreTaxCost",
                    "function": "Sum"
                }
            },
            "grouping": [
                {
                    "type": "Dimension",
                    "name": "ResourceId"
                },
                {
                    "type": "Dimension", 
                    "name": "ResourceType"
                },
                {
                    "type": "Dimension",
                    "name": "ResourceLocation"
                },
                {
                    "type": "Dimension",
                    "name": "ChargeType"
                }
            ]
        }
    }'
    
    log_info "Querying Cost Management API..."
    
    local temp_json="${OUTPUT_FILE%.csv}-raw.json"
    
    # Execute cost query with retry logic
    if az_execute_with_retry "az rest --method post --url \"/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.CostManagement/query?api-version=2023-03-01\" --body '$cost_query' --output json" 3 10 > "$temp_json"; then
        
        log_success "Cost Management API query completed"
        
        # Convert to CSV
        log_info "Processing cost data..."
        if process_cost_data "$temp_json" "$OUTPUT_FILE"; then
            
            # Get resource-level cost breakdown
            generate_resource_cost_breakdown
            
            # Generate cost optimization recommendations
            generate_cost_recommendations
            
            # Clean up
            rm -f "$temp_json"
            
            local cost_records
            cost_records=$(tail -n +2 "$OUTPUT_FILE" 2>/dev/null | wc -l || echo "0")
            log_success "Cost analysis complete: $OUTPUT_FILE ($cost_records records)"
        else
            log_error "Failed to process cost data"
            return 1
        fi
    else
        log_error "Cost Management API query failed"
        log_warn "This might be due to permissions or API availability"
        
        # Fallback: try alternative cost collection method
        log_info "Attempting alternative cost collection..."
        collect_cost_fallback
    fi
}

process_cost_data() {
    local input_file="$1"
    local output_file="$2"
    
    log_debug "Processing cost data from: $input_file"
    
    # Check if the response has the expected structure
    if ! jq -e '.properties.rows' "$input_file" >/dev/null 2>&1; then
        log_warn "Unexpected cost data structure, attempting to parse..."
        
        # Try alternative parsing
        if jq -e '.[]' "$input_file" >/dev/null 2>&1; then
            # Array format
            jq -r '
                ["Date","ResourceId","ResourceType","ResourceLocation","ChargeType","Cost"] as $headers |
                $headers,
                (.[] | [
                    (.date // ""),
                    (.resourceId // ""),
                    (.resourceType // ""),
                    (.location // ""),
                    (.chargeType // ""),
                    (.cost // 0)
                ]) | @csv
            ' "$input_file" > "$output_file"
        else
            log_error "Unable to parse cost data structure"
            return 1
        fi
    else
        # Standard Cost Management API response
        jq -r '
            ["Date","ResourceId","ResourceType","ResourceLocation","ChargeType","Cost"] as $headers |
            $headers,
            (.properties.rows[]? as $row |
                [
                    ($row[0] // ""),
                    ($row[1] // ""),
                    ($row[2] // ""),
                    ($row[3] // ""),
                    ($row[4] // ""),
                    ($row[5] // 0)
                ]
            ) | @csv
        ' "$input_file" > "$output_file"
    fi
    
    # Validate the output
    if [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
        log_success "Cost data processing completed"
        return 0
    else
        log_error "Cost data processing failed - empty output"
        return 1
    fi
}

# Fallback cost collection using resource pricing estimates
collect_cost_fallback() {
    log_info "Using fallback cost collection method..."
    
    local fallback_file="${OUTPUT_FILE%.csv}-fallback.csv"
    
    # Create a basic cost estimate based on resource types and sizes
    echo "ResourceType,EstimatedMonthlyCost,Confidence,Notes" > "$fallback_file"
    
    # Get VM information for cost estimation
    if az vm list --subscription "$SUBSCRIPTION_ID" --output json | \
    jq -r '
        .[] | [
            "Microsoft.Compute/virtualMachines",
            (if .hardwareProfile.vmSize then 
                (if (.hardwareProfile.vmSize | contains("Standard_B")) then "50-150"
                elif (.hardwareProfile.vmSize | contains("Standard_D")) then "100-300"
                elif (.hardwareProfile.vmSize | contains("Standard_F")) then "80-250"
                else "30-500" end)
            else "Unknown" end),
            "Low",
            ("VM Size: " + (.hardwareProfile.vmSize // "Unknown"))
        ] | @csv
    ' >> "$fallback_file"; then
        log_info "Basic VM cost estimates added"
    fi
    
    # Add storage account estimates
    if az storage account list --subscription "$SUBSCRIPTION_ID" --output json | \
    jq -r '
        .[] | [
            "Microsoft.Storage/storageAccounts",
            (if .sku.name then
                (if (.sku.name | contains("Standard")) then "20-100"
                elif (.sku.name | contains("Premium")) then "50-200"
                else "10-150" end)
            else "Unknown" end),
            "Low",
            ("SKU: " + (.sku.name // "Unknown"))
        ] | @csv
    ' >> "$fallback_file"; then
        log_info "Basic storage cost estimates added"
    fi
    
    log_warn "Fallback cost collection completed with limited accuracy"
    log_info "For accurate costs, ensure proper Cost Management API permissions"
}

# Generate resource-level cost breakdown
generate_resource_cost_breakdown() {
    local breakdown_file="${OUTPUT_FILE%.csv}-breakdown.csv"
    
    log_info "Generating resource cost breakdown..."
    
    if [[ ! -f "$OUTPUT_FILE" ]] || [[ ! -s "$OUTPUT_FILE" ]]; then
        log_warn "No cost data available for breakdown"
        return 1
    fi
    
    # Aggregate costs by resource
    {
        echo "ResourceId,TotalCost,ResourceType,Location"
        tail -n +2 "$OUTPUT_FILE" | \
        awk -F',' '
        BEGIN { OFS="," }
        {
            resource = $2
            cost = $6
            type = $3
            location = $4
            if (resource != "" && cost != "") {
                total[resource] += cost
                res_type[resource] = type
                res_location[resource] = location
            }
        }
        END {
            for (r in total) {
                print r, total[r], res_type[r], res_location[r]
            }
        }' | sort -t',' -k2 -nr
    } > "$breakdown_file"
    
    local breakdown_count
    breakdown_count=$(tail -n +2 "$breakdown_file" 2>/dev/null | wc -l || echo "0")
    log_info "Resource cost breakdown saved: $breakdown_file ($breakdown_count resources)"
}

# Cost optimization recommendations
generate_cost_recommendations() {
    log_info "Generating cost optimization recommendations..."
    
    local recommendations_file="${OUTPUT_FILE%.csv}-recommendations.csv"
    
    # Get Azure Advisor cost recommendations
    log_debug "Querying Azure Advisor for cost recommendations..."
    
    if az advisor recommendation list \
        --category Cost \
        --subscription "$SUBSCRIPTION_ID" \
        --output json 2>/dev/null | \
    jq -r '
        ["ResourceName","ResourceType","Impact","PotentialSavings","Recommendation","Category"] as $headers |
        $headers,
        (.[] | [
            (.impactedValue // ""),
            (.impactedField // ""),
            (.impact // ""),
            (.extendedProperties.savingsAmount // "0"),
            (.shortDescription.solution // ""),
            "Azure Advisor"
        ]) | @csv
    ' > "$recommendations_file"; then
        
        local rec_count
        rec_count=$(tail -n +2 "$recommendations_file" 2>/dev/null | wc -l || echo "0")
        log_info "Azure Advisor recommendations saved: $rec_count recommendations"
    else
        log_warn "Unable to retrieve Azure Advisor recommendations"
        # Create basic recommendations based on cost analysis
        generate_basic_recommendations "$recommendations_file"
    fi
    
    # Add custom recommendations based on cost patterns
    add_custom_recommendations "$recommendations_file"
}

# Generate basic cost recommendations
generate_basic_recommendations() {
    local rec_file="$1"
    
    log_debug "Generating basic cost recommendations..."
    
    echo "ResourceName,ResourceType,Impact,PotentialSavings,Recommendation,Category" > "$rec_file"
    
    # Add recommendations based on cost thresholds
    if [[ -f "${OUTPUT_FILE%.csv}-breakdown.csv" ]]; then
        tail -n +2 "${OUTPUT_FILE%.csv}-breakdown.csv" | \
        awk -F',' -v high="${COST_THRESHOLD_HIGH:-500}" -v medium="${COST_THRESHOLD_MEDIUM:-100}" '
        BEGIN { OFS="," }
        {
            resource = $1
            cost = $2
            type = $3
            if (cost > high) {
                print resource, type, "High", cost * 0.2, "Consider rightsizing or reserved instances", "Custom Analysis"
            } else if (cost > medium) {
                print resource, type, "Medium", cost * 0.1, "Review utilization and optimize", "Custom Analysis"
            }
        }' >> "$rec_file"
    fi
}

# Add custom recommendations
add_custom_recommendations() {
    local rec_file="$1"
    
    log_debug "Adding custom cost recommendations..."
    
    # Add VM rightsizing recommendations
    if command -v az vm list >/dev/null 2>&1; then
        az vm list --subscription "$SUBSCRIPTION_ID" --show-details --output json 2>/dev/null | \
        jq -r '
            .[] | 
            select(.powerState == "VM deallocated" or .powerState == "VM stopped") |
            [
                .name,
                "Microsoft.Compute/virtualMachines",
                "Medium",
                "50-200",
                "VM is stopped/deallocated - consider deletion if not needed",
                "Power State Analysis"
            ] | @csv
        ' >> "$rec_file" 2>/dev/null || true
    fi
    
    log_debug "Custom recommendations added"
}

# Generate cost trend analysis
generate_cost_trends() {
    log_info "Generating cost trend analysis..."
    
    local trends_file="${OUTPUT_FILE%.csv}-trends.csv"
    
    # Query for historical cost data (last 30 days)
    local trend_query='{
        "type": "ActualCost",
        "timeframe": "Custom",
        "timePeriod": {
            "from": "'$(date -d "30 days ago" +%Y-%m-%d)'T00:00:00Z",
            "to": "'$(date +%Y-%m-%d)'T23:59:59Z"
        },
        "dataset": {
            "granularity": "Daily",
            "aggregation": {
                "totalCost": {
                    "name": "PreTaxCost",
                    "function": "Sum"
                }
            },
            "grouping": [
                {
                    "type": "Dimension",
                    "name": "ResourceType"
                }
            ]
        }
    }'
    
    if az rest --method post \
        --url "/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.CostManagement/query?api-version=2023-03-01" \
        --body "$trend_query" \
        --output json > "${trends_file%.csv}.json" 2>/dev/null; then
        
        # Process trend data
        jq -r '
            ["Date","ResourceType","DailyCost"] as $headers |
            $headers,
            (.properties.rows[]? as $row |
                [
                    ($row[0] // ""),
                    ($row[1] // ""),
                    ($row[2] // 0)
                ]
            ) | @csv
        ' "${trends_file%.csv}.json" > "$trends_file"
        
        rm -f "${trends_file%.csv}.json"
        
        local trend_count
        trend_count=$(tail -n +2 "$trends_file" 2>/dev/null | wc -l || echo "0")
        log_info "Cost trend analysis saved: $trends_file ($trend_count records)"
    else
        log_warn "Unable to generate cost trend analysis"
    fi
}

main() {
    parse_parameters "$@"
    [[ -z "$SUBSCRIPTION_ID" ]] && { log_error "Subscription ID required"; exit 1; }
    [[ -z "$OUTPUT_FILE" ]] && { log_error "Output file required"; exit 1; }
    
    # Create output directory
    local output_dir
    output_dir=$(dirname "$OUTPUT_FILE")
    mkdir -p "$output_dir"
    
    analyze_costs
    generate_cost_trends
    
    log_script_end "Cost Analysis" 0
}

main "$@"