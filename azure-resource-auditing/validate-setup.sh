#!/bin/bash
# validate-setup.sh - Azure Resource Auditing Setup Validation Script

echo "=== Azure Resource Auditing Setup Validation ==="
echo

# Check file permissions
echo "🔍 Checking script permissions..."
echo
for script in scripts/*.sh lib/*.sh; do
    if [[ -x "$script" ]]; then
        echo "✓ $script - executable"
    else
        echo "✗ $script - not executable"
        echo "  Fix with: chmod +x $script"
    fi
done

echo
echo "🔍 Checking Azure CLI authentication..."
echo
if az account show --query '{name:name, id:id}' --output table 2>/dev/null; then
    echo "✓ Azure CLI authentication OK"
else
    echo "✗ Azure CLI authentication failed - please run 'az login'"
fi

echo
echo "🔍 Testing Resource Graph access..."
echo
if az graph query --query "Resources | limit 1" --output json >/dev/null 2>&1; then
    echo "✓ Resource Graph access OK"
else
    echo "⚠️  Resource Graph access failed - this may be due to permissions or subscription access"
    echo "  Required permissions: Reader role or resource.read permissions"
fi

echo
echo "🔍 Testing Activity Log access..."
echo
if az monitor activity-log list --max-items 1 --output json >/dev/null 2>&1; then
    echo "✓ Activity Log access OK"
else
    echo "⚠️  Activity Log access failed - may need additional permissions"
    echo "  Required permissions: Monitoring Reader or logs.read permissions"
fi

echo
echo "🔍 Checking required directories..."
echo
for dir in "output" "output/reports" "config"; do
    if [[ -d "$dir" ]]; then
        echo "✓ Directory $dir exists"
    else
        echo "⚠️  Directory $dir missing - creating it now..."
        mkdir -p "$dir"
        echo "✓ Directory $dir created"
    fi
done

echo
echo "🔍 Checking configuration files..."
echo
for config in "config/audit-config.env" "config/cost-thresholds.env"; do
    if [[ -f "$config" ]]; then
        echo "✓ Configuration file $config exists"
    else
        echo "⚠️  Configuration file $config missing"
    fi
done

echo
echo "🔍 Testing complete resource tracker functionality..."
echo
if [[ -f "scripts/complete-resource-tracker.sh" ]]; then
    if [[ -x "scripts/complete-resource-tracker.sh" ]]; then
        echo "✓ Complete resource tracker script exists and is executable"
        if ./scripts/complete-resource-tracker.sh 2>&1 | grep -q "Subscription ID required"; then
            echo "✓ Complete resource tracker parameter validation works"
        else
            echo "⚠️  Complete resource tracker parameter validation may have issues"
        fi
    else
        echo "✗ Complete resource tracker script not executable"
        echo "  Fix with: chmod +x scripts/complete-resource-tracker.sh"
    fi
else
    echo "✗ Complete resource tracker script missing"
    echo "  This script provides comprehensive resource analysis for ALL resources"
fi

echo
echo "=== Validation Complete ==="
echo "🚀 Ready to run Azure Resource Auditing!"
echo
echo "Available Analysis Modes:"
echo "• Activity Log Analysis: Last 30-90 days (limited by Azure log retention)"
echo "• Complete Resource Analysis: ALL existing resources (no time limit)"
echo "• Combined Analysis: Both activity logs + complete resource tracking"
echo
echo "Next steps:"
echo "1. Ensure you're logged into Azure: az login"
echo "2. Run a complete audit (includes new complete resource tracker):"
echo "   ./scripts/azure-audit-main.sh --subscription 189c3343-7f40-4beb-ad33-xxxxxxxx --verbose"
echo "3. Or run just the complete resource analysis:"
echo "   ./scripts/complete-resource-tracker.sh --subscription YOUR_SUBSCRIPTION_ID --output complete-resources.csv"
echo
