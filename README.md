# Azure Resource Auditing Solution

A comprehensive Azure resource auditing solution that provides enterprise-grade scripts for complete resource inventory, cost analysis, orphaned resource detection, and automated cleanup recommendations. The modular design ensures flexibility, safety, and production-ready deployment on WSL Ubuntu environments.

## 🚀 Features

- **Complete Resource Inventory**: Comprehensive listing of all Azure resources with metadata
- **Complete Resource Creation Analysis**: Tracks ALL resources (no time limits) with creator identification from tags and properties
- **Cost Analysis**: Resource-level cost breakdown with optimization recommendations
- **Orphaned Resource Detection**: Identifies unused resources for potential cleanup
- **Activity Log Tracking**: Resource creator identification and change tracking (last 30-90 days)
- **Governance Recommendations**: Automated tagging compliance analysis and policy suggestions
- **Safety-First Cleanup**: Automated cleanup recommendations with safety tagging
- **Enterprise Ready**: Production-grade logging, error handling, and safety features

## 📁 Directory Structure

```
azure-resource-auditing/
├── scripts/
│   ├── azure-audit-main.sh           # Main orchestration script
│   ├── inventory-collector.sh         # Resource inventory module
│   ├── cost-analyzer.sh              # Cost analysis module
│   ├── orphan-detector.sh            # Orphaned resource detection
│   ├── activity-tracker.sh           # Activity log analysis (last 30-90 days)
│   ├── complete-resource-tracker.sh   # Complete resource analysis (ALL resources)
│   └── cleanup-manager.sh            # Deletion recommendations & safety tagging
├── lib/
│   ├── azure-helpers.sh              # Azure CLI utilities
│   ├── logging.sh                    # Centralized logging system
│   ├── csv-export.sh                 # CSV formatting functions
│   └── validation.sh                 # Input validation
├── config/
│   ├── audit-config.env              # Main configuration
│   └── cost-thresholds.env           # Cost analysis settings
├── validate-setup.sh                 # Setup validation script
└── output/
    └── reports/                      # Generated CSV reports
```

## 🔧 Prerequisites

### System Requirements
- WSL Ubuntu 18.04+ or native Linux environment
- Bash 4.0 or later
- Azure CLI 2.50.0 or later
- jq (JSON processor)
- bc (basic calculator)

### Azure Requirements
- Azure subscription with appropriate permissions
- Authenticated Azure CLI session
- Resource Graph API access
- Cost Management API access (for detailed cost analysis)

### Installation

1. **Install Azure CLI** (if not already installed):
```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

2. **Install required dependencies**:
```bash
sudo apt update
sudo apt install jq bc
```

3. **Authenticate to Azure**:
```bash
az login
```

4. **Verify installation**:
```bash
az --version
jq --version
```

5. **Validate setup** (recommended):
```bash
# Navigate to the project directory
cd azure-resource-auditing

# Run the validation script to check everything is properly configured
./validate-setup.sh
```

## 📚 Documentation

### 📖 Complete User Manual
For comprehensive documentation, installation guides, troubleshooting, and advanced usage scenarios, see our **[Complete User Manual](USER_MANUAL.md)**.

The user manual includes:
- **Detailed Installation Guide**: Step-by-step setup instructions
- **Configuration Reference**: Complete parameter documentation
- **Module-Specific Usage**: In-depth guide for each auditing module
- **Advanced Workflows**: Multi-subscription auditing, automation scripts
- **Troubleshooting Guide**: Common issues and solutions
- **Best Practices**: Security, performance, and operational guidelines
- **FAQ**: Frequently asked questions and answers

## 🚦 Quick Start

### Setup Validation

Before running audits, validate your setup:

```bash
# Navigate to the project directory
cd azure-resource-auditing

# Run setup validation script
./validate-setup.sh
```

This validation script checks:
- ✅ Script execution permissions
- ✅ Azure CLI authentication status
- ✅ Resource Graph API access
- ✅ Activity Log API access
- ✅ Complete resource tracker functionality
- ✅ Required directories and configuration files

### Basic Usage

1. **Complete subscription audit**:
```bash
./scripts/azure-audit-main.sh --subscription "your-subscription-id"
```

2. **Audit specific resource groups**:
```bash
./scripts/azure-audit-main.sh \
    --subscription "your-subscription-id" \
    --resource-groups "rg1,rg2,rg3"
```

3. **Fast inventory without cost analysis**:
```bash
./scripts/azure-audit-main.sh \
    --subscription "your-subscription-id" \
    --no-cost-analysis \
    --no-activity-tracking
```

4. **Dry run for validation**:
```bash
./scripts/azure-audit-main.sh \
    --subscription "your-subscription-id" \
    --dry-run
