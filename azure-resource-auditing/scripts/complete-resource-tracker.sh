#!/bin/bash
# Complete Resource Creation Tracker
# Gets creation info for ALL resources using multiple data sources

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/../lib"

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/azure-helpers.sh"

SUBSCRIPTION_ID=""
OUTPUT_FILE=""
INCLUDE_ACTIVITY_LOG="true"

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
            --no-activity-log)
                INCLUDE_ACTIVITY_LOG="false"
                shift
                ;;
        esac
    done
}

# Get creation info for ALL resources using Resource Graph
get_all_resource_creation_info() {
    log_script_start "Complete Resource Creation Analysis"
    log_info "Getting creation information for ALL resources in subscription..."

    local complete_query='
    Resources
    | join kind=leftouter (
        ResourceContainers
        | where type == "microsoft.resources/subscriptions"
        | project subscriptionName = name, subscriptionId
    ) on subscriptionId
    | extend
        // Extract creation time from multiple possible properties
        CreationTime = case(
            isnotempty(properties.timeCreated), tostring(properties.timeCreated),
            isnotempty(properties.creationDate), tostring(properties.creationDate),
            isnotempty(properties.createdTime), tostring(properties.createdTime),
            isnotempty(properties.createdOn), tostring(properties.createdOn),
            isnotempty(properties.created), tostring(properties.created),
            isnotempty(properties.provisionedOn), tostring(properties.provisionedOn),
            ""
        ),
        // Extract creator information from multiple tag formats
        CreatedBy = case(
            isnotempty(tags["CreatedBy"]), tostring(tags["CreatedBy"]),
            isnotempty(tags["created-by"]), tostring(tags["created-by"]),
            isnotempty(tags["createdBy"]), tostring(tags["createdBy"]),
            isnotempty(tags["Owner"]), tostring(tags["Owner"]),
            isnotempty(tags["owner"]), tostring(tags["owner"]),
            isnotempty(tags["Creator"]), tostring(tags["Creator"]),
            isnotempty(tags["creator"]), tostring(tags["creator"]),
            isnotempty(tags["Author"]), tostring(tags["Author"]),
            isnotempty(tags["author"]), tostring(tags["author"]),
            isnotempty(tags["DeployedBy"]), tostring(tags["DeployedBy"]),
            isnotempty(tags["deployed-by"]), tostring(tags["deployed-by"]),
            "Unknown"
        ),
        // Extract additional metadata
        Environment = case(
            isnotempty(tags["Environment"]), tostring(tags["Environment"]),
            isnotempty(tags["environment"]), tostring(tags["environment"]),
            isnotempty(tags["Env"]), tostring(tags["Env"]),
            isnotempty(tags["env"]), tostring(tags["env"]),
            "Unknown"
        ),
        Project = case(
            isnotempty(tags["Project"]), tostring(tags["Project"]),
            isnotempty(tags["project"]), tostring(tags["project"]),
            isnotempty(tags["ProjectName"]), tostring(tags["ProjectName"]),
            isnotempty(tags["project-name"]), tostring(tags["project-name"]),
            "Unknown"
        ),
        CostCenter = case(
            isnotempty(tags["CostCenter"]), tostring(tags["CostCenter"]),
            isnotempty(tags["cost-center"]), tostring(tags["cost-center"]),
            isnotempty(tags["Department"]), tostring(tags["Department"]),
            isnotempty(tags["department"]), tostring(tags["department"]),
            "Unknown"
        ),
        // Calculate age in days
        AgeInDays = case(
            isnotempty(properties.timeCreated),
            datetime_diff("day", now(), todatetime(properties.timeCreated)),
            isnotempty(properties.creationDate),
            datetime_diff("day", now(), todatetime(properties.creationDate)),
            isnotempty(properties.createdTime),
            datetime_diff("day", now(), todatetime(properties.createdTime)),
            -1
        ),
        // Categorize by age
        AgeCategory = case(
            isnotempty(properties.timeCreated) or isnotempty(properties.creationDate) or isnotempty(properties.createdTime),
            case(
                datetime_diff("day", now(), coalesce(todatetime(properties.timeCreated), todatetime(properties.creationDate), todatetime(properties.createdTime))) <= 7, "Last 7 days",
                datetime_diff("day", now(), coalesce(todatetime(properties.timeCreated), todatetime(properties.creationDate), todatetime(properties.createdTime))) <= 30, "Last 30 days",
                datetime_diff("day", now(), coalesce(todatetime(properties.timeCreated), todatetime(properties.creationDate), todatetime(properties.createdTime))) <= 90, "Last 90 days",
                datetime_diff("day", now(), coalesce(todatetime(properties.timeCreated), todatetime(properties.creationDate), todatetime(properties.createdTime))) <= 365, "Last year",
                "Over 1 year old"
            ),
            "Unknown age"
        ),
        // Resource size/configuration info
        ResourceSize = case(
            type =~ "microsoft.compute/virtualmachines" and isnotempty(properties.hardwareProfile.vmSize),
            tostring(properties.hardwareProfile.vmSize),
            type =~ "microsoft.compute/disks" and isnotempty(properties.diskSizeGB),
            strcat(tostring(properties.diskSizeGB), " GB"),
            type =~ "microsoft.sql/servers/databases" and isnotempty(properties.currentServiceObjectiveName),
            tostring(properties.currentServiceObjectiveName),
            type =~ "microsoft.storage/storageaccounts" and isnotempty(sku.name),
            tostring(sku.name),
            ""
        ),
        // Provisioning state
        ProvisioningState = tostring(properties.provisioningState),
        // Power state for VMs
        PowerState = case(
            type =~ "microsoft.compute/virtualmachines" and isnotempty(properties.extended.instanceView.powerState.code),
            tostring(properties.extended.instanceView.powerState.code),
            ""
        )
    | project
        SubscriptionName = subscriptionName,
        SubscriptionId = subscriptionId,
        ResourceGroup = resourceGroup,
        ResourceName = name,
        ResourceType = type,
        Location = location,
        CreationTime,
        CreatedBy,
        Environment,
        Project,
        CostCenter,
        AgeInDays,
        AgeCategory,
        ResourceSize,
        ProvisioningState,
        PowerState,
        Tags = tags
    | order by CreationTime desc, ResourceName asc
    '

    local temp_json="${OUTPUT_FILE%.csv}.json"

    if az graph query \
        -q "$complete_query" \
        --subscriptions "$SUBSCRIPTION_ID" \
        --output json > "$temp_json"; then

        log_success "Resource Graph query completed"

        # Convert to CSV
        jq -r '
            ["SubscriptionName","SubscriptionId","ResourceGroup","ResourceName","ResourceType","Location","CreationTime","CreatedBy","Environment","Project","CostCenter","AgeInDays","AgeCategory","ResourceSize","ProvisioningState","PowerState","Tags"] as $headers |
            $headers,
            (.[] | [
                .SubscriptionName // "",
                .SubscriptionId // "",
                .ResourceGroup // "",
                .ResourceName // "",
                .ResourceType // "",
                .Location // "",
                .CreationTime // "",
                .CreatedBy // "",
                .Environment // "",
                .Project // "",
                .CostCenter // "",
                .AgeInDays // "",
                .AgeCategory // "",
                .ResourceSize // "",
                .ProvisioningState // "",
                .PowerState // "",
                (.Tags // {} | to_entries | map("\(.key)=\(.value)") | join(";"))
            ]) | @csv
        ' "$temp_json" > "$OUTPUT_FILE"

        rm -f "$temp_json"

        local total_resources
        total_resources=$(tail -n +2 "$OUTPUT_FILE" | wc -l)
        log_success "Complete resource analysis saved: $OUTPUT_FILE ($total_resources resources)"

        # Generate detailed analysis
        generate_detailed_analysis

    else
        log_error "Failed to get complete resource information"
        return 1
    fi
}

# Generate detailed analysis and statistics
generate_detailed_analysis() {
    log_info "Generating detailed resource analysis..."

    local summary_file="${OUTPUT_FILE%.csv}-analysis.txt"
    local creators_file="${OUTPUT_FILE%.csv}-by-creator.csv"
    local age_file="${OUTPUT_FILE%.csv}-by-age.csv"

    # Main summary
    cat > "$summary_file" << EOF
Complete Resource Creation Analysis Report
==========================================
Generated: $(date)
Subscription: $SUBSCRIPTION_ID

OVERVIEW
========
EOF

    local total_resources with_creation_time with_creator with_env with_project
    total_resources=$(tail -n +2 "$OUTPUT_FILE" | wc -l)
    with_creation_time=$(tail -n +2 "$OUTPUT_FILE" | awk -F',' '$7 != ""' | wc -l)
    with_creator=$(tail -n +2 "$OUTPUT_FILE" | awk -F',' '$8 != "Unknown" && $8 != ""' | wc -l)
    with_env=$(tail -n +2 "$OUTPUT_FILE" | awk -F',' '$9 != "Unknown" && $9 != ""' | wc -l)
    with_project=$(tail -n +2 "$OUTPUT_FILE" | awk -F',' '$10 != "Unknown" && $10 != ""' | wc -l)

    cat >> "$summary_file" << EOF
Total Resources: $total_resources
Resources with Creation Time: $with_creation_time ($(( with_creation_time * 100 / total_resources ))%)
Resources with Creator Info: $with_creator ($(( with_creator * 100 / total_resources ))%)
Resources with Environment Tags: $with_env ($(( with_env * 100 / total_resources ))%)
Resources with Project Tags: $with_project ($(( with_project * 100 / total_resources ))%)

RESOURCE COUNT BY AGE CATEGORY
===============================
EOF

    tail -n +2 "$OUTPUT_FILE" | cut -d',' -f13 | sort | uniq -c | \
    awk '{printf "%-20s: %5d resources\n", $2, $1}' >> "$summary_file"

    cat >> "$summary_file" << EOF

RESOURCE COUNT BY TYPE (TOP 15)
================================
EOF

    tail -n +2 "$OUTPUT_FILE" | cut -d',' -f5 | sed 's/"//g' | sort | uniq -c | sort -nr | head -15 | \
    awk '{printf "%-60s: %3d\n", $2, $1}' >> "$summary_file"

    cat >> "$summary_file" << EOF

RESOURCE COUNT BY LOCATION
===========================
EOF

    tail -n +2 "$OUTPUT_FILE" | cut -d',' -f6 | sed 's/"//g' | sort | uniq -c | sort -nr | \
    awk '{printf "%-20s: %5d resources\n", $2, $1}' >> "$summary_file"

    # Top creators analysis
    {
        echo "Creator,ResourceCount,ResourceTypes,Environments,Projects"
        tail -n +2 "$OUTPUT_FILE" | awk -F',' '
        $8 != "Unknown" && $8 != "" {
            creator = $8
            gsub(/"/, "", creator)
            creators[creator]++

            type = $5
            gsub(/"/, "", type)
            if (creator_types[creator] == "") {
                creator_types[creator] = type
            } else if (index(creator_types[creator], type) == 0) {
                creator_types[creator] = creator_types[creator] ";" type
            }

            env = $9
            gsub(/"/, "", env)
            if (env != "Unknown" && env != "") {
                if (creator_envs[creator] == "") {
                    creator_envs[creator] = env
                } else if (index(creator_envs[creator], env) == 0) {
                    creator_envs[creator] = creator_envs[creator] ";" env
                }
            }

            proj = $10
            gsub(/"/, "", proj)
            if (proj != "Unknown" && proj != "") {
                if (creator_projs[creator] == "") {
                    creator_projs[creator] = proj
                } else if (index(creator_projs[creator], proj) == 0) {
                    creator_projs[creator] = creator_projs[creator] ";" proj
                }
            }
        }
        END {
            for (c in creators) {
                print c "," creators[c] "," creator_types[c] "," creator_envs[c] "," creator_projs[c]
            }
        }' | sort -t',' -k2 -nr
    } > "$creators_file"

    cat >> "$summary_file" << EOF

TOP RESOURCE CREATORS
=====================
EOF

    tail -n +2 "$creators_file" | head -10 | \
    awk -F',' '{printf "%-40s: %3d resources\n", $1, $2}' >> "$summary_file"

    # Age distribution analysis
    {
        echo "AgeCategory,Count,Percentage"
        tail -n +2 "$OUTPUT_FILE" | cut -d',' -f13 | sed 's/"//g' | sort | uniq -c | \
        awk -v total="$total_resources" '{
            printf "%s,%d,%.1f\n", $2, $1, ($1 * 100.0 / total)
        }'
    } > "$age_file"

    log_success "Detailed analysis saved:"
    log_info "  - Summary: $summary_file"
    log_info "  - By Creator: $creators_file"
    log_info "  - By Age: $age_file"
}

# Enhanced analysis with Activity Log data (last 90 days) for recent resources
enhance_with_activity_log() {
    if [[ "$INCLUDE_ACTIVITY_LOG" != "true" ]]; then
        log_info "Skipping Activity Log enhancement (disabled)"
        return 0
    fi

    log_info "Enhancing with Activity Log data (last 90 days)..."

    local activity_file="${OUTPUT_FILE%.csv}-activity-enhanced.csv"
    local start_date=$(date -d "90 days ago" +%Y-%m-%d)
    local end_date=$(date +%Y-%m-%d)

    log_info "Collecting Activity Log data from $start_date to $end_date..."

    # Get Activity Log data for resource creation events
    if az monitor activity-log list \
        --subscription "$SUBSCRIPTION_ID" \
        --start-time "${start_date}T00:00:00Z" \
        --end-time "${end_date}T23:59:59Z" \
        --status "Succeeded" \
        --output json | \
    jq -r '
        map(select(.operationName.value | test("write$|create"; "i"))) |
        map(select(.resourceId != null)) |
        map({
            resourceId: .resourceId,
            resourceName: (.resourceId | split("/")[-1]),
            resourceType: (.resourceType.value // ""),
            resourceGroup: (.resourceGroupName // ""),
            caller: .caller,
            eventTime: .eventTimestamp,
            operation: .operationName.value,
            correlationId: .correlationId
        }) |
        group_by(.resourceName) |
        map({
            resourceName: .[0].resourceName,
            resourceType: .[0].resourceType,
            resourceGroup: .[0].resourceGroup,
            createdByActivity: .[0].caller,
            creationTimeFromActivity: (sort_by(.eventTime) | .[0].eventTime),
            operations: [.[].operation] | unique | join(";")
        })
    ' > "${activity_file%.csv}.json"; then

        log_success "Activity Log data retrieved"

        # Convert to CSV
        jq -r '
            ["ResourceName","ResourceType","ResourceGroup","CreatedByActivity","CreationTimeFromActivity","Operations"] as $headers |
            $headers,
            (.[] | [
                .resourceName,
                .resourceType,
                .resourceGroup,
                .createdByActivity,
                .creationTimeFromActivity,
                .operations
            ]) | @csv
        ' "${activity_file%.csv}.json" > "$activity_file"

        rm -f "${activity_file%.csv}.json"

        local activity_count
        activity_count=$(tail -n +2 "$activity_file" | wc -l)
        log_success "Activity Log enhancement saved: $activity_file ($activity_count resources)"

    else
        log_warn "Could not retrieve Activity Log data - may need additional permissions"
    fi
}

# Generate governance recommendations
generate_governance_recommendations() {
    log_info "Generating governance recommendations..."

    local governance_file="${OUTPUT_FILE%.csv}-governance-recommendations.txt"
    local total_resources
    total_resources=$(tail -n +2 "$OUTPUT_FILE" | wc -l)

    cat > "$governance_file" << EOF
Resource Governance Recommendations
===================================
Generated: $(date)
Based on analysis of $total_resources resources

TAGGING COMPLIANCE ISSUES
=========================
EOF

    # Resources without creator info
    local no_creator
    no_creator=$(tail -n +2 "$OUTPUT_FILE" | awk -F',' '$8 == "Unknown" || $8 == ""' | wc -l)

    cat >> "$governance_file" << EOF
1. Missing Creator Information: $no_creator resources ($(( no_creator * 100 / total_resources ))%)
   - Recommendation: Implement mandatory CreatedBy or Owner tags
   - Impact: Cannot identify resource ownership for cost allocation

EOF

    # Resources without environment tags
    local no_env
    no_env=$(tail -n +2 "$OUTPUT_FILE" | awk -F',' '$9 == "Unknown" || $9 == ""' | wc -l)

    cat >> "$governance_file" << EOF
2. Missing Environment Tags: $no_env resources ($(( no_env * 100 / total_resources ))%)
   - Recommendation: Implement mandatory Environment tags (dev/test/prod)
   - Impact: Cannot apply environment-specific policies

EOF

    # Resources without project tags
    local no_project
    no_project=$(tail -n +2 "$OUTPUT_FILE" | awk -F',' '$10 == "Unknown" || $10 == ""' | wc -l)

    cat >> "$governance_file" << EOF
3. Missing Project Tags: $no_project resources ($(( no_project * 100 / total_resources ))%)
   - Recommendation: Implement mandatory Project or Application tags
   - Impact: Cannot track costs by project or application

RECOMMENDED ACTIONS
===================
1. Create Azure Policy to enforce mandatory tags
2. Implement automated tagging via Azure Resource Manager templates
3. Set up regular tagging compliance reports
4. Train teams on proper resource tagging standards
5. Consider using Azure Resource Graph queries for ongoing monitoring

OLD RESOURCES REVIEW
====================
EOF

    # Very old resources that might need review
    local very_old
    very_old=$(tail -n +2 "$OUTPUT_FILE" | awk -F',' '$13 == "Over 1 year old"' | wc -l)

    cat >> "$governance_file" << EOF
Resources over 1 year old: $very_old
- Recommendation: Review for continued business need
- Consider implementing lifecycle management policies
- Evaluate for cost optimization opportunities
EOF

    log_success "Governance recommendations saved: $governance_file"
}

main() {
    parse_parameters "$@"
    [[ -z "$SUBSCRIPTION_ID" ]] && { log_error "Subscription ID required"; exit 1; }
    [[ -z "$OUTPUT_FILE" ]] && { log_error "Output file required"; exit 1; }

    local output_dir
    output_dir=$(dirname "$OUTPUT_FILE")
    mkdir -p "$output_dir"

    get_all_resource_creation_info
    enhance_with_activity_log
    generate_governance_recommendations

    log_script_end "Complete Resource Creation Analysis" 0
}

main "$@"
