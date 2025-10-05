// Oracle configuration for different networks

export interface NetworkOracleConfig {
  network: string;
  chainId: bigint;
  oracles: {
    [asset: string]: {
      address: string;
      decimals: number;
      description: string;
      provider: string;
      stalenessThreshold: number; // seconds
    };
  };
}

// Sonic Mainnet Oracle Configuration
export const SONIC_MAINNET_ORACLES: NetworkOracleConfig = {
  network: "sonic-mainnet",
  chainId: 146n,
  oracles: {
    ETH: {
      address: "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419", // Chainlink ETH/USD - UPDATE WITH REAL SONIC ADDRESS
      decimals: 8,
      description: "ETH/USD Price Feed",
      provider: "Chainlink",
      stalenessThreshold: 3600 // 1 hour
    },
    BTC: {
      address: "0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c", // Chainlink BTC/USD - UPDATE WITH REAL SONIC ADDRESS
      decimals: 8,
      description: "BTC/USD Price Feed",
      provider: "Chainlink",
      stalenessThreshold: 3600 // 1 hour
    }
  }
};

// Somnia Mainnet Oracle Configuration (Protofire Oracle)
export const SOMNIA_MAINNET_ORACLES: NetworkOracleConfig = {
  network: "somnia-mainnet",
  chainId: 2648n, // Update with actual Somnia chain ID
  oracles: {
    ETH: {
      address: "0xeC25a820A6F194118ef8274216a7F225Da019526", // Protofire ETH/USD Proxy
      decimals: 8,
      description: "ETH/USD Price Feed",
      provider: "Protofire Oracle",
      stalenessThreshold: 3600 // 1 hour
    },
    BTC: {
      address: "0xa57d637618252669fD859B1F4C7bE6F52Bef67ed", // Protofire BTC/USD Proxy
      decimals: 8,
      description: "BTC/USD Price Feed",
      provider: "Protofire Oracle",
      stalenessThreshold: 3600 // 1 hour
    },
    USDC: {
      address: "0x843B6812E9Aa67b3773675d2836646BCbd216642", // Protofire USDC/USD Proxy
      decimals: 8,
      description: "USDC/USD Price Feed",
      provider: "Protofire Oracle",
      stalenessThreshold: 86400 // 24 hours (stable coin)
    }
  }
};

// Testnet configurations for development
export const SONIC_TESTNET_ORACLES: NetworkOracleConfig = {
  network: "sonic-testnet",
  chainId: 64165n, // Sonic testnet chain ID
  oracles: {
    ETH: {
      address: "0x0000000000000000000000000000000000000000", // Mock or testnet oracle
      decimals: 8,
      description: "ETH/USD Price Feed (Testnet)",
      provider: "Mock/Testnet",
      stalenessThreshold: 3600
    }
  }
};

export const SOMNIA_TESTNET_ORACLES: NetworkOracleConfig = {
  network: "somnia-testnet",
  chainId: 50311n, // Somnia testnet chain ID
  oracles: {
    ETH: {
      address: "0xd9132c1d762D432672493F640a63B758891B449e", // Protofire ETH/USD Testnet
      decimals: 8,
      description: "ETH/USD Price Feed (Testnet)",
      provider: "Protofire Oracle",
      stalenessThreshold: 3600
    },
    BTC: {
      address: "0x8CeE6c58b8CbD8afdEaF14e6fCA0876765e161fE", // Protofire BTC/USD Testnet
      decimals: 8,
      description: "BTC/USD Price Feed (Testnet)",
      provider: "Protofire Oracle",
      stalenessThreshold: 3600
    },
    USDC: {
      address: "0xa2515C9480e62B510065917136B08F3f7ad743B4", // Protofire USDC/USD Testnet
      decimals: 8,
      description: "USDC/USD Price Feed (Testnet)",
      provider: "Protofire Oracle",
      stalenessThreshold: 86400 // 24 hours (stable coin)
    }
  }
};

// Helper function to get oracle config by chain ID
export function getOracleConfig(chainId: bigint): NetworkOracleConfig | null {
  const configs = [
    SONIC_MAINNET_ORACLES,
    SOMNIA_MAINNET_ORACLES,
    SONIC_TESTNET_ORACLES,
    SOMNIA_TESTNET_ORACLES
  ];

  return configs.find(config => config.chainId === chainId) || null;
}

// Helper function to validate oracle addresses
export function validateOracleConfig(config: NetworkOracleConfig): boolean {
  for (const [asset, oracle] of Object.entries(config.oracles)) {
    if (oracle.address === "0x0000000000000000000000000000000000000000") {
      console.warn(`⚠️ Warning: ${asset} oracle address not configured for ${config.network}`);
      return false;
    }
  }
  return true;
}

// Asset addresses for different networks (ETH is zero address)
export const ASSET_ADDRESSES = {
  ETH: "0x0000000000000000000000000000000000000000",
  // Add other asset addresses as needed per network
};