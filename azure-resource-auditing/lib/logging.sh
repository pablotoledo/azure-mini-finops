#!/bin/bash
# Centralized Logging System for Azure Resource Auditing
# Provides consistent logging across all modules

# Default log level
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Color codes for terminal output (only set if not already defined)
if [[ -z "${RED:-}" ]]; then
    readonly RED='\033[0;31m'
    readonly YELLOW='\033[0;33m'
    readonly GREEN='\033[0;32m'
    readonly BLUE='\033[0;34m'
    readonly PURPLE='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly WHITE='\033[1;37m'
    readonly NC='\033[0m' # No Color
fi

# Log levels (only set if not already defined)
if [[ -z "${LOG_LEVEL_ERROR:-}" ]]; then
    readonly LOG_LEVEL_ERROR=0
    readonly LOG_LEVEL_WARN=1
    readonly LOG_LEVEL_INFO=2
    readonly LOG_LEVEL_DEBUG=3
fi

# Convert log level string to number
get_log_level_number() {
    case "${1:-INFO}" in
        ERROR) echo $LOG_LEVEL_ERROR ;;
        WARN)  echo $LOG_LEVEL_WARN ;;
        INFO)  echo $LOG_LEVEL_INFO ;;
        DEBUG) echo $LOG_LEVEL_DEBUG ;;
        *)     echo $LOG_LEVEL_INFO ;;
    esac
}

# Check if message should be logged
should_log() {
    local msg_level="$1"
    local current_level=$(get_log_level_number "$LOG_LEVEL")
    local msg_level_num=$(get_log_level_number "$msg_level")
    
    [[ $msg_level_num -le $current_level ]]
}

# Base logging function
log_message() {
    local level="$1"
    local color="$2"
    local message="$3"
    
    if should_log "$level"; then
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        printf "${color}[%s] %s: %s${NC}\n" "$timestamp" "$level" "$message" >&2
    fi
}

# Logging functions
log_error() {
    log_message "ERROR" "$RED" "$1"
}

log_warn() {
    log_message "WARN" "$YELLOW" "$1"
}

log_info() {
    log_message "INFO" "$GREEN" "$1"
}

log_debug() {
    log_message "DEBUG" "$CYAN" "$1"
}

log_success() {
    log_message "INFO" "$GREEN" "✓ $1"
}

log_progress() {
    log_message "INFO" "$BLUE" "→ $1"
}

# Function to log command execution
log_command() {
    local command="$1"
    log_debug "Executing: $command"
}

# Function to log file operations
log_file_operation() {
    local operation="$1"
    local file="$2"
    log_debug "$operation: $file"
}

# Function to create a log separator
log_separator() {
    if should_log "INFO"; then
        printf "${PURPLE}%s${NC}\n" "$(printf '=%.0s' {1..60})" >&2
    fi
}

# Function to log script start
log_script_start() {
    local script_name="$1"
    log_separator
    log_info "Starting $script_name"
    log_separator
}

# Function to log script end
log_script_end() {
    local script_name="$1"
    local exit_code="${2:-0}"
    log_separator
    if [[ $exit_code -eq 0 ]]; then
        log_success "$script_name completed successfully"
    else
        log_error "$script_name completed with errors (exit code: $exit_code)"
    fi
    log_separator
}

# Function to log duration
log_duration() {
    local start_time="$1"
    local end_time="$2"
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    if [[ $minutes -gt 0 ]]; then
        log_info "Duration: ${minutes}m ${seconds}s"
    else
        log_info "Duration: ${seconds}s"
    fi
}

# Export functions for use in other scripts
export -f log_error log_warn log_info log_debug log_success log_progress
export -f log_command log_file_operation log_separator log_script_start log_script_end log_duration
export -f should_log get_log_level_number log_message