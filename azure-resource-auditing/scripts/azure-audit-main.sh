#!/bin/bash
# Azure Resource Auditing - Main Script
# Compatible with WSL Ubuntu and Azure CLI 2.50+

set -euo pipefail

# Script metadata
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/../lib"
readonly CONFIG_DIR="${SCRIPT_DIR}/../config"
readonly OUTPUT_DIR="${SCRIPT_DIR}/../output/reports"

# Load libraries
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/azure-helpers.sh"
source "${LIB_DIR}/validation.sh"

# Default configuration
SUBSCRIPTION_ID=""
RESOURCE_GROUPS=""
OUTPUT_FORMAT="csv"
DRY_RUN="false"
ENABLE_COST_ANALYSIS="true"
ENABLE_ORPHAN_DETECTION="true"
ENABLE_ACTIVITY_TRACKING="true"
CONFIG_FILE="${CONFIG_DIR}/audit-config.env"
PARALLEL_JOBS=5
REPORT_DATE=$(date +%Y%m%d_%H%M%S)

# Help function
show_help() {
    cat << EOF
Azure Resource Auditing Suite v2.0

USAGE:
    $0 [OPTIONS]

REQUIRED:
    -s, --subscription ID           Azure subscription ID or name

OPTIONAL:
    -g, --resource-groups GROUPS    Comma-separated list of resource groups (default: all)
    -c, --config FILE              Configuration file path
    -o, --output-dir DIR           Output directory for reports
    -f, --format FORMAT            Output format: csv, json (default: csv)
    --no-cost-analysis             Skip cost analysis (faster execution)
    --no-orphan-detection          Skip orphaned resource detection
    --no-activity-tracking         Skip activity log analysis
    --dry-run                      Preview operations without execution
    --parallel-jobs N              Number of parallel operations (default: 5)
    -v, --verbose                  Enable verbose logging
    -h, --help                     Show this help

EXAMPLES:
    # Complete audit of subscription
    $0 --subscription "12345678-1234-1234-1234-123456789012"

    # Audit specific resource groups with custom config
    $0 -s "my-subscription" -g "rg1,rg2" -c config/prod.env

    # Fast inventory without cost analysis
    $0 -s "dev-subscription" --no-cost-analysis --no-activity-tracking

    # Dry run for validation
    $0 -s "test-subscription" --dry-run

AUTHENTICATION:
    Supports Azure CLI authentication methods:
    - Interactive: az login
    - Service Principal: Environment variables
    - Managed Identity: Auto-detected in Azure VMs

OUTPUT:
    Generated CSV reports:
    - resource-inventory.csv        # Complete resource listing
    - cost-analysis.csv            # Resource-level cost data
    - orphaned-resources.csv       # Unused resources for cleanup
    - activity-summary.csv         # Resource creator tracking
    - cleanup-recommendations.csv   # Deletion recommendations

CONFIGURATION:
    Example config file (audit-config.env):
    AZURE_LOCATION="eastus"
    TAG_ENVIRONMENT="production"
    COST_THRESHOLD_HIGH=100
    RETENTION_DAYS=90
    EXCLUDE_RESOURCE_TYPES="Microsoft.Insights/components"

EXIT CODES:
    0 - Success
    1 - General error
    2 - Authentication failure
    3 - Configuration error
    4 - Azure CLI not found
EOF
}

# Parameter parsing
parse_parameters() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--subscription)
                SUBSCRIPTION_ID="$2"
                shift 2
                ;;
            -g|--resource-groups)
                RESOURCE_GROUPS="$2"
                shift 2
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -o|--output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --no-cost-analysis)
                ENABLE_COST_ANALYSIS="false"
                shift
                ;;
            --no-orphan-detection)
                ENABLE_ORPHAN_DETECTION="false"
                shift
                ;;
            --no-activity-tracking)
                ENABLE_ACTIVITY_TRACKING="false"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --parallel-jobs)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            -v|--verbose)
                LOG_LEVEL="DEBUG"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown parameter: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Main execution function
