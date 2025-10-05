// Example React components for Fluid Protocol frontend
import React, { useState, useMemo, useEffect } from 'react';
import { parseEther, formatEther } from 'viem';
import { useAccount, useBalance } from 'wagmi';
import { 
  useTrove, 
  useETHPrice, 
  useOpenTrove, 
  useAdjustTrove,
  useBorrowingFee,
  useStabilityPool,
  useStabilityPoolOperations,
  useSystemStats,
  useICRCalculation
} from './frontend-hooks-example';

// Risk level indicator component
const RiskIndicator = ({ icr }: { icr: number }) => {
  const getRiskLevel = (icr: number) => {
    if (icr >= 200) return { level: 'Safe', color: 'text-green-600', bg: 'bg-green-100' };
    if (icr >= 150) return { level: 'Moderate', color: 'text-yellow-600', bg: 'bg-yellow-100' };
    if (icr >= 135) return { level: 'Warning', color: 'text-orange-600', bg: 'bg-orange-100' };
    return { level: 'Danger', color: 'text-red-600', bg: 'bg-red-100' };
  };

  const risk = getRiskLevel(icr);
  
  return (
    <div className={`px-3 py-1 rounded-full text-sm font-medium ${risk.color} ${risk.bg}`}>
      {risk.level} ({icr.toFixed(2)}%)
    </div>
  );
};

// Open Trove Component
export const OpenTrove = () => {
  const { address } = useAccount();
  const { data: ethBalance } = useBalance({ address });
  const [collAmount, setCollAmount] = useState('');
  const [usdfAmount, setUsdfAmount] = useState('');
  const [maxFee, setMaxFee] = useState('5'); // 5% default
  
  const { price, isLoading: priceLoading } = useETHPrice();
  const { fee, feePercentage } = useBorrowingFee(usdfAmount);
  const { openTrove, isPending, isSuccess, error } = useOpenTrove();
  const trove = useTrove(address!);

  // Calculate ICR in real-time
  const icr = useMemo(() => {
    if (!collAmount || !usdfAmount || !price) return 0;
    const totalDebt = parseFloat(usdfAmount) + parseFloat(formatEther(fee));
    return (parseFloat(collAmount) * parseFloat(formatEther(price))) / totalDebt * 100;
  }, [collAmount, usdfAmount, fee, price]);

  const canOpenTrove = useMemo(() => {
    return icr >= 135 && 
           parseFloat(usdfAmount) >= 200 && 
           parseFloat(collAmount) > 0 &&
           !trove.exists &&
           ethBalance && parseFloat(collAmount) <= parseFloat(formatEther(ethBalance.value));
  }, [icr, usdfAmount, collAmount, trove.exists, ethBalance]);

  const handleOpenTrove = async () => {
    if (!canOpenTrove) return;
    await openTrove(collAmount, usdfAmount, (parseFloat(maxFee) / 100).toString());
  };

  if (trove.exists) {
    return (
      <div className="p-6 bg-blue-50 rounded-lg">
        <h3 className="text-lg font-semibold text-blue-800">You already have an active trove</h3>
        <p className="text-blue-600">Use the Adjust Trove section to modify your position.</p>
      </div>
    );
  }

  return (
    <div className="max-w-md mx-auto p-6 bg-white rounded-lg shadow-lg">
      <h2 className="text-2xl font-bold mb-6">Open Trove</h2>
      
      <div className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            ETH Collateral
          </label>
          <input
            type="number"
            value={collAmount}
            onChange={(e) => setCollAmount(e.target.value)}
            placeholder="0.0"
            className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
          {ethBalance && (
            <p className="text-sm text-gray-500 mt-1">
              Balance: {parseFloat(formatEther(ethBalance.value)).toFixed(4)} ETH
            </p>
          )}
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            USDF to Borrow
          </label>
          <input
            type="number"
            value={usdfAmount}
            onChange={(e) => setUsdfAmount(e.target.value)}
            placeholder="0.0"
            className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
          <p className="text-sm text-gray-500 mt-1">Minimum: 200 USDF</p>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            Max Fee (%)
          </label>
          <input
            type="number"
            value={maxFee}
            onChange={(e) => setMaxFee(e.target.value)}
            min="0.5"
            max="5"
            step="0.1"
            className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>

        {collAmount && usdfAmount && (
          <div className="p-4 bg-gray-50 rounded-lg space-y-2">
            <div className="flex justify-between">
              <span>Collateral Ratio:</span>
              <RiskIndicator icr={icr} />
            </div>
            <div className="flex justify-between">
              <span>Borrowing Fee:</span>
              <span>{formatEther(fee)} USDF ({feePercentage}%)</span>
            </div>
            <div className="flex justify-between">
              <span>Total Debt:</span>
              <span>{(parseFloat(usdfAmount) + parseFloat(formatEther(fee)) + 200).toFixed(2)} USDF</span>
            </div>
          </div>
        )}

        <button
          onClick={handleOpenTrove}
          disabled={!canOpenTrove || isPending || priceLoading}
          className={`w-full py-3 px-4 rounded-md font-medium ${
            canOpenTrove && !isPending
              ? 'bg-blue-600 hover:bg-blue-700 text-white'
              : 'bg-gray-300 text-gray-500 cursor-not-allowed'
          }`}
        >
          {isPending ? 'Opening Trove...' : 'Open Trove'}
        </button>

        {error && (
          <div className="p-3 bg-red-100 border border-red-400 text-red-700 rounded">
            {error.message}
          </div>
        )}

        {isSuccess && (
          <div className="p-3 bg-green-100 border border-green-400 text-green-700 rounded">
            Trove opened successfully!
          </div>
        )}
      </div>
    </div>
  );
};

