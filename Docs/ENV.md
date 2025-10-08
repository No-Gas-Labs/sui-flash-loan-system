# Environment Setup & Dependencies

## System Requirements

### Core Dependencies
- **Sui CLI**: v1.34.0 or higher
- **Node.js**: v18.17.0 or higher
- **npm**: v9.0.0 or higher
- **TypeScript**: v5.0.0 or higher

### Sui Network Configuration
- **Testnet**: Recommended for development
- **Devnet**: For experimental features
- **Mainnet**: Production deployment

### Move Compiler Version
- **Move Language**: v1.6.0
- **Sui Framework**: Latest stable version

## Installation Steps

### 1. Install Sui CLI
```bash
# macOS
brew install sui

# Ubuntu/Debian
wget -qO- https://github.com/MystenLabs/sui/releases/latest/download/sui-linux-x86_64.tgz | tar -xz
sudo mv sui /usr/local/bin/

# Verify installation
sui --version
```

### 2. Setup Node.js Environment
```bash
# Install Node.js (if not already installed)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify installation
node --version
npm --version
```

### 3. Install Project Dependencies
```bash
cd Backend_TS
npm install

# Install global TypeScript
npm install -g typescript ts-node
```

### 4. Configure Wallet
```bash
# Create new wallet (testnet)
sui client new-address ed25519

# Switch to testnet
sui client switch --env testnet

# Get test tokens
sui client faucet
```

### 5. Environment Variables
Copy `.env.example` to `.env` and configure:
```bash
cp Deployment_Scripts/.env.example Deployment_Scripts/.env
```

## Development Setup

### 1. Compile Move Contracts
```bash
cd OnChain_SuiMove
sui move build
```

### 2. Run Tests
```bash
# Move tests
sui move test

# TypeScript tests
cd ../Backend_TS
npm test
```

### 3. Deploy Contracts
```bash
cd ../Deployment_Scripts
chmod +x deploy.sh
./deploy.sh
```

## Network Endpoints

### Testnet
- **RPC**: https://fullnode.testnet.sui.io:443
- **Faucet**: https://faucet.testnet.sui.io/gas
- **Explorer**: https://suiscan.xyz/testnet

### Devnet
- **RPC**: https://fullnode.devnet.sui.io:443
- **Faucet**: https://faucet.devnet.sui.io/gas
- **Explorer**: https://suiscan.xyz/devnet

### Mainnet
- **RPC**: https://fullnode.mainnet.sui.io:443
- **Explorer**: https://suiscan.xyz/mainnet

## Troubleshooting

### Common Issues
1. **"Module not found"**: Ensure all dependencies are installed
2. **"Insufficient gas"**: Use the faucet to get test tokens
3. **"Network timeout"**: Check internet connection and RPC endpoints
4. **"Move compilation failed"**: Verify Move.toml configuration

### Debug Commands
```bash
# Check Sui client configuration
sui client envs

# Check account balance
sui client gas

# Check network connectivity
curl -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"sui_getLatestCheckpointSequenceNumber","id":1}' \
  https://fullnode.testnet.sui.io:443
```