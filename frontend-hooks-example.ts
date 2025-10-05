// Example React hooks for frontend integration
import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseEther, formatEther, Address } from 'viem';
import { CONTRACT_ADDRESSES, BORROWER_OPERATIONS_ABI, TROVE_MANAGER_ABI, STABILITY_POOL_ABI, USDF_ABI } from './contract-abis';

// Hook to get user's trove data
export function useTrove(userAddress: Address, asset: Address = '0x0000000000000000000000000000000000000000') {
  const { data: troveData, isLoading, refetch } = useReadContract({
    address: CONTRACT_ADDRESSES.troveManager,
    abi: TROVE_MANAGER_ABI,
    functionName: 'getTroveDebtAndColl',
    args: [userAddress, asset],
  });

  const { data: troveStatus } = useReadContract({
    address: CONTRACT_ADDRESSES.troveManager,
    abi: TROVE_MANAGER_ABI,
    functionName: 'getTroveStatus',
    args: [userAddress, asset],
  });

  const { data: currentICR } = useReadContract({
    address: CONTRACT_ADDRESSES.troveManager,
    abi: TROVE_MANAGER_ABI,
    functionName: 'getCurrentICR',
    args: [userAddress, asset],
  });

  return {
    debt: troveData?.[0] || 0n,
    collateral: troveData?.[1] || 0n,
    status: troveStatus || 0,
    icr: currentICR || 0n,
    isLoading,
    refetch,
    exists: troveStatus && troveStatus > 0,
    isActive: troveStatus === 1
  };
}

// Hook to get ETH price from oracle
export function useETHPrice() {
  const { data: price, isLoading, refetch } = useReadContract({
    address: CONTRACT_ADDRESSES.priceOracle,
    abi: ['function getPrice(address asset) view returns (uint256)'],
    functionName: 'getPrice',
    args: ['0x0000000000000000000000000000000000000000'], // ETH
  });

  return {
    price: price || 0n,
    priceFormatted: price ? formatEther(price) : '0',
    isLoading,
    refetch
  };
}

// Hook to get user's USDF balance and allowance
export function useUSDF(userAddress: Address, spender?: Address) {
  const { data: balance } = useReadContract({
    address: CONTRACT_ADDRESSES.usdf,
    abi: USDF_ABI,
    functionName: 'balanceOf',
    args: [userAddress],
  });

  const { data: allowance } = useReadContract({
    address: CONTRACT_ADDRESSES.usdf,
    abi: USDF_ABI,
    functionName: 'allowance',
    args: spender ? [userAddress, spender] : [userAddress, CONTRACT_ADDRESSES.borrowerOperations],
  });

  return {
    balance: balance || 0n,
    balanceFormatted: balance ? formatEther(balance) : '0',
    allowance: allowance || 0n,
    allowanceFormatted: allowance ? formatEther(allowance) : '0'
  };
}

// Hook to get stability pool data
export function useStabilityPool(userAddress: Address) {
  const { data: deposit } = useReadContract({
    address: CONTRACT_ADDRESSES.stabilityPool,
    abi: STABILITY_POOL_ABI,
    functionName: 'deposits',
    args: [userAddress],
  });

  const { data: compoundedDeposit } = useReadContract({
    address: CONTRACT_ADDRESSES.stabilityPool,
    abi: STABILITY_POOL_ABI,
    functionName: 'getCompoundedUSDF',
    args: [userAddress],
  });

  const { data: collateralGain } = useReadContract({
    address: CONTRACT_ADDRESSES.stabilityPool,
    abi: STABILITY_POOL_ABI,
    functionName: 'getDepositorCollateralGain',
    args: [userAddress, '0x0000000000000000000000000000000000000000'], // ETH
  });

  const { data: fluidGain } = useReadContract({
    address: CONTRACT_ADDRESSES.stabilityPool,
    abi: STABILITY_POOL_ABI,
    functionName: 'getDepositorFLUIDGain',
    args: [userAddress],
  });

  const { data: totalUSDF } = useReadContract({
    address: CONTRACT_ADDRESSES.stabilityPool,
    abi: STABILITY_POOL_ABI,
    functionName: 'getTotalUSDF',
  });

  return {
    deposit: deposit || 0n,
    compoundedDeposit: compoundedDeposit || 0n,
    collateralGain: collateralGain || 0n,
    fluidGain: fluidGain || 0n,
    totalUSDF: totalUSDF || 0n,
    depositFormatted: deposit ? formatEther(deposit) : '0',
    collateralGainFormatted: collateralGain ? formatEther(collateralGain) : '0',
    fluidGainFormatted: fluidGain ? formatEther(fluidGain) : '0'
  };
}

// Hook for opening a trove
export function useOpenTrove() {
  const { writeContract, data: hash, isPending, error } = useWriteContract();
  
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  const openTrove = async (
    collateralAmount: string,
    usdfAmount: string,
    maxFeePercentage: string = '0.05'
  ) => {
    const collAmount = parseEther(collateralAmount);
    const debtAmount = parseEther(usdfAmount);
    const maxFee = parseEther(maxFeePercentage);

    writeContract({
      address: CONTRACT_ADDRESSES.borrowerOperations,
      abi: BORROWER_OPERATIONS_ABI,
      functionName: 'openTrove',
      args: [
        '0x0000000000000000000000000000000000000000', // ETH
        maxFee,
        collAmount,
        debtAmount,
        '0x0000000000000000000000000000000000000000', // upperHint
        '0x0000000000000000000000000000000000000000', // lowerHint
      ],
      value: collAmount,
    });
  };

  return {
    openTrove,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error
  };
}

