# EV Charging Token System

A revolutionary blockchain-based pay-per-use electric vehicle charging platform built on the Stacks blockchain. This system enables transparent, decentralized management of EV charging stations with tokenized payments and secure access control.

## Overview

The EV Charging Token System transforms how electric vehicle owners interact with charging infrastructure by providing:

- **Decentralized Payments**: Use blockchain tokens for transparent charging payments
- **Usage-Based Billing**: Pay only for the energy you consume
- **Access Control**: Secure authentication for charging station usage
- **Real-time Tracking**: Monitor charging sessions and costs on-chain
- **Fair Pricing**: Dynamic pricing based on demand and energy costs

## Smart Contracts

This system consists of three integrated smart contracts:

### 1. Token Contract (`token.clar`)
- **SIP-010 Compliant**: Standard fungible token for payments
- **Minting & Burning**: Dynamic token supply management
- **Transfer Functions**: Secure token transfers between users
- **Balance Management**: Real-time balance tracking

### 2. Billing Contract (`billing.clar`)  
- **Usage Metering**: Track energy consumption per charging session
- **Dynamic Pricing**: Flexible rate management based on time and demand
- **Payment Processing**: Automated token-based payments
- **Session Management**: Complete charging session lifecycle
- **Revenue Distribution**: Fair distribution to station operators

### 3. Access Contract (`access.clar`)
- **Station Registration**: Register and manage charging stations
- **User Authentication**: Secure user verification system  
- **Permission Management**: Role-based access controls
- **Station Status**: Real-time availability and status tracking
- **Usage Authorization**: Validate user permissions before charging

## Key Features

- 🔋 **Pay-per-kWh**: Fair pricing based on actual energy consumption
- 🔐 **Secure Access**: Blockchain-based authentication and authorization
- 📊 **Transparent Billing**: All transactions recorded on-chain
- ⚡ **Real-time Updates**: Live status of charging sessions and stations
- 💰 **Token Economics**: Incentive mechanisms for station operators
- 🌍 **Decentralized**: No central authority controlling the network
- 📈 **Scalable**: Built to handle thousands of charging stations

## Technology Stack

- **Blockchain**: Stacks (Bitcoin Layer 2)
- **Smart Contracts**: Clarity Language  
- **Token Standard**: SIP-010 (Stacks Improvement Proposal)
- **Testing**: Clarinet Framework
- **Development**: TypeScript/JavaScript

## Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) - Stacks smart contract development tool
- [Node.js](https://nodejs.org/) v16+ - JavaScript runtime
- [Git](https://git-scm.com/) - Version control

### Installation

```bash
# Clone the repository
git clone https://github.com/chongmbami-ai/ev-charging-token.git
cd ev-charging-token

# Install dependencies
npm install

# Run contract checks
clarinet check

# Run tests
npm test
```

## Contract Architecture

```
EV Charging Token System
├── token.clar           # Payment token management
├── billing.clar         # Usage tracking & payments  
└── access.clar          # Authentication & permissions
```

## Usage Flow

1. **Station Registration**: Operators register charging stations via access contract
2. **User Authentication**: EV owners authenticate through access control
3. **Session Initiation**: Start charging session with permission validation
4. **Energy Metering**: Track kWh consumed during charging session
5. **Automatic Billing**: Calculate costs and process token payments
6. **Session Completion**: Finalize session and update all records

## Economic Model

- **Token Supply**: Dynamic based on network usage and demand
- **Pricing**: Market-driven rates with minimum/maximum bounds
- **Operator Revenue**: 80% to station operators, 20% to network maintenance
- **User Incentives**: Loyalty rewards for frequent users
- **Network Fees**: Minimal fees for contract execution

## Security Features

- **Access Control**: Multi-layered permission system
- **Input Validation**: Comprehensive parameter checking
- **Overflow Protection**: Safe arithmetic operations
- **Emergency Controls**: Admin functions for critical situations
- **Audit Trail**: Complete transaction history on-chain

## Project Structure

```
ev-charging-token/
├── contracts/
│   ├── token.clar       # EV Token contract
│   ├── billing.clar     # Billing and payment logic
│   └── access.clar      # Access control and authentication
├── tests/
│   ├── token.test.ts    # Token contract tests
│   ├── billing.test.ts  # Billing contract tests
│   └── access.test.ts   # Access contract tests
├── settings/            # Network configurations
├── Clarinet.toml        # Project configuration
└── README.md           # This file
```

## Contributing

We welcome contributions to the EV Charging Token System! Please read our contributing guidelines and submit pull requests for any improvements.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contact

For questions, suggestions, or collaboration opportunities, please reach out through GitHub issues or contact the development team.

---

*Building the future of decentralized EV charging infrastructure* ⚡🚗
