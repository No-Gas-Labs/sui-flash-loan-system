#!/bin/bash

# Flash Loan System Deployment Script for Sui
# This script handles building, testing, and deploying the flash loan system

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NETWORK="${SUI_NETWORK:-testnet}"
PACKAGE_DIR="flash_loan"
LOG_FILE="deployment.log"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a $LOG_FILE
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a $LOG_FILE
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a $LOG_FILE
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install dependencies
install_dependencies() {
    print_status "Installing dependencies..."
    
    # Check if sui CLI is installed
    if ! command_exists sui; then
        print_error "Sui CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Node.js is installed for TypeScript tests
    if ! command_exists node; then
        print_error "Node.js is not installed. Please install it first."
        exit 1
    fi
    
    # Check if npm is installed
    if ! command_exists npm; then
        print_error "npm is not installed. Please install it first."
        exit 1
    fi
    
    # Install TypeScript dependencies
    if [ -f "package.json" ]; then
        print_status "Installing TypeScript dependencies..."
        npm install
    else
        print_warning "No package.json found, skipping npm install"
    fi
}

# Function to build Move contracts
build_move() {
    print_status "Building Move contracts..."
    
    cd $PACKAGE_DIR
    
    # Clean previous build
    if [ -d "build" ]; then
        rm -rf build
    fi
    
    # Build the package
    sui move build
    
    if [ $? -ne 0 ]; then
        print_error "Move build failed"
        exit 1
    fi
    
    print_status "Move build completed successfully"
    cd ..
}

# Function to run Move tests
test_move() {
    print_status "Running Move tests..."
    
    cd $PACKAGE_DIR
    
    # Run all tests
    sui move test
    
    if [ $? -ne 0 ]; then
        print_error "Move tests failed"
        exit 1
    fi
    
    print_status "Move tests passed"
    cd ..
}

# Function to run TypeScript tests
test_typescript() {
    print_status "Running TypeScript tests..."
    
    if [ -f "package.json" ]; then
        npx jest
        
        if [ $? -ne 0 ]; then
            print_error "TypeScript tests failed"
            exit 1
        fi
        
        print_status "TypeScript tests passed"
    else
        print_warning "No package.json found, skipping TypeScript tests"
    fi
}

# Function to publish package
publish_package() {
    print_status "Publishing package to $NETWORK..."
    
    cd $PACKAGE_DIR
    
    # Check if we have a private key
    if [ -z "$PRIVATE_KEY" ]; then
        print_error "PRIVATE_KEY environment variable not set"
        exit 1
    fi
    
    # Publish the package
    sui client publish \
        --gas-budget 100000000 \
        --skip-dependency-verification
    
    if [ $? -ne 0 ]; then
        print_error "Package publish failed"
        exit 1
    fi
    
    print_status "Package published successfully"
    cd ..
}

# Function to create pool
create_pool() {
    print_status "Creating flash loan pool..."
    
    cd $PACKAGE_DIR
    
    # Check if we have the package ID
    if [ -z "$PACKAGE_ID" ]; then
        print_error "PACKAGE_ID not set. Run publish_package first or set PACKAGE_ID manually"
        exit 1
    fi
    
    # Check if we have initial liquidity amount
    if [ -z "$INITIAL_LIQUIDITY" ]; then
        INITIAL_LIQUIDITY=1000000000  # Default 1 SUI
        print_warning "INITIAL_LIQUIDITY not set, using default: $INITIAL_LIQUIDITY"
    fi
    
    # Check if we have fee rate
    if [ -z "$FEE_RATE" ]; then
        FEE_RATE=100  # Default 1%
        print_warning "FEE_RATE not set, using default: $FEE_RATE"
    fi
    
    # Check if we have max loan ratio
    if [ -z "$MAX_LOAN_RATIO" ]; then
        MAX_LOAN_RATIO=5000  # Default 50%
        print_warning "MAX_LOAN_RATIO not set, using default: $MAX_LOAN_RATIO"
    fi
    
    # Create pool
    sui client call \
        --function create_pool \
        --module pool_v2 \
        --package $PACKAGE_ID \
        --args $INITIAL_LIQUIDITY $FEE_RATE $MAX_LOAN_RATIO \
        --type-args 0x2::sui::SUI \
        --gas-budget 10000000
    
    if [ $? -ne 0 ]; then
        print_error "Pool creation failed"
        exit 1
    fi
    
    print_status "Pool created successfully"
    cd ..
}

# Function to deploy with full setup
full_deploy() {
    print_status "Starting full deployment process..."
    
    install_dependencies
    build_move
    test_move
    test_typescript
    
    print_status "All tests passed, proceeding with deployment..."
    
    if [ "$SKIP_PUBLISH" != "true" ]; then
        publish_package
    fi
    
    if [ "$SKIP_CREATE_POOL" != "true" ]; then
        create_pool
    fi
    
    print_status "Full deployment completed successfully!"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  install      Install dependencies"
    echo "  build        Build Move contracts"
    echo "  test         Run all tests (Move + TypeScript)"
    echo "  test-move    Run Move tests only"
    echo "  test-ts      Run TypeScript tests only"
    echo "  publish      Publish package to network"
    echo "  create-pool  Create flash loan pool"
    echo "  deploy       Full deployment (build, test, publish, create-pool)"
    echo ""
    echo "Environment Variables:"
    echo "  SUI_NETWORK     Network to deploy to (default: testnet)"
    echo "  PRIVATE_KEY     Private key for deployment"
    echo "  PACKAGE_ID      Package ID (if already published)"
    echo "  INITIAL_LIQUIDITY  Initial liquidity for pool (default: 1000000000)"
    echo "  FEE_RATE        Fee rate in basis points (default: 100)"
    echo "  MAX_LOAN_RATIO  Maximum loan ratio in basis points (default: 5000 = 50%)"
    echo ""
    echo "Examples:"
    echo "  PRIVATE_KEY=your_key_here $0 deploy"
    echo "  SUI_NETWORK=devnet PRIVATE_KEY=your_key_here $0 publish"
}

# Main execution
main() {
    # Create log file
    echo "Deployment started at $(date)" > $LOG_FILE
    
    case "${1:-deploy}" in
        install)
            install_dependencies
            ;;
        build)
            build_move
            ;;
        test)
            test_move
            test_typescript
            ;;
        test-move)
            test_move
            ;;
        test-ts)
            test_typescript
            ;;
        publish)
            publish_package
            ;;
        create-pool)
            create_pool
            ;;
        deploy)
            full_deploy
            ;;
        *)
            show_usage
            ;;
    esac
    
    echo "Deployment completed at $(date)" >> $LOG_FILE
}

# Run main function
main "$@"