```

> 💡 **Need more help?** Check the **[User Manual](USER_MANUAL.md)** for detailed instructions and advanced usage examples.

### Advanced Usage

**Custom configuration with parallel processing**:
```bash
./scripts/azure-audit-main.sh \
    --subscription "prod-subscription" \
    --config config/prod-audit.env \
    --parallel-jobs 10 \
    --output-dir /path/to/reports \
    --verbose
```

**Individual module execution**:
```bash
# Just resource inventory
./scripts/inventory-collector.sh \
    --subscription "your-subscription-id" \
    --output reports/inventory.csv

# Just orphan detection
./scripts/orphan-detector.sh \
    --subscription "your-subscription-id" \
    --output reports/orphans.csv

# Complete resource analysis (ALL resources with creator info)
./scripts/complete-resource-tracker.sh \
    --subscription "your-subscription-id" \
    --output reports/complete-resources.csv

# Activity log analysis (recent resources only - last 30-90 days)
./scripts/activity-tracker.sh \
    --subscription "your-subscription-id" \
    --output reports/activity.csv
```

## 📊 Output Reports

The auditing suite generates several CSV reports:

### Main Reports
- **`resource-inventory.csv`**: Complete resource listing with metadata
- **`cost-analysis.csv`**: Resource-level cost data and trends
- **`orphaned-resources.csv`**: Unused resources for cleanup
- **`activity-summary.csv`**: Resource creator tracking (last 30-90 days)
- **`complete-resources.csv`**: ALL resources with creator info (no time limits)
- **`cleanup-recommendations.csv`**: Deletion recommendations with safety checks

### Complete Resource Analysis Reports (NEW)
- **`complete-resources.csv`**: All resources with creation time, creator, tags
- **`complete-resources-analysis.txt`**: Detailed statistics and breakdowns
- **`complete-resources-by-creator.csv`**: Resources grouped by creator
- **`complete-resources-by-age.csv`**: Age distribution analysis
- **`complete-resources-activity-enhanced.csv`**: Enhanced with Activity Log data
- **`complete-resources-governance-recommendations.txt`**: Governance and compliance recommendations

### Detailed Reports
- **`resource-inventory-vm-status.csv`**: Detailed VM information
- **`cost-analysis-breakdown.csv`**: Cost breakdown by resource
- **`orphaned-resources-empty-rgs.csv`**: Empty resource groups
- **`activity-summary-creator-summary.csv`**: Creator activity patterns

### Summary Reports
- **`azure-audit-YYYYMMDD_HHMMSS-summary.txt`**: Overall audit summary
- **`cleanup-recommendations-summary.txt`**: Cleanup action summary

## ⚙️ Configuration

### Main Configuration (`config/audit-config.env`)

```bash
# Azure Configuration
AZURE_LOCATION="eastus"
TAG_ENVIRONMENT="production"

# Audit Scope
EXCLUDE_RESOURCE_TYPES="Microsoft.Insights/components"
RETENTION_DAYS=90

# Performance
MAX_PARALLEL_JOBS=10
QUERY_TIMEOUT_SECONDS=300

# Logging
LOG_LEVEL="INFO"  # DEBUG, INFO, WARN, ERROR

# Safety Features
CLEANUP_DRY_RUN="true"
ENABLE_SAFETY_TAGS="true"
REQUIRE_CONFIRMATION="true"
```

### Cost Thresholds (`config/cost-thresholds.env`)

```bash
# Monthly Cost Thresholds (USD)
COST_THRESHOLD_CRITICAL=1000
COST_THRESHOLD_HIGH=500
COST_THRESHOLD_MEDIUM=100
COST_THRESHOLD_LOW=10

# Resource-Specific Thresholds
VM_COST_THRESHOLD_HIGH=200
STORAGE_COST_THRESHOLD_HIGH=100
DATABASE_COST_THRESHOLD_HIGH=300
```

## 🛡️ Safety Features

### Built-in Safety Mechanisms
- **Dry Run Mode**: Preview operations without making changes
- **Safety Tagging**: Mark resources for cleanup with audit tags
- **Risk Assessment**: Categorize resources by deletion risk
- **Confirmation Prompts**: Require manual confirmation for destructive operations
- **Backup Recommendations**: Suggest backup strategies before deletion

### Safety Tags Applied
- `audit-candidate=true`: Marks resource for potential cleanup
- `audit-date=YYYY-MM-DD`: Date when resource was flagged
- `audit-risk=low|medium|high`: Risk level assessment

## 📋 Command Line Options

### Main Script (`azure-audit-main.sh`)

```
REQUIRED:
    -s, --subscription ID           Azure subscription ID or name

OPTIONAL:
    -g, --resource-groups GROUPS    Comma-separated list of resource groups
    -c, --config FILE              Configuration file path
    -o, --output-dir DIR           Output directory for reports
    -f, --format FORMAT            Output format: csv, json
    --no-cost-analysis             Skip cost analysis
    --no-orphan-detection          Skip orphaned resource detection
    --no-activity-tracking         Skip activity log analysis
    --dry-run                      Preview operations only
    --parallel-jobs N              Number of parallel operations
    -v, --verbose                  Enable verbose logging
    -h, --help                     Show help
