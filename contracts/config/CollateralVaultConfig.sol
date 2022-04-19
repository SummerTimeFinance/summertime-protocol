// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";

contract CollateralVaultConfig is Ownable {
    struct VaultConfig {
        // eg. CAKE/BNB
        string displayName;
        // The LP Collateral token address accepted by the platform
        address collateralTokenAddress;
        // The token addresses of the tokens paired together in the AMM
        address token0;
        address token1;
        // The name of the each of the tokens in the pair, not required
        // Can be inferred from the frontend configuration
        // string token0Name;
        // string token1Name;
        // This is to be able to support not only PancakeSwap,
        // but any together UniswapV2 clone out there
        address uniswapFactoryAddress;
        // The Pancake or MasterChef address being used for staking the LP
        // By default, it's 0, which should reference PCS
        uint256 index;
        // The MasterChef pool ID of this LP collateral
        uint256 farmPoolID;
        // The strategy address for this vault used by SummerTime for compounding
        address strategyAddress;
        // The price oracle to get the PRICE of the token0
        address token0PriceOracle;
        // The price oracle to get the PRICE of the token1
        address token1PriceOracle;
        // the current fair LP price
        uint256 fairPrice;
        // Initially , it's 0, so unlimited, should be set to $1000 while testing
        uint256 maxCollateralAmountAccepted;
        // By default it will be 50% (5e17),
        // but should be adjustable depending on the collateral provided
        // For example, USDT-BUSD should have a lower discount such as 10%
        uint256 discountApplied;
        // For pausing depositing or borrowing, incase there is a need to do so
        bool depositingPaused;
        bool borrowingPaused;
        // When disabled, ONLY repayments, and withdrawals will be permitted
        bool disabled;
    }
}
