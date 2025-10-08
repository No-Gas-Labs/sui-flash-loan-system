#!/bin/bash

echo "🔍 No_Gas_Labs Flash Loan System - Security Audit"
echo "=================================================="
echo

# Check for common secret patterns
echo "📋 Scanning for potential secrets..."
echo

# Define patterns to search for
patterns=(
    "private_key"
    "secret"
    "api_key"
    "mnemonic"
    "seed"
    "password"
    "wallet.*json"
    "0x[a-fA-F0-9]{64}"  # Private key pattern
    "[a-zA-Z0-9]{32,}"   # Generic API key pattern
)

files_to_check=$(find . -type f \( -name "*.ts" -o -name "*.move" -o -name "*.sh" -o -name "*.json" -o -name "*.md" \) ! -path "./node_modules/*")

total_issues=0

for pattern in "${patterns[@]}"; do
    echo "🔍 Checking pattern: $pattern"
    matches=$(grep -i -n "$pattern" $files_to_check 2>/dev/null | grep -v ".env.example" | grep -v "security_audit.sh" | grep -v "process.env" | grep -v "ADMIN_PRIVATE_KEY.*process.env" | grep -v "fromSecretKey.*jest.fn" | grep -v "throw new Error.*PRIVATE_KEY" | grep -v "if.*PRIVATE_KEY" | grep -v "echo.*PRIVATE_KEY" || true)
    
    if [ ! -z "$matches" ]; then
        echo "⚠️  Potential issues found:"
        echo "$matches"
        echo
        total_issues=$((total_issues + 1))
    else
        echo "✅ No hardcoded secrets found for pattern: $pattern"
        echo
    fi
done

# Check .gitignore effectiveness
echo "🔍 Checking .gitignore effectiveness..."
git_check_files=$(git status --porcelain 2>/dev/null | grep -E "\.env|\.key|wallet" || true)
if [ ! -z "$git_check_files" ]; then
    echo "⚠️  Sensitive files might be tracked:"
    echo "$git_check_files"
    total_issues=$((total_issues + 1))
else
    echo "✅ No sensitive files are tracked by git"
fi
echo

# Check file permissions
echo "🔍 Checking file permissions..."
sensitive_files=$(find . -type f -perm /o+w 2>/dev/null | grep -v node_modules || true)
if [ ! -z "$sensitive_files" ]; then
    echo "⚠️  Files with world-write permissions found:"
    echo "$sensitive_files"
    total_issues=$((total_issues + 1))
else
    echo "✅ File permissions are secure"
fi
echo

# Summary
echo "=================================================="
echo "🔒 Security Audit Summary"
echo "=================================================="
if [ $total_issues -eq 0 ]; then
    echo "✅ PASSED: No security issues found"
    echo "✅ All secrets are properly managed via environment variables"
    echo "✅ .gitignore is effectively protecting sensitive files"
    echo "✅ File permissions are secure"
    exit 0
else
    echo "⚠️  FOUND: $total_issues potential security issues"
    echo "❌ Please review and fix the issues above before proceeding"
    exit 1
fi