// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";

contract VaultCollateralConfig is Ownable {

  struct VaultInformation {
    // eg. CAKE/BNB
    string collateralName;
    // The LP Collateral token address accepted by the platform
    address collateralTokenAddress;
    // The address where all the collateral is deposited at
    address collateralAddress;
    // Is the vault a single asset collateral vault
    // eg. we can accept USDC only vaults, to help stabalize the SHELL stablecoin
    bool isSingleAssetCollateralVault;
    // The token addresses of the tokens paired together in the AMM
    address token0;
    address token1;
    // The name of the each of the tokens in the pair
    string token0Name;
    string token1Name;
    // The Pancake or MasterChef address being used for staking the LP
    address stakingAddress;
    // The strategy address used by SummerTime for compounding
    address strategyAddress;
    // The price oracle to get the PRICE of the LP tokens using the fair price
    // Reference: https://github.com/AlphaFinanceLab/alpha-homora-v2-contract/blob/master/contracts/oracle/UniswapV2Oracle.sol
    address priceOracleAddress;
    // Backup price oracle if the main one fails, may use for Uniswapv2 TWAP oracles
    address secondaryPriceOracleAddress;
  }

  mapping(address => VaultInformation) internal vaultInformation;
}
