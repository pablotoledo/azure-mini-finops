# Azure Resource Auditing Solution - Complete User Manual

## 📋 Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Installation Guide](#installation-guide)
4. [Configuration Setup](#configuration-setup)
5. [Authentication Methods](#authentication-methods)
6. [Step-by-Step Usage Guide](#step-by-step-usage-guide)
7. [Module-Specific Usage](#module-specific-usage)
8. [Output Interpretation](#output-interpretation)
9. [Advanced Workflows](#advanced-workflows)
10. [Troubleshooting](#troubleshooting)
11. [Best Practices](#best-practices)
12. [FAQ](#faq)

---

## 🎯 Overview

The Azure Resource Auditing Solution is a comprehensive suite of Bash scripts designed to perform enterprise-grade auditing of Azure subscriptions. It provides complete visibility into your Azure resources, identifies cost optimization opportunities, detects orphaned resources, and generates actionable cleanup recommendations.

### Key Capabilities

- **Complete Resource Inventory**: Comprehensive listing of all resources with detailed metadata
- **Cost Analysis**: Resource-level cost breakdown with optimization recommendations
- **Orphaned Resource Detection**: Identification of unused resources for potential cleanup
- **Creator Tracking**: Resource ownership identification through Activity Log analysis  
- **Safety Management**: Automated tagging and staged deletion workflows
- **Parallel Processing**: High-performance execution with configurable concurrency

### Architecture

```
azure-resource-auditing/
├── scripts/              # Main execution scripts
├── lib/                  # Shared utility libraries  
├── config/              # Configuration files
└── output/              # Generated reports and logs
    └── reports/         # CSV audit reports
```

---

## 🔧 Prerequisites

### System Requirements

- **Operating System**: Ubuntu 20.04+ (including WSL2)
- **Memory**: Minimum 2GB RAM (4GB recommended for large subscriptions)
- **Disk Space**: 1GB free space for temporary files and reports
- **Network**: Internet connectivity for Azure API access

### Required Software

| Tool | Version | Purpose |
|------|---------|---------|
| Azure CLI | 2.50+ | Azure API interactions |
| jq | 1.6+ | JSON processing |
| bc | 1.07+ | Mathematical calculations |
| curl | 7.68+ | HTTP requests |
| bash | 5.0+ | Script execution |

### Azure Permissions Required

Your Azure identity must have the following permissions:

- **Reader** role at subscription level (minimum)
- **Cost Management Reader** for cost analysis
- **Log Analytics Reader** for activity log access (if using Log Analytics)

---

## 🚀 Installation Guide

### Step 1: Download and Extract

```bash
# Create project directory
mkdir -p ~/azure-resource-auditing
cd ~/azure-resource-auditing

# Download the solution (assuming you have the files)
# Extract all files maintaining directory structure
```

### Step 2: Install Prerequisites

```bash
# Update package lists
sudo apt update

# Install required packages
sudo apt install -y curl jq bc git

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

### Step 3: Verify Installation

```bash
# Verify all components
az version
jq --version
bc --version

# Test Azure connectivity (requires authentication)
az account list --output table
```

### Step 4: Set Permissions

```bash
# Make all scripts executable
find scripts/ -name "*.sh" -exec chmod +x {} \;
find lib/ -name "*.sh" -exec chmod +x {} \;
```

---

## ⚙️ Configuration Setup

### Basic Configuration

The solution uses two main configuration files located in the `config/` directory:

1. **Main Configuration** (`config/audit-config.env`)
2. **Cost Thresholds** (`config/cost-thresholds.env`)

#### Main Configuration Settings

Key configuration parameters in `audit-config.env`:

```bash
# Basic settings
AZURE_LOCATION="eastus"
LOG_LEVEL="INFO"

# Enable/disable modules
ENABLE_COST_ANALYSIS="true"
ENABLE_ORPHAN_DETECTION="true" 
ENABLE_ACTIVITY_TRACKING="true"

# Performance settings
MAX_PARALLEL_JOBS="10"
PARALLEL_JOBS="5"

# Safety settings
CLEANUP_DRY_RUN="true"
ENABLE_SAFETY_TAGS="true"
REQUIRE_CONFIRMATION="true"
```

### Advanced Configuration Options

| Parameter | Description | Default | Values |
|-----------|-------------|---------|---------|
| `LOG_LEVEL` | Logging verbosity | `INFO` | `DEBUG`, `INFO`, `WARN`, `ERROR` |
| `MAX_PARALLEL_JOBS` | Maximum concurrent operations | `10` | `1-10` |
| `COST_ANALYSIS_PERIOD` | Cost analysis window | `MonthToDate` | `MonthToDate`, `TheLastMonth` |
| `RETENTION_DAYS` | Activity log lookback | `90` | `1-90` |
| `ENABLE_SAFETY_TAGS` | Auto-tag resources for safety | `true` | `true`, `false` |

### Cost Thresholds Configuration

Edit `config/cost-thresholds.env` to customize cost analysis:

```bash
# Cost classification thresholds (USD monthly)
COST_THRESHOLD_CRITICAL=1000
COST_THRESHOLD_HIGH=500
COST_THRESHOLD_MEDIUM=100
COST_THRESHOLD_LOW=10

# Resource-specific thresholds
VM_COST_THRESHOLD_HIGH=200
STORAGE_COST_THRESHOLD_HIGH=100
DATABASE_COST_THRESHOLD_HIGH=300
```

---

## 🔐 Authentication Methods

### Method 1: Interactive Login (Recommended for Testing)

```bash
# Login interactively
az login

# Verify authentication
az account show
```

### Method 2: Service Principal (Recommended for Automation)

```bash
# Set environment variables
export AZURE_CLIENT_ID="your-client-id"
export AZURE_CLIENT_SECRET="your-client-secret" 
export AZURE_TENANT_ID="your-tenant-id"

# The script will automatically use service principal auth
```

### Method 3: Managed Identity (For Azure VMs)

```bash
# Enable managed identity on the VM
# The script will auto-detect and use managed identity
az login --identity
```

### Verify Permissions

```bash
# Check subscription access
az account list --output table

# Test required permissions
az graph query --query "Resources | limit 1"
az costmanagement query --help
az monitor activity-log list --max-events 1
```

---

## 📖 Step-by-Step Usage Guide

### Quick Start (5 minutes)

1. **Set your subscription**:
```bash
# List available subscriptions
az account list --output table

# Set target subscription
export SUBSCRIPTION_ID="12345678-1234-1234-1234-123456789012"
```

2. **Run complete audit**:
```bash
./scripts/azure-audit-main.sh --subscription "$SUBSCRIPTION_ID"
```

3. **Review results**:
```bash
ls -la output/reports/
```

### Detailed Workflow

#### Stage 1: Environment Preparation

```bash
# 1. Authenticate to Azure
az login

# 2. Verify subscription access
az account show

# 3. Set target subscription
az account set --subscription "your-subscription-id"

# 4. Test permissions
az graph query --query "Resources | limit 1" --output table
```

#### Stage 2: Configuration Validation

```bash
# 1. Review configuration
cat config/audit-config.env

# 2. Test with dry run
./scripts/azure-audit-main.sh \
  --subscription "$SUBSCRIPTION_ID" \
  --dry-run \
  --verbose
```

#### Stage 3: Execute Full Audit

```bash
# Complete audit with all modules
./scripts/azure-audit-main.sh \
  --subscription "$SUBSCRIPTION_ID" \
  --output-dir "./output/reports" \
  --config "./config/audit-config.env"
```

#### Stage 4: Review Results

```bash
# List generated reports
ls -la output/reports/

# Preview inventory report
head -20 output/reports/azure-audit-*-inventory.csv

# Check for orphaned resources
wc -l output/reports/azure-audit-*-orphans.csv
```

#### Stage 5: Analyze Findings

```bash
# Review cost analysis
cat output/reports/azure-audit-*-costs-breakdown.csv

# Check cleanup recommendations
cat output/reports/azure-audit-*-cleanup.csv

# Review summary
cat output/reports/azure-audit-*-summary.txt
```

---

## 🔍 Module-Specific Usage

### Resource Inventory Module

**Purpose**: Collect comprehensive resource listing

```bash
# Run inventory only
./scripts/inventory-collector.sh \
  --subscription "$SUBSCRIPTION_ID" \
  --output "./inventory-report.csv"

# With resource group filter
./scripts/inventory-collector.sh \
  --subscription "$SUBSCRIPTION_ID" \
  --resource-groups "rg-prod,rg-dev" \
  --output "./filtered-inventory.csv"
```

**Output Columns**:
- SubscriptionName, SubscriptionId
- ResourceGroup, Name, Type, Location
- PowerState, ProvisioningState
- CreationTime, SkuName, Size, Tags

### Cost Analysis Module

**Purpose**: Resource-level cost breakdown

```bash
# Current month costs
./scripts/cost-analyzer.sh \
  --subscription "$SUBSCRIPTION_ID" \
  --output "./cost-report.csv"

# Custom time period
./scripts/cost-analyzer.sh \
  --subscription "$SUBSCRIPTION_ID" \
  --time-period "TheLastMonth" \
  --output "./last-month-costs.csv"
```

**Output Files**:
- `cost-report.csv`: Daily cost breakdown by resource
- `cost-report-breakdown.csv`: Aggregated costs by resource  
- `cost-report-recommendations.csv`: Azure Advisor recommendations

### Orphaned Resource Detection

**Purpose**: Identify unused resources for cleanup

```bash
# Detect all orphaned resources
./scripts/orphan-detector.sh \
  --subscription "$SUBSCRIPTION_ID" \
  --output "./orphans-report.csv"
```

**Detected Resource Types**:
- Unattached managed disks
- Unassociated public IP addresses
- Unused network security groups
- Orphaned network interfaces
- Unused load balancers
- Empty resource groups

### Activity Log Analysis

**Purpose**: Track resource creators and changes

```bash
# Analyze last 30 days
./scripts/activity-tracker.sh \
  --subscription "$SUBSCRIPTION_ID" \
  --output "./activity-report.csv"

# Custom time window
./scripts/activity-tracker.sh \
  --subscription "$SUBSCRIPTION_ID" \
  --days 60 \
  --output "./activity-60days.csv"
```

**Output Files**:
- `activity-report.csv`: Detailed activity log events
- `activity-report-creators.csv`: Resource creator summary

### Cleanup Management

**Purpose**: Generate safe deletion recommendations

```bash
# Generate recommendations
./scripts/cleanup-manager.sh \
  --subscription "$SUBSCRIPTION_ID" \
  --input-dir "./output/reports" \
  --output "./cleanup-recommendations.csv" \
  --report-date "20241215_143022"

# With automatic safety tagging
./scripts/cleanup-manager.sh \
  --subscription "$SUBSCRIPTION_ID" \
  --input-dir "./output/reports" \
  --output "./cleanup-recommendations.csv" \
  --report-date "20241215_143022" \
  --auto-tag
```

---

## 📊 Output Interpretation

### Report Types and Structure

#### 1. Resource Inventory Report
```csv
SubscriptionName,SubscriptionId,ResourceGroup,Name,Type,Location,PowerState,ProvisioningState,CreationTime,SkuName,Size,Tags
Production,12345...,rg-web,vm-web01,Microsoft.Compute/virtualMachines,eastus,PowerState/running,Succeeded,2024-01-15T10:30:00Z,Standard_D2s_v3,Standard_D2s_v3,Environment=Production;Owner=TeamA
```

#### 2. Cost Analysis Report  
```csv
Date,ResourceId,ResourceType,ResourceLocation,ChargeType,Cost
2024-12-01,/subscriptions/.../vm-web01,Microsoft.Compute/virtualMachines,eastus,Usage,45.67
```

#### 3. Orphaned Resources Report
```csv
SubscriptionId,ResourceGroup,Name,Type,Location,OrphanType,CostImpact,Details,Tags
12345...,rg-storage,disk-orphaned-01,Microsoft.Compute/disks,eastus,Unattached Disk,High,Size: 512GB; SKU: Premium_LRS,""
```

#### 4. Cleanup Recommendations Report
```csv
ResourceGroup,ResourceName,ResourceType,RecommendationType,Priority,EstimatedMonthlySavings,SafetyRating,RecommendedAction,ValidationRequired
rg-storage,disk-orphaned-01,Microsoft.Compute/disks,Orphaned Resource,1-Critical,$50-500,Low,Create snapshot then delete disk,Yes
```

### Understanding Priority Levels

| Priority | Description | Action Timeframe | Review Required |
|----------|-------------|------------------|-----------------|
| 1-Critical | High-cost orphaned resources | Within 7 days | Mandatory |
| 2-High | Medium-cost optimization opportunities | Within 14 days | Recommended |
| 3-Low | Low-impact cleanup items | Within 30 days | Optional |

### Safety Ratings Explained

- **High**: Safe to delete after basic validation
- **Medium**: Requires careful review before deletion  
- **Low**: Needs comprehensive validation (snapshots, backups)

---

## 🔄 Advanced Workflows

### Workflow 1: Monthly Cost Optimization Review

```bash
#!/bin/bash
# Monthly optimization workflow

SUBSCRIPTION="your-subscription-id"
REPORT_DATE=$(date +%Y%m%d_%H%M%S)

echo "Starting monthly cost optimization review..."

# 1. Generate comprehensive audit
./scripts/azure-audit-main.sh \
  --subscription "$SUBSCRIPTION" \
  --config "./config/audit-config.env"

# 2. Extract high-cost orphaned resources
tail -n +2 "./output/reports/azure-audit-${REPORT_DATE}-cleanup.csv" | \
awk -F',' '$5 == "1-Critical" {print}' > high-priority-cleanup.csv

# 3. Generate executive summary
echo "High-Priority Cleanup Opportunities:" > executive-summary.txt
echo "====================================" >> executive-summary.txt
wc -l high-priority-cleanup.csv >> executive-summary.txt
echo "" >> executive-summary.txt

# 4. Send results for review
echo "Review high-priority-cleanup.csv and executive-summary.txt"
```

### Workflow 2: Automated Safety Tagging

```bash
#!/bin/bash
# Safety tagging workflow

SUBSCRIPTION="your-subscription-id"

# 1. Detect orphaned resources
./scripts/orphan-detector.sh \
  --subscription "$SUBSCRIPTION" \
  --output "./orphans-$(date +%Y%m%d).csv"

# 2. Apply safety tags to orphaned resources
./scripts/cleanup-manager.sh \
  --subscription "$SUBSCRIPTION" \
  --input-dir "./output/reports" \
  --output "./cleanup-plan.csv" \
  --auto-tag \
  --report-date "$(date +%Y%m%d_%H%M%S)"

# 3. Generate deletion script for review
echo "Safety tags applied. Review cleanup-plan-delete-script.sh before execution."
```

### Workflow 3: Multi-Subscription Audit

```bash
#!/bin/bash
# Multi-subscription audit workflow

SUBSCRIPTIONS=("sub1-id" "sub2-id" "sub3-id")

for sub in "${SUBSCRIPTIONS[@]}"; do
    echo "Processing subscription: $sub"
    
    ./scripts/azure-audit-main.sh \
      --subscription "$sub" \
      --output-dir "./output/reports/$sub"
      
    echo "Completed: $sub"
done

# Consolidate results
echo "Consolidating multi-subscription results..."
find ./output/reports -name "*-inventory.csv" -exec cat {} \; > consolidated-inventory.csv
```

---

## 🔧 Troubleshooting

### Common Issues and Solutions

#### Issue 1: Authentication Failures

**Symptoms**:
```
ERROR: Please run 'az login' to setup account.
```

**Solutions**:
```bash
# Clear cached credentials
az logout
az cache purge

# Re-authenticate
az login

# Verify authentication
az account show
```

#### Issue 2: Permission Denied Errors

**Symptoms**:
```
ERROR: The client does not have authorization to perform action 'microsoft.costmanagement/query/usage/action'
```

**Solutions**:
1. Verify required permissions:
```bash
# Check current role assignments
az role assignment list --assignee $(az account show --query user.name -o tsv) --output table
```

2. Request additional permissions from subscription owner:
   - Cost Management Reader
   - Reader (minimum)

#### Issue 3: Large Dataset Timeouts

**Symptoms**:
```
ERROR: Request timeout or partial results
```

**Solutions**:
```bash
# Reduce parallel jobs
export MAX_PARALLEL_JOBS=2

# Filter by resource groups
./scripts/azure-audit-main.sh \
  --subscription "$SUBSCRIPTION_ID" \
  --resource-groups "rg1,rg2"

# Disable heavy modules temporarily  
./scripts/azure-audit-main.sh \
  --subscription "$SUBSCRIPTION_ID" \
  --no-cost-analysis \
  --no-activity-tracking
```

#### Issue 4: Missing Dependencies

**Symptoms**:
```
command not found: jq
```

**Solutions**:
```bash
# Install missing dependencies
sudo apt update
sudo apt install -y jq bc curl

# Verify installation
which jq bc curl
```

#### Issue 5: CSV Formatting Issues

**Symptoms**:
- Malformed CSV output
- Special characters breaking parsing

**Solutions**:
```bash
# Check file encoding
file output/reports/*.csv

# Verify CSV structure
head -5 output/reports/azure-audit-*-inventory.csv

# Fix encoding if needed
iconv -f UTF-8 -t UTF-8//IGNORE input.csv > output.csv
```

### Debug Mode

Enable detailed debugging:

```bash
# Set debug environment
export LOG_LEVEL="DEBUG"

# Run with verbose output
./scripts/azure-audit-main.sh \
  --subscription "$SUBSCRIPTION_ID" \
  --verbose 2>&1 | tee debug.log
```

### Log Analysis

```bash
# Check general logs
tail -f /tmp/azure-audit.log

# Find error patterns
grep -i error /tmp/azure-audit.log

# Check Azure CLI logs
cat ~/.azure/logs/azure-cli.log
```

---

## ✅ Best Practices

### Security Best Practices

1. **Use Service Principal for Automation**:
```bash
# Create dedicated service principal
az ad sp create-for-rbac --name "azure-audit-sp" --role Reader

# Store credentials securely
# Never commit credentials to version control
```

2. **Implement Least Privilege**:
   - Use Reader role for basic auditing
   - Add Cost Management Reader only when needed
   - Avoid Contributor/Owner roles

3. **Secure Configuration**:
```bash
# Set restrictive permissions on config files
chmod 600 config/*.env

# Use environment variables for sensitive data
export AZURE_CLIENT_SECRET="secure-secret"
```

### Performance Optimization

1. **Resource Group Filtering**:
```bash
# Audit only specific resource groups
./scripts/azure-audit-main.sh \
  --subscription "$SUBSCRIPTION_ID" \
  --resource-groups "critical-rg1,critical-rg2"
```

2. **Parallel Processing Tuning**:
```bash
# Adjust based on system resources
export MAX_PARALLEL_JOBS=3  # For smaller systems
export MAX_PARALLEL_JOBS=8  # For larger systems
```

3. **Selective Module Execution**:
```bash
# Skip expensive operations for quick inventory
./scripts/azure-audit-main.sh \
  --subscription "$SUBSCRIPTION_ID" \
  --no-cost-analysis \
  --no-activity-tracking
```

### Data Management

1. **Regular Cleanup**:
```bash
# Clean old reports (keep last 30 days)
find output/reports -name "*.csv" -mtime +30 -delete
```

2. **Backup Important Reports**:
```bash
# Backup critical audit results
cp output/reports/azure-audit-*-cleanup.csv backups/
```

3. **Version Control**:
```bash
# Track configuration changes
git add config/
git commit -m "Updated audit configuration"
```

---

## ❓ FAQ

### General Questions

**Q: How long does a complete audit take?**  
A: Depends on subscription size:
- Small (< 100 resources): 2-5 minutes
- Medium (100-1000 resources): 5-15 minutes  
- Large (1000+ resources): 15-60 minutes

**Q: Can I run this in Azure Cloud Shell?**  
A: Yes, all prerequisites are pre-installed in Azure Cloud Shell.

**Q: Does this modify any resources?**  
A: By default, no. Only when using `--auto-tag` are resources modified with metadata tags.

**Q: How accurate are the cost estimates?**  
A: Cost data comes directly from Azure Cost Management API and reflects actual billing data.

### Technical Questions

**Q: Why use Azure Resource Graph instead of az resource list?**  
A: Resource Graph is significantly faster for large-scale queries and provides more comprehensive metadata.

**Q: Can I customize the orphaned resource detection logic?**  
A: Yes, modify the KQL queries in `orphan-detector.sh` to match your requirements.

**Q: How do I handle subscriptions with thousands of resources?**  
A: Use resource group filtering and adjust parallel processing settings. Consider running modules separately.

**Q: What if Activity Log data is older than 90 days?**  
A: Configure Log Analytics workspace export for longer retention, or the creator information will not be available.

### Troubleshooting Questions

**Q: Getting "Insufficient permissions" errors?**  
A: Verify you have Reader role at subscription level and Cost Management Reader for cost analysis.

**Q: CSV files are empty or malformed?**  
A: Check Azure CLI version (requires 2.50+) and verify jq is properly installed.

**Q: Script hangs during execution?**  
A: Likely a large dataset timeout. Try reducing `MAX_PARALLEL_JOBS` or use resource group filtering.

---

## 📞 Support and Contribution

### Getting Help

1. **Check logs**: `/tmp/azure-audit.log`
2. **Enable debug mode**: `export LOG_LEVEL="DEBUG"`
3. **Review this documentation**: Most issues are covered in troubleshooting
4. **Check Azure CLI documentation**: [https://docs.microsoft.com/cli/azure/](https://docs.microsoft.com/cli/azure/)

### Contributing

1. **Report Issues**: Document bugs with full error messages and environment details
2. **Feature Requests**: Describe use case and expected behavior
3. **Code Contributions**: Follow existing patterns and include tests

### Version History

- **v1.0**: Initial release with basic auditing
- **v2.0**: Added cost analysis and orphan detection  
- **v2.1**: Enhanced safety mechanisms and multi-subscription support

---

## 📄 License and Disclaimer

This tool is provided as-is for Azure resource management. Always review recommendations before taking any deletion actions. Test in non-production environments first.

**Important**: This tool can identify resources for deletion but cannot determine business criticality. Always validate with stakeholders before removing any resources.

---

*Last Updated: December 2024*  
*Compatible with: Azure CLI 2.50+, Ubuntu 20.04+, WSL2*