// Adjust Trove Component
export const AdjustTrove = () => {
  const { address } = useAccount();
  const trove = useTrove(address!);
  const { price } = useETHPrice();
  const { adjustTrove, isPending, isSuccess, error } = useAdjustTrove();
  
  const [collChange, setCollChange] = useState('');
  const [debtChange, setDebtChange] = useState('');
  const [isAddingColl, setIsAddingColl] = useState(true);
  const [isIncreasingDebt, setIsIncreasingDebt] = useState(true);

  const { icrPercentage: newICR } = useICRCalculation(
    isAddingColl 
      ? trove.collateral + parseEther(collChange || '0')
      : trove.collateral - parseEther(collChange || '0'),
    isIncreasingDebt
      ? trove.debt + parseEther(debtChange || '0')
      : trove.debt - parseEther(debtChange || '0')
  );

  const canAdjust = useMemo(() => {
    return trove.isActive && newICR >= 135 && (collChange || debtChange);
  }, [trove.isActive, newICR, collChange, debtChange]);

  const handleAdjust = async () => {
    if (!canAdjust) return;
    await adjustTrove(collChange || '0', debtChange || '0', isIncreasingDebt);
  };

  if (!trove.isActive) {
    return (
      <div className="p-6 bg-yellow-50 rounded-lg">
        <h3 className="text-lg font-semibold text-yellow-800">No Active Trove</h3>
        <p className="text-yellow-600">Open a trove first to adjust your position.</p>
      </div>
    );
  }

  return (
    <div className="max-w-md mx-auto p-6 bg-white rounded-lg shadow-lg">
      <h2 className="text-2xl font-bold mb-6">Adjust Trove</h2>
      
      <div className="mb-6 p-4 bg-gray-50 rounded-lg">
        <h3 className="font-semibold mb-2">Current Position</h3>
        <div className="space-y-1 text-sm">
          <div className="flex justify-between">
            <span>Collateral:</span>
            <span>{parseFloat(formatEther(trove.collateral)).toFixed(4)} ETH</span>
          </div>
          <div className="flex justify-between">
            <span>Debt:</span>
            <span>{parseFloat(formatEther(trove.debt)).toFixed(2)} USDF</span>
          </div>
          <div className="flex justify-between">
            <span>ICR:</span>
            <RiskIndicator icr={trove.icrPercentage} />
          </div>
        </div>
      </div>

      <div className="space-y-4">
        <div>
          <div className="flex items-center justify-between mb-2">
            <label className="text-sm font-medium text-gray-700">Collateral Change</label>
            <div className="flex space-x-2">
              <button
                onClick={() => setIsAddingColl(true)}
                className={`px-3 py-1 text-xs rounded ${isAddingColl ? 'bg-green-100 text-green-800' : 'bg-gray-100'}`}
              >
                Add
              </button>
              <button
                onClick={() => setIsAddingColl(false)}
                className={`px-3 py-1 text-xs rounded ${!isAddingColl ? 'bg-red-100 text-red-800' : 'bg-gray-100'}`}
              >
                Remove
              </button>
            </div>
          </div>
          <input
            type="number"
            value={collChange}
            onChange={(e) => setCollChange(e.target.value)}
            placeholder="0.0 ETH"
            className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>

        <div>
          <div className="flex items-center justify-between mb-2">
            <label className="text-sm font-medium text-gray-700">Debt Change</label>
            <div className="flex space-x-2">
              <button
                onClick={() => setIsIncreasingDebt(true)}
                className={`px-3 py-1 text-xs rounded ${isIncreasingDebt ? 'bg-red-100 text-red-800' : 'bg-gray-100'}`}
              >
                Borrow
              </button>
              <button
                onClick={() => setIsIncreasingDebt(false)}
                className={`px-3 py-1 text-xs rounded ${!isIncreasingDebt ? 'bg-green-100 text-green-800' : 'bg-gray-100'}`}
              >
                Repay
              </button>
            </div>
          </div>
          <input
            type="number"
            value={debtChange}
            onChange={(e) => setDebtChange(e.target.value)}
            placeholder="0.0 USDF"
            className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>

        {(collChange || debtChange) && (
          <div className="p-4 bg-gray-50 rounded-lg">
            <div className="flex justify-between items-center">
              <span className="font-medium">New ICR:</span>
              <RiskIndicator icr={newICR} />
            </div>
          </div>
        )}

        <button
          onClick={handleAdjust}
          disabled={!canAdjust || isPending}
          className={`w-full py-3 px-4 rounded-md font-medium ${
            canAdjust && !isPending
              ? 'bg-blue-600 hover:bg-blue-700 text-white'
              : 'bg-gray-300 text-gray-500 cursor-not-allowed'
          }`}
        >
          {isPending ? 'Adjusting...' : 'Adjust Trove'}
        </button>

        {error && (
          <div className="p-3 bg-red-100 border border-red-400 text-red-700 rounded">
            {error.message}
          </div>
        )}

        {isSuccess && (
          <div className="p-3 bg-green-100 border border-green-400 text-green-700 rounded">
            Trove adjusted successfully!
          </div>
        )}
      </div>
    </div>
  );
};