```

### Individual Modules

Each module supports specific options:
- `--subscription`: Azure subscription ID (required)
- `--output`: Output file path (required)
- Module-specific options (see `--help` for each script)

## 🔍 Authentication Methods

The solution supports multiple Azure authentication methods:

1. **Interactive Login** (recommended for initial setup):
```bash
az login
```

2. **Service Principal** (for automation):
```bash
export AZURE_CLIENT_ID="your-client-id"
export AZURE_CLIENT_SECRET="your-client-secret"
export AZURE_TENANT_ID="your-tenant-id"
```

3. **Managed Identity** (automatically detected in Azure VMs)

> 📖 **For detailed authentication setup**: See [Authentication Methods](USER_MANUAL.md#authentication-methods) in the User Manual

## 🚨 Troubleshooting

### Setup Validation

First, run the validation script to identify common issues:

```bash
./validate-setup.sh
```

This will automatically check:
- Script permissions and executability
- Azure CLI authentication status
- Resource Graph API access
- Required directories and configuration files

### Common Issues

**Authentication Errors**:
```bash
# Check current authentication
az account show

# Re-authenticate if needed
az login --scope https://management.azure.com//.default
```

**Permission Issues**:
- Ensure you have `Reader` role on subscription
- For cost analysis: `Cost Management Reader` role required
- For cleanup operations: `Contributor` role required

**Resource Graph Errors**:
```bash
# Install/update Resource Graph extension
az extension add --name resource-graph
az extension update --name resource-graph
```

> 🔧 **For comprehensive troubleshooting**: See [Troubleshooting Guide](USER_MANUAL.md#troubleshooting) in the User Manual

### Debug Mode

Enable detailed logging for troubleshooting:
```bash
./scripts/azure-audit-main.sh \
    --subscription "your-subscription-id" \
    --verbose \
    2>&1 | tee audit-debug.log
```

## 📈 Performance Optimization

### Large Subscriptions

For subscriptions with thousands of resources:

1. **Increase parallel jobs**:
```bash
--parallel-jobs 20
```

2. **Use resource group filtering**:
```bash
--resource-groups "critical-rg1,critical-rg2"
```

3. **Skip expensive operations**:
```bash
--no-cost-analysis --no-activity-tracking
```

### Resource Graph Optimization

- Use specific resource type filters in configuration
- Leverage Resource Graph caching (enabled by default)
- Run during off-peak hours for better API performance

## 🔒 Security Considerations

### Data Security
- Reports may contain sensitive resource information
- Store reports in secure locations with appropriate access controls
- Consider encrypting report files for sensitive environments

### Access Controls
- Use least-privilege principle for Azure RBAC assignments
- Regularly rotate service principal credentials
- Audit who has access to run these scripts

### Compliance
- Review organizational policies before resource deletion
- Maintain audit trails of cleanup activities
- Ensure compliance with data retention requirements

## 🤝 Contributing

### Development Setup

1. **Clone and setup development environment**:
```bash
git clone <repository-url>
cd azure-resource-auditing
```

2. **Test individual modules**:
```bash
./scripts/inventory-collector.sh --help
```

3. **Run in dry-run mode for testing**:
```bash
./scripts/azure-audit-main.sh --subscription "test-sub" --dry-run
```

### Code Standards
- Follow existing shell scripting patterns
- Add comprehensive error handling
- Include detailed logging for all operations
- Test with multiple subscription types and sizes
- Update documentation for new features

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.

## ⚠️ Disclaimer

**IMPORTANT**: This tool can identify and recommend deletion of Azure resources. Always:
- Test in non-production environments first
- Backup critical data before any cleanup operations
- Review all recommendations with appropriate stakeholders
- Use dry-run mode to preview operations
- Have a rollback plan ready

The authors are not responsible for any data loss or service disruption resulting from the use of this tool.

## 📞 Support

For issues, questions, or contributions:
1. **First**: Check the **[Complete User Manual](USER_MANUAL.md)** for detailed troubleshooting
2. Review existing issues in the repository
3. Create a new issue with detailed information including:
   - Error messages and logs
   - Azure CLI version (`az --version`)
   - Subscription type and size
   - Steps to reproduce the issue

## 📚 Additional Resources

- **[Complete User Manual](USER_MANUAL.md)** - Comprehensive documentation and guides
- **[Configuration Reference](azure-resource-auditing/config/)** - Sample configuration files
- **[Script Documentation](azure-resource-auditing/scripts/)** - Individual module documentation

---

**Made with ❤️ for Azure FinOps teams everywhere**