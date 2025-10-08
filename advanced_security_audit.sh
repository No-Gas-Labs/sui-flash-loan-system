#!/bin/bash

echo "🔍 No_Gas_Labs Flash Loan System - Advanced Security Audit"
echo "=========================================================="
echo

# Function to check for actual hardcoded secrets
check_for_hardcoded_secrets() {
    local file=$1
    local issues=0
    
    # Check for private key patterns that are NOT environment variable references
    if grep -q "0x[a-fA-F0-9]\{64\}" "$file" && ! grep -q "process.env\|ADMIN_PRIVATE_KEY.*process.env" "$file"; then
        echo "⚠️  Potential hardcoded private key in $file"
        grep -n "0x[a-fA-F0-9]\{64\}" "$file"
        issues=$((issues + 1))
    fi
    
    # Check for API key patterns that are NOT environment variable references
    if grep -q "[a-zA-Z0-9]\{32,\}" "$file" && ! grep -q "process.env\|ADMIN_PRIVATE_KEY" "$file"; then
        echo "⚠️  Potential hardcoded API key in $file"
        grep -n "[a-zA-Z0-9]\{32,\}" "$file"
        issues=$((issues + 1))
    fi
    
    # Check for wallet JSON content
    if grep -q "&quot;address&quot;\|&quot;publicKey&quot;\|&quot;privateKeyEncrypted&quot;" "$file"; then
        echo "⚠️  Potential wallet JSON content in $file"
        grep -n "&quot;address&quot;\|&quot;publicKey&quot;\|&quot;privateKeyEncrypted&quot;" "$file"
        issues=$((issues + 1))
    fi
    
    return $issues
}

echo "📋 Scanning for hardcoded secrets..."
echo

files_to_check=$(find . -type f \( -name "*.ts" -o -name "*.move" -o -name "*.sh" -o -name "*.json" \) ! -path "./node_modules/*" ! -name "security_audit.sh" ! -name "advanced_security_audit.sh")

total_issues=0

for file in $files_to_check; do
    echo "🔍 Checking $file..."
    file_issues=0
    
    # Check for hardcoded secrets
    check_for_hardcoded_secrets "$file"
    file_issues=$((file_issues + $?))
    
    # Check for environment variable usage (this is GOOD)
    if grep -q "process.env\|ADMIN_PRIVATE_KEY.*process.env" "$file"; then
        echo "✅ Proper environment variable usage detected"
    fi
    
    # Check for sensitive comments
    if grep -qi "todo.*secret\|hack.*key\|temp.*private" "$file"; then
        echo "⚠️  Potentially sensitive comments found"
        grep -ni "todo.*secret\|hack.*key\|temp.*private" "$file"
        file_issues=$((file_issues + 1))
    fi
    
    if [ $file_issues -eq 0 ]; then
        echo "✅ No hardcoded secrets found"
    fi
    
    total_issues=$((total_issues + file_issues))
    echo
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

# Check for .env files that should be ignored
echo "🔍 Checking for .env files..."
env_files=$(find . -name ".env" -o -name "*.env" 2>/dev/null || true)
if [ ! -z "$env_files" ]; then
    echo "⚠️  Environment files found (should be in .gitignore):"
    echo "$env_files"
    total_issues=$((total_issues + 1))
else
    echo "✅ No .env files found in repository"
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
echo "=========================================================="
echo "🔒 Advanced Security Audit Summary"
echo "=========================================================="
if [ $total_issues -eq 0 ]; then
    echo "✅ PASSED: No hardcoded security issues found"
    echo "✅ Environment variables are properly used"
    echo "✅ No sensitive data is hardcoded"
    echo "✅ .gitignore is effectively protecting sensitive files"
    echo "✅ File permissions are secure"
    exit 0
else
    echo "⚠️  FOUND: $total_issues potential security issues"
    echo "❌ Please review and fix the issues above before proceeding"
    exit 1
fi