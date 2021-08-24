// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";

contract VaultCollateralConfig is Ownable {
    // This collateral vault custom interest rate, if still 0, it uses the global one
    uint256 interestRate;
    // This collateral vault specific debt ceiling, if 0, its unlimited
    uint256 debtCeiling;
    // Is the vault a single asset collateral vault; only SET once
    // eg. we can accept USDC only vaults, to help stablize the SHELL stablecoin
    bool isSingleAssetCollateralVault;
    // Both initialized with 0;
    uint256 totalDepositedAmount;
    uint256 totalDebtBorrowed;
    // For pausing depositing or borrowing, incase there is a need to do so
    bool depositingPaused;
    bool borrowingPaused;
}