// Stability Pool Component
export const StabilityPoolInterface = () => {
  const { address } = useAccount();
  const stabilityPool = useStabilityPool(address!);
  const { depositToSP, withdrawFromSP, withdrawAllFromSP, isPending, isSuccess, error } = useStabilityPoolOperations();
  
  const [depositAmount, setDepositAmount] = useState('');
  const [withdrawAmount, setWithdrawAmount] = useState('');

  const handleDeposit = async () => {
    if (!depositAmount || parseFloat(depositAmount) <= 0) return;
    await depositToSP(depositAmount);
  };

  const handleWithdraw = async () => {
    if (!withdrawAmount || parseFloat(withdrawAmount) <= 0) return;
    await withdrawFromSP(withdrawAmount);
  };

  const handleWithdrawAll = async () => {
    await withdrawAllFromSP();
  };

  return (
    <div className="max-w-md mx-auto p-6 bg-white rounded-lg shadow-lg">
      <h2 className="text-2xl font-bold mb-6">Stability Pool</h2>
      
      <div className="mb-6 p-4 bg-blue-50 rounded-lg">
        <h3 className="font-semibold mb-2 text-blue-800">Your Position</h3>
        <div className="space-y-1 text-sm">
          <div className="flex justify-between">
            <span>USDF Deposited:</span>
            <span>{stabilityPool.depositFormatted} USDF</span>
          </div>
          <div className="flex justify-between">
            <span>ETH Rewards:</span>
            <span className="text-green-600">{stabilityPool.collateralGainFormatted} ETH</span>
          </div>
          <div className="flex justify-between">
            <span>FLUID Rewards:</span>
            <span className="text-purple-600">{stabilityPool.fluidGainFormatted} FLUID</span>
          </div>
        </div>
      </div>

      <div className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            Deposit USDF
          </label>
          <div className="flex space-x-2">
            <input
              type="number"
              value={depositAmount}
              onChange={(e) => setDepositAmount(e.target.value)}
              placeholder="0.0"
              className="flex-1 px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
            <button
              onClick={handleDeposit}
              disabled={!depositAmount || isPending}
              className="px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700 disabled:bg-gray-300"
            >
              Deposit
            </button>
          </div>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            Withdraw USDF
          </label>
          <div className="flex space-x-2">
            <input
              type="number"
              value={withdrawAmount}
              onChange={(e) => setWithdrawAmount(e.target.value)}
              placeholder="0.0"
              max={stabilityPool.depositFormatted}
              className="flex-1 px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
            <button
              onClick={handleWithdraw}
              disabled={!withdrawAmount || isPending}
              className="px-4 py-2 bg-yellow-600 text-white rounded-md hover:bg-yellow-700 disabled:bg-gray-300"
            >
              Withdraw
            </button>
          </div>
        </div>

        {parseFloat(stabilityPool.depositFormatted) > 0 && (
          <button
            onClick={handleWithdrawAll}
            disabled={isPending}
            className="w-full py-2 bg-red-600 text-white rounded-md hover:bg-red-700 disabled:bg-gray-300"
          >
            Withdraw All + Claim Rewards
          </button>
        )}

        {error && (
          <div className="p-3 bg-red-100 border border-red-400 text-red-700 rounded">
            {error.message}
          </div>
        )}

        {isSuccess && (
          <div className="p-3 bg-green-100 border border-green-400 text-green-700 rounded">
            Transaction successful!
          </div>
        )}
      </div>
    </div>
  );
};

