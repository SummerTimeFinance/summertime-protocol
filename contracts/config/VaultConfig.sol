// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";

contract VaultCollateralConfig is Ownable {
    struct VaultConfig {
        // eg. CAKE/BNB
        string collateralDisplayName;
        // The LP Collateral token address accepted by the platform
        address collateralTokenAddress;
        // The address where all the collateral is deposited at
        address collateralAddress;
        // Is the vault a single asset collateral vault; only SET once
        // eg. we can accept USDC only vaults, to help stabalize the SHELL stablecoin
        bool isSingleAssetCollateralVault;
        // The token addresses of the tokens paired together in the AMM
        address token0;
        address token1;
        // The name of the each of the tokens in the pair, not required
        // Can be inferred from the frontend configuration
        // string token0Name;
        // string token1Name;
        // The Pancake or MasterChef address being used for staking the LP
        address stakingAddress;
        // The strategy address for this vault used by SummerTime for compounding
        address strategyAddress;
        // the current fair LP price
        uint256 fairPrice;
        // The price oracle to get the PRICE of the LP tokens using the fair price
        address priceOracleAddress;
        // Backup price oracle if the main one fails, may use for Uniswapv2 TWAP oracles
        address priceOracle2Address;
        // This collateral vault custom interest rate, if still 0, it uses the global one
        uint256 interestRate;
        // This collateral vault specific debt ceiling, if 0, its unlimited
        uint256 debtCeiling;
        // Default will be 50%, meaning user can borrow only up to 50% of their collateral value
        // Set to 51 to allow user to actually borrow up to 50% of it
        uint256 minimumDebtCollateralRatio;
        // The current ratio, got from: debt / deposits
        uint256 currentDebtCollateralRatio;
        // Initially value will be $1000, if 0, it's unlimited
        uint256 maxCollateralAmountAccepted;
        // Both initialized with 0;
        uint256 currentTotalDepositedAmount;
        uint256 currentTotalDebtBorrowed;
        // For pausing depositing or borrowing, incase there is a need to do so
        bool depositingPaused;
        bool borrowingPaused;
        // When disabled, ONLY repayments, and withdrawals will be permitted
        bool disabled;
    }
}