main() {
    local start_time
    start_time=$(date +%s)
    
    log_script_start "Azure Resource Auditing Suite"
    log_info "Report Date: $REPORT_DATE"
    
    # Load configuration
    load_configuration
    
    # Validate parameters
    validate_parameters
    
    # Check prerequisites
    check_prerequisites
    
    # Authenticate to Azure
    authenticate_azure || exit 2
    
    # Set subscription context
    set_subscription "$SUBSCRIPTION_ID" || exit 2
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Initialize report files
    local base_filename="${OUTPUT_DIR}/azure-audit-${REPORT_DATE}"
    
    # Execute audit modules in parallel where possible
    log_info "Starting resource audit modules..."
    
    # Resource Inventory (always run first)
    log_info "Collecting resource inventory..."
    if [[ "$DRY_RUN" != "true" ]]; then
        "${SCRIPT_DIR}/inventory-collector.sh" \
            --subscription "$SUBSCRIPTION_ID" \
            --resource-groups "$RESOURCE_GROUPS" \
            --output "${base_filename}-inventory.csv" \
            --parallel-jobs "$PARALLEL_JOBS" || log_warn "Inventory collection had errors"
    else
        log_info "DRY RUN: Would collect resource inventory"
    fi
    
    # Parallel execution of independent modules
    local pids=()
    
    if [[ "$ENABLE_COST_ANALYSIS" == "true" ]]; then
        log_info "Starting cost analysis module..."
        if [[ "$DRY_RUN" != "true" ]]; then
            "${SCRIPT_DIR}/cost-analyzer.sh" \
                --subscription "$SUBSCRIPTION_ID" \
                --output "${base_filename}-costs.csv" &
            pids+=($!)
        else
            log_info "DRY RUN: Would perform cost analysis"
        fi
    fi
    
    if [[ "$ENABLE_ORPHAN_DETECTION" == "true" ]]; then
        log_info "Starting orphaned resource detection..."
        if [[ "$DRY_RUN" != "true" ]]; then
            "${SCRIPT_DIR}/orphan-detector.sh" \
                --subscription "$SUBSCRIPTION_ID" \
                --output "${base_filename}-orphans.csv" &
            pids+=($!)
        else
            log_info "DRY RUN: Would detect orphaned resources"
        fi
    fi
    
    if [[ "$ENABLE_ACTIVITY_TRACKING" == "true" ]]; then
        log_info "Starting activity log analysis..."
        if [[ "$DRY_RUN" != "true" ]]; then
            "${SCRIPT_DIR}/activity-tracker.sh" \
                --subscription "$SUBSCRIPTION_ID" \
                --output "${base_filename}-activity.csv" &
            pids+=($!)
        else
            log_info "DRY RUN: Would analyze activity logs"
        fi
    fi
    
    # Wait for parallel jobs to complete
    if [[ ${#pids[@]} -gt 0 ]]; then
        log_info "Waiting for analysis modules to complete..."
        for pid in "${pids[@]}"; do
            wait "$pid" || log_warn "Module with PID $pid completed with errors"
        done
    fi
    
    # Generate cleanup recommendations (depends on previous analyses)
    log_info "Generating cleanup recommendations..."
    if [[ "$DRY_RUN" != "true" ]]; then
        "${SCRIPT_DIR}/cleanup-manager.sh" \
            --subscription "$SUBSCRIPTION_ID" \
            --input-dir "$OUTPUT_DIR" \
            --output "${base_filename}-cleanup.csv" \
            --report-date "$REPORT_DATE" || log_warn "Cleanup recommendations had errors"
    else
        log_info "DRY RUN: Would generate cleanup recommendations"
    fi
    
    # Generate summary report
    generate_summary_report "${base_filename}"
    
    local end_time
    end_time=$(date +%s)
    log_duration "$start_time" "$end_time"
    
    log_script_end "Azure Resource Audit" 0
    log_info "Reports saved to: $OUTPUT_DIR"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN completed - no actual changes made"
    fi
}

# Configuration loading
load_configuration() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Loading configuration from: $CONFIG_FILE"
        source "$CONFIG_FILE"
    else
        log_warn "Configuration file not found: $CONFIG_FILE"
        log_info "Using default settings"
    fi
    
    # Load cost thresholds if available
    local cost_config="${CONFIG_DIR}/cost-thresholds.env"
    [[ -f "$cost_config" ]] && source "$cost_config"
}

# Parameter validation
validate_parameters() {
    log_info "Validating parameters..."
    
    # Validate required parameters
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        log_error "Subscription ID is required"
        echo "Use --help for usage information"
        exit 3
    fi
    
    # Validate using validation library
    if ! validate_main_parameters "$SUBSCRIPTION_ID" "$RESOURCE_GROUPS" "$OUTPUT_DIR" "$OUTPUT_FORMAT" "$PARALLEL_JOBS" "$CONFIG_FILE"; then
        exit 3
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! check_azure_cli; then
        exit 4
    fi
    
    # Check required extensions
    if ! check_azure_extensions; then
        exit 4
    fi
    
    # Validate subscription access
    if ! validate_subscription "$SUBSCRIPTION_ID"; then
        exit 2
    fi
    
    # Validate resource groups if specified
    if ! validate_resource_groups "$SUBSCRIPTION_ID" "$RESOURCE_GROUPS"; then
        exit 3
    fi
}

# Summary report generation
generate_summary_report() {
    local base_filename="$1"
    local summary_file="${base_filename}-summary.txt"
    
    log_info "Generating summary report: $summary_file"
    
    cat > "$summary_file" << EOF
Azure Resource Audit Summary Report
===================================
Generated: $(date)
Subscription: $SUBSCRIPTION_ID
Resource Groups: ${RESOURCE_GROUPS:-"All"}

Report Files Generated:
EOF
    
    for file in "${base_filename}"*.csv; do
        if [[ -f "$file" ]]; then
            local basename=$(basename "$file")
            local count=$(tail -n +2 "$file" 2>/dev/null | wc -l || echo "0")
            echo "  - $basename ($count records)" >> "$summary_file"
        fi
    done
    
    echo "" >> "$summary_file"
    echo "Next Steps:" >> "$summary_file"
    echo "1. Review resource inventory for accuracy" >> "$summary_file"
    echo "2. Analyze cost report for optimization opportunities" >> "$summary_file"
    echo "3. Validate orphaned resources before cleanup" >> "$summary_file"
    echo "4. Use cleanup recommendations with safety tagging" >> "$summary_file"
    
    log_success "Summary report generated: $summary_file"
}

# Error handling
trap 'log_error "Script failed at line $LINENO"' ERR

# Script execution
parse_parameters "$@"
main

exit 0