// System Dashboard Component
export const SystemDashboard = () => {
  const { address } = useAccount();
  const { totalDebt, totalCollateral, tvl, ethPrice } = useSystemStats();
  const trove = useTrove(address!);
  const stabilityPool = useStabilityPool(address!);

  return (
    <div className="max-w-4xl mx-auto p-6">
      <h1 className="text-3xl font-bold mb-8">Fluid Protocol Dashboard</h1>
      
      {/* System Stats */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
        <div className="bg-white p-6 rounded-lg shadow">
          <h3 className="text-sm font-medium text-gray-500">Total Value Locked</h3>
          <p className="text-2xl font-bold text-gray-900">${parseFloat(formatEther(tvl)).toLocaleString()}</p>
        </div>
        <div className="bg-white p-6 rounded-lg shadow">
          <h3 className="text-sm font-medium text-gray-500">Total USDF Debt</h3>
          <p className="text-2xl font-bold text-gray-900">{parseFloat(formatEther(totalDebt)).toLocaleString()}</p>
        </div>
        <div className="bg-white p-6 rounded-lg shadow">
          <h3 className="text-sm font-medium text-gray-500">Total ETH Collateral</h3>
          <p className="text-2xl font-bold text-gray-900">{parseFloat(formatEther(totalCollateral)).toLocaleString()}</p>
        </div>
        <div className="bg-white p-6 rounded-lg shadow">
          <h3 className="text-sm font-medium text-gray-500">ETH Price</h3>
          <p className="text-2xl font-bold text-gray-900">${parseFloat(formatEther(ethPrice)).toLocaleString()}</p>
        </div>
      </div>

      {/* User Position */}
      {address && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          {/* Trove Position */}
          <div className="bg-white p-6 rounded-lg shadow">
            <h3 className="text-lg font-semibold mb-4">Your Trove</h3>
            {trove.isActive ? (
              <div className="space-y-3">
                <div className="flex justify-between">
                  <span>Collateral:</span>
                  <span className="font-medium">{parseFloat(formatEther(trove.collateral)).toFixed(4)} ETH</span>
                </div>
                <div className="flex justify-between">
                  <span>Debt:</span>
                  <span className="font-medium">{parseFloat(formatEther(trove.debt)).toFixed(2)} USDF</span>
                </div>
                <div className="flex justify-between items-center">
                  <span>Collateral Ratio:</span>
                  <RiskIndicator icr={trove.icrPercentage} />
                </div>
              </div>
            ) : (
              <p className="text-gray-500">No active trove</p>
            )}
          </div>

          {/* Stability Pool Position */}
          <div className="bg-white p-6 rounded-lg shadow">
            <h3 className="text-lg font-semibold mb-4">Stability Pool</h3>
            {parseFloat(stabilityPool.depositFormatted) > 0 ? (
              <div className="space-y-3">
                <div className="flex justify-between">
                  <span>USDF Deposited:</span>
                  <span className="font-medium">{stabilityPool.depositFormatted} USDF</span>
                </div>
                <div className="flex justify-between">
                  <span>ETH Rewards:</span>
                  <span className="font-medium text-green-600">{stabilityPool.collateralGainFormatted} ETH</span>
                </div>
                <div className="flex justify-between">
                  <span>FLUID Rewards:</span>
                  <span className="font-medium text-purple-600">{stabilityPool.fluidGainFormatted} FLUID</span>
                </div>
              </div>
            ) : (
              <p className="text-gray-500">No stability pool deposit</p>
            )}
          </div>
        </div>
      )}
    </div>
  );
};