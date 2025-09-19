# Lending Liquidity Guardian Hook

A Uniswap V4 hook that automatically protects lending protocols by executing liquidations and optimizing liquidity positions in real-time.

## What is this project?

The Lending Liquidity Guardian Hook is a smart contract that acts as a "guardian" for DeFi lending protocols. It watches over borrowers' health and automatically steps in when liquidations are needed, while also optimizing liquidity provider positions to maximize returns.

Think of it as an automated system that:
- **Monitors** borrower health across lending protocols like Aave and Compound
- **Executes** liquidations when borrowers become undercollateralized
- **Optimizes** liquidity provider positions based on market conditions
- **Protects** the lending ecosystem from bad debt

## Key Features

### 🔒 Automated Liquidation Protection
- **Real-time Monitoring**: Continuously watches borrower health factors
- **Multi-Protocol Support**: Works with Aave V3 and Compound V3
- **Instant Execution**: Automatically liquidates risky positions
- **Gas Efficient**: Optimized for low transaction costs

### 📊 Smart Liquidity Management
- **Dynamic Rebalancing**: Adjusts LP positions based on market volatility
- **Optimal Positioning**: Finds the best price ranges for maximum fees
- **Risk Management**: Protects against impermanent loss
- **Capital Efficiency**: Maximizes returns on liquidity provision

### 🛡️ Security & Control
- **Access Control**: Only authorized liquidators can execute liquidations
- **Emergency Pause**: Can be paused in case of emergencies
- **Reentrancy Protection**: Protected against common attack vectors
- **Owner Controls**: Administrative functions for protocol management

## How It Works

The hook integrates with Uniswap V4 pools and intercepts swaps to:

1. **Before Swap**: Check if any liquidations are needed
2. **Execute Liquidation**: If a borrower is unhealthy, liquidate their position
3. **After Swap**: Optimize LP positions based on new market conditions
4. **Monitor**: Continuously track price movements and volatility

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           LENDING LIQUIDITY GUARDIAN HOOK                      │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐            │
│  │   UNISWAP V4    │    │  LIQUIDATION    │    │  LP POSITION    │            │
│  │   INTEGRATION   │    │    ENGINE       │    │  OPTIMIZER      │            │
│  │                 │    │                 │    │                 │            │
│  │ • beforeSwap()  │    │ • Health Check  │    │ • Rebalancing   │            │
│  │ • afterSwap()   │    │ • Execute Liq.  │    │ • Tick Monitor  │            │
│  │ • Hook Manager  │    │ • Multi-Protocol│    │ • Volatility    │            │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘            │
│           │                       │                       │                    │
│           └───────────────────────┼───────────────────────┘                    │
│                                   │                                            │
│  ┌─────────────────────────────────┼─────────────────────────────────┐        │
│  │                    SECURITY & ACCESS CONTROL                      │        │
│  │                                                                    │        │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌───────────┐ │        │
│  │  │ Reentrancy  │  │   Access    │  │  Pausable   │  │ Emergency │ │        │
│  │  │ Protection  │  │  Control    │  │ Operations  │  │ Functions │ │        │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └───────────┘ │        │
│  └────────────────────────────────────────────────────────────────────┘        │
│                                   │                                            │
└───────────────────────────────────┼────────────────────────────────────────────┘
                                    │
            ┌───────────────────────┼───────────────────────┐
            │                EXTERNAL INTEGRATIONS                │
            │                                                      │
            │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
            │  │   AAVE V3   │  │ COMPOUND V3 │  │ CHAINLINK   │  │
            │  │             │  │             │  │  ORACLES    │  │
            │  │ • Pool      │  │ • Comet     │  │             │  │
            │  │ • Oracle    │  │ • Oracle    │  │ • Price     │  │
            │  │ • Liquidate │  │ • Liquidate │  │   Feeds     │  │
            │  └─────────────┘  └─────────────┘  └─────────────┘  │
            └──────────────────────────────────────────────────────┘
```

## Smart Contract Architecture

The system is built with a modular architecture:

### Core Components

| Component | Purpose | Key Functions |
|-----------|---------|---------------|
| **Hook Manager** | Uniswap V4 integration | `beforeSwap()`, `afterSwap()` |
| **Liquidation Engine** | Automated liquidations | Health monitoring, execution |
| **LP Optimizer** | Position management | Rebalancing, tick monitoring |
| **Security Module** | Protection & access | Reentrancy guards, permissions |
| **Protocol Adapters** | External integrations | Aave V3, Compound V3 interfaces |

### Data Flow

1. **Swap Initiated** → Hook intercepts via `beforeSwap()`
2. **Health Check** → Monitor borrower positions across protocols
3. **Liquidation** → Execute if health factor is below threshold
4. **Position Update** → Optimize LP positions via `afterSwap()`
5. **Monitoring** → Track volatility and adjust ranges

### Key Features

- **Multi-Protocol**: Supports multiple lending protocols simultaneously
- **Gas Optimized**: Efficient execution with minimal overhead
- **Secure**: Comprehensive security measures and access controls
- **Automated**: No manual intervention required for normal operations
- **Flexible**: Configurable parameters for different market conditions

## Getting Started

### Prerequisites
- [Foundry](https://getfoundry.sh/) for smart contract development
- Node.js 16+ for tooling
- Git for version control

### Quick Setup

```bash
# Clone the repository
git clone <repository-url>
cd lending-liquidity-guardian

# Install dependencies
forge install

# Run tests
forge test

# Deploy (testnet)
forge script script/DeployLendingLiquidityGuardianHook.s.sol --broadcast
```

## License

MIT License - see LICENSE file for details.

---

**Built for the DeFi ecosystem to provide automated protection and optimization for lending protocols.**
