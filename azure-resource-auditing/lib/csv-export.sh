#!/bin/bash
# CSV Export Functions
# Utilities for formatting and exporting data to CSV format

# Source logging if available
if [[ -f "${LIB_DIR:-./}/logging.sh" ]]; then
    source "${LIB_DIR:-./}/logging.sh"
fi

# CSV formatting utility functions
csv_escape_field() {
    local field="$1"
    
    # If field contains comma, quote, or newline, wrap in quotes and escape internal quotes
    if [[ "$field" =~ [,\"$'\n'] ]]; then
        field=$(echo "$field" | sed 's/"/""/g')  # Escape quotes by doubling them
        echo "\"$field\""
    else
        echo "$field"
    fi
}

# Create CSV header row
create_csv_header() {
    local -a headers=("$@")
    local csv_line=""
    
    for header in "${headers[@]}"; do
        if [[ -n "$csv_line" ]]; then
            csv_line+=","
        fi
        csv_line+=$(csv_escape_field "$header")
    done
    
    echo "$csv_line"
}

# Create CSV data row
create_csv_row() {
    local -a fields=("$@")
    local csv_line=""
    
    for field in "${fields[@]}"; do
        if [[ -n "$csv_line" ]]; then
            csv_line+=","
        fi
        csv_line+=$(csv_escape_field "$field")
    done
    
    echo "$csv_line"
}

# Convert JSON array to CSV
json_to_csv() {
    local json_file="$1"
    local output_file="$2"
    local -a headers=("${@:3}")
    
    if [[ ! -f "$json_file" ]]; then
        log_error "JSON file not found: $json_file"
        return 1
    fi
    
    log_debug "Converting JSON to CSV: $json_file -> $output_file"
    
    # Create JQ filter for headers if provided
    local jq_filter
    if [[ ${#headers[@]} -gt 0 ]]; then
        # Build JQ filter for specific headers
        local header_filter=""
        for header in "${headers[@]}"; do
            if [[ -n "$header_filter" ]]; then
                header_filter+=", "
            fi
            header_filter+=".$header // \"\""
        done
        
        jq_filter="[$header_filter]"
        
        # Write headers first
        create_csv_header "${headers[@]}" > "$output_file"
        
        # Add data rows
        jq -r ".[] | $jq_filter | @csv" "$json_file" >> "$output_file"
    else
        # Auto-detect headers from first object
        local first_obj_keys
        first_obj_keys=$(jq -r 'if length > 0 then .[0] | keys_unsorted | @csv else empty end' "$json_file")
        
        if [[ -n "$first_obj_keys" ]]; then
            echo "$first_obj_keys" > "$output_file"
            jq -r '.[] | [.[] // ""] | @csv' "$json_file" >> "$output_file"
        else
            log_warn "No data found in JSON file: $json_file"
            echo "" > "$output_file"
        fi
    fi
    
    local row_count
    row_count=$(tail -n +2 "$output_file" 2>/dev/null | wc -l || echo "0")
    log_debug "CSV export complete: $row_count data rows written"
}

# Validate CSV file format
validate_csv() {
    local csv_file="$1"
    
    if [[ ! -f "$csv_file" ]]; then
        log_error "CSV file not found: $csv_file"
        return 1
    fi
    
    # Check if file has content
    if [[ ! -s "$csv_file" ]]; then
        log_warn "CSV file is empty: $csv_file"
        return 1
    fi
    
    # Count lines
    local total_lines header_present data_lines
    total_lines=$(wc -l < "$csv_file")
    
    if [[ $total_lines -eq 0 ]]; then
        log_warn "CSV file has no lines: $csv_file"
        return 1
    fi
    
    # Assume first line is header
    header_present=1
    data_lines=$((total_lines - header_present))
    
    log_debug "CSV validation: $total_lines total lines, $data_lines data rows"
    
    # Basic format validation - check if first line has commas (likely header)
    local first_line
    first_line=$(head -n 1 "$csv_file")
    
    if [[ "$first_line" =~ , ]]; then
        log_debug "CSV appears to have valid header row"
        return 0
    else
        log_warn "CSV may not have proper header format: $csv_file"
        return 1
    fi
}

# Merge multiple CSV files with same structure
merge_csv_files() {
    local output_file="$1"
    shift
    local input_files=("$@")
    
    if [[ ${#input_files[@]} -eq 0 ]]; then
        log_error "No input files specified for CSV merge"
        return 1
    fi
    
    log_info "Merging ${#input_files[@]} CSV files into: $output_file"
    
    local first_file_processed=false
    
    for csv_file in "${input_files[@]}"; do
        if [[ ! -f "$csv_file" ]]; then
            log_warn "CSV file not found, skipping: $csv_file"
            continue
        fi
        
        if [[ ! -s "$csv_file" ]]; then
            log_warn "CSV file is empty, skipping: $csv_file"
            continue
        fi
        
        if [[ "$first_file_processed" == "false" ]]; then
            # Copy entire first file (including header)
            cp "$csv_file" "$output_file"
            first_file_processed=true
            log_debug "Added header and data from: $csv_file"
        else
            # Append data rows only (skip header)
            tail -n +2 "$csv_file" >> "$output_file"
            log_debug "Added data rows from: $csv_file"
        fi
    done
    
    if [[ "$first_file_processed" == "false" ]]; then
        log_error "No valid CSV files found to merge"
        return 1
    fi
    
    local total_rows
    total_rows=$(tail -n +2 "$output_file" | wc -l)
    log_success "CSV merge complete: $total_rows total data rows"
}

# Add summary row to CSV
add_csv_summary() {
    local csv_file="$1"
    local summary_label="$2"
    shift 2
    local -a summary_values=("$@")
    
    if [[ ! -f "$csv_file" ]]; then
        log_error "CSV file not found: $csv_file"
        return 1
    fi
    
    # Add separator line
    echo "" >> "$csv_file"
    
    # Create summary row
    local summary_row
    summary_row=$(create_csv_row "$summary_label" "${summary_values[@]}")
    echo "$summary_row" >> "$csv_file"
    
    log_debug "Summary row added to CSV: $csv_file"
}

# Convert tab-separated values to CSV
tsv_to_csv() {
    local tsv_file="$1"
    local csv_file="$2"
    
    if [[ ! -f "$tsv_file" ]]; then
        log_error "TSV file not found: $tsv_file"
        return 1
    fi
    
    log_debug "Converting TSV to CSV: $tsv_file -> $csv_file"
    
    # Convert tabs to commas and handle field escaping
    awk -F'\t' '
    {
        for(i=1; i<=NF; i++) {
            # Escape quotes and wrap fields containing special characters
            gsub(/"/, "\"\"", $i)
            if($i ~ /[,"\n\r]/ || $i ~ /^[ \t]/ || $i ~ /[ \t]$/) {
                $i = "\"" $i "\""
            }
        }
        # Rebuild line with commas
        line = $1
        for(i=2; i<=NF; i++) {
            line = line "," $i
        }
        print line
    }' "$tsv_file" > "$csv_file"
    
    validate_csv "$csv_file"
}

# Filter CSV by column value
filter_csv() {
    local input_csv="$1"
    local output_csv="$2"
    local column_name="$3"
    local filter_value="$4"
    
    if [[ ! -f "$input_csv" ]]; then
        log_error "Input CSV file not found: $input_csv"
        return 1
    fi
    
    log_debug "Filtering CSV by $column_name = $filter_value"
    
    # Get header line
    local header
    header=$(head -n 1 "$input_csv")
    echo "$header" > "$output_csv"
    
    # Find column index
    local column_index
    column_index=$(echo "$header" | tr ',' '\n' | grep -n "^$column_name$" | cut -d: -f1)
    
    if [[ -z "$column_index" ]]; then
        log_error "Column '$column_name' not found in CSV"
        return 1
    fi
    
    # Filter data rows
    tail -n +2 "$input_csv" | awk -F',' -v col="$column_index" -v val="$filter_value" '
        {
            gsub(/^"/, "", $col)
            gsub(/"$/, "", $col)
            if($col == val) print $0
        }
    ' >> "$output_csv"
    
    local filtered_count
    filtered_count=$(tail -n +2 "$output_csv" | wc -l)
    log_debug "Filtered CSV: $filtered_count rows match criteria"
}

# Export functions for use in other scripts
export -f csv_escape_field create_csv_header create_csv_row json_to_csv
export -f validate_csv merge_csv_files add_csv_summary tsv_to_csv filter_csv