// Hook for adjusting a trove
export function useAdjustTrove() {
  const { writeContract, data: hash, isPending, error } = useWriteContract();
  
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  const adjustTrove = async (
    collateralChange: string,
    usdfChange: string,
    isDebtIncrease: boolean,
    maxFeePercentage: string = '0.05'
  ) => {
    const collChange = parseEther(collateralChange);
    const debtChange = parseEther(usdfChange);
    const maxFee = parseEther(maxFeePercentage);

    writeContract({
      address: CONTRACT_ADDRESSES.borrowerOperations,
      abi: BORROWER_OPERATIONS_ABI,
      functionName: 'adjustTrove',
      args: [
        '0x0000000000000000000000000000000000000000', // ETH
        maxFee,
        collChange,
        debtChange,
        isDebtIncrease,
        '0x0000000000000000000000000000000000000000', // upperHint
        '0x0000000000000000000000000000000000000000', // lowerHint
      ],
      value: isDebtIncrease ? 0n : collChange, // Only send ETH if adding collateral
    });
  };

  return {
    adjustTrove,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error
  };
}

// Hook for stability pool operations
export function useStabilityPoolOperations() {
  const { writeContract, data: hash, isPending, error } = useWriteContract();
  
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  const depositToSP = async (amount: string) => {
    const depositAmount = parseEther(amount);

    writeContract({
      address: CONTRACT_ADDRESSES.stabilityPool,
      abi: STABILITY_POOL_ABI,
      functionName: 'provideToSP',
      args: [
        depositAmount,
        '0x0000000000000000000000000000000000000000', // frontEndTag
      ],
    });
  };

  const withdrawFromSP = async (amount: string) => {
    const withdrawAmount = parseEther(amount);

    writeContract({
      address: CONTRACT_ADDRESSES.stabilityPool,
      abi: STABILITY_POOL_ABI,
      functionName: 'withdrawFromSP',
      args: [withdrawAmount],
    });
  };

  const withdrawAllFromSP = async () => {
    writeContract({
      address: CONTRACT_ADDRESSES.stabilityPool,
      abi: STABILITY_POOL_ABI,
      functionName: 'withdrawAllFromSP',
    });
  };

  return {
    depositToSP,
    withdrawFromSP,
    withdrawAllFromSP,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error
  };
}

// Hook for calculating borrowing fees
export function useBorrowingFee(usdfAmount: string) {
  const amount = usdfAmount ? parseEther(usdfAmount) : 0n;
  
  const { data: fee } = useReadContract({
    address: CONTRACT_ADDRESSES.borrowerOperations,
    abi: BORROWER_OPERATIONS_ABI,
    functionName: 'getBorrowingFee',
    args: ['0x0000000000000000000000000000000000000000', amount], // ETH, amount
    query: {
      enabled: amount > 0n,
    },
  });

  return {
    fee: fee || 0n,
    feeFormatted: fee ? formatEther(fee) : '0',
    feePercentage: amount > 0n && fee ? (Number(fee) / Number(amount) * 100).toFixed(3) : '0'
  };
}

// Hook for system statistics
export function useSystemStats() {
  const { data: totalDebt } = useReadContract({
    address: CONTRACT_ADDRESSES.troveManager,
    abi: TROVE_MANAGER_ABI,
    functionName: 'totalDebt',
    args: ['0x0000000000000000000000000000000000000000'], // ETH
  });

  const { data: totalCollateral } = useReadContract({
    address: CONTRACT_ADDRESSES.troveManager,
    abi: TROVE_MANAGER_ABI,
    functionName: 'totalCollateral',
    args: ['0x0000000000000000000000000000000000000000'], // ETH
  });

  const { data: totalStabilityPoolUSDF } = useReadContract({
    address: CONTRACT_ADDRESSES.stabilityPool,
    abi: STABILITY_POOL_ABI,
    functionName: 'getTotalUSDF',
  });

  const { data: ethPrice } = useReadContract({
    address: CONTRACT_ADDRESSES.priceOracle,
    abi: ['function getPrice(address asset) view returns (uint256)'],
    functionName: 'getPrice',
    args: ['0x0000000000000000000000000000000000000000'], // ETH
  });

  // Calculate TVL
  const tvl = totalCollateral && ethPrice 
    ? (totalCollateral * ethPrice) / parseEther('1')
    : 0n;

  return {
    totalDebt: totalDebt || 0n,
    totalCollateral: totalCollateral || 0n,
    totalStabilityPoolUSDF: totalStabilityPoolUSDF || 0n,
    ethPrice: ethPrice || 0n,
    tvl,
    totalDebtFormatted: totalDebt ? formatEther(totalDebt) : '0',
    totalCollateralFormatted: totalCollateral ? formatEther(totalCollateral) : '0',
    tvlFormatted: tvl ? formatEther(tvl) : '0',
    ethPriceFormatted: ethPrice ? formatEther(ethPrice) : '0'
  };
}

// Utility hook for ICR calculations
export function useICRCalculation(collateral: bigint, debt: bigint) {
  const { price } = useETHPrice();
  
  const icr = debt > 0n && price > 0n 
    ? (collateral * price) / debt 
    : 0n;
  
  const icrPercentage = icr > 0n 
    ? Number(formatEther(icr)) * 100 
    : 0;

  const riskLevel = icrPercentage >= 150 ? 'safe' : 
                   icrPercentage >= 135 ? 'warning' : 'danger';

  return {
    icr,
    icrPercentage,
    icrFormatted: icrPercentage.toFixed(2) + '%',
    riskLevel,
    isHealthy: icrPercentage >= 135,
    liquidationPrice: collateral > 0n && price > 0n 
      ? (debt * parseEther('1.1')) / collateral // 110% liquidation threshold
      : 0n
  };
}