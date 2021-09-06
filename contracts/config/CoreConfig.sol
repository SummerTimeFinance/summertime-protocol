// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "../constants/Defaults.sol";

contract SummerTimeCoreConfig is DefaultConfig {
    // The treasury admin will be set as the deployer address
    address public treasuryAdminAddress;

    // This is the platform's stability pool address
    address public platformStabilityPool;

    // Initial protocol-WIDE DEBT ceiling is: $100,000
    uint256 public summerTimeDebtCeiling = 100000e18;

    // Used to set the mininum amount of debt a user can borrow
    uint256 public minimumDebtAmount = 0;

    // Holds the total collateral value deposited into SummerTime
    uint256 public platformTotalCollateralValue = 0;

    // The base can be used to calculate a new CCR for a new vault,
    // or updating an existing one, equal to 1
    uint256 public constant baseCollateralCoverageRatio = 1e18;

    // The threshold at which a borrow position will be considered: 0.95
    // undercollateralized and subject to liquidation for each collateral.
    uint256 public liquidationThreshold = 95e17;

    // Targeted CCR of a vault (1.2), once liquidation is triggered
    uint256 public targetedCollateralCoverageRatio = 12e17;

    // discount applied the user's collateralL: 50% (0.5)
    uint256 public discountApplied = 5e17;

    // Default platform interest rate: 5%
    address public platformInterestRateAddress;

    // On liquidation, 4/9 of a vault's collateral is taken
    uint256 public liquidationFraction = 44444e13;

    // Vault liquidation incentive: 10%
    uint256 public liquidationIncentive = 10e18;

    // Liquidation fee of 0.5% is applied to all liquidations
    uint256 public liquidationFee = 5e17;

    // The portion of accrued interest that goes into reserves, initial set to: 0.10%
    uint256 public reserveFactor = 1e17;

    // The amount of collateral that is in the reserves
    uint256 public reserveAmount = 0;

    // Set to $25, same as the cost to opening a bank account
    uint256 public vaultOpeningFee = 25e18;

    // Initial set to: 0
    uint256 public vaultClosingFee = 0;

    // Debt borrowing onetime fee: 0.5%
    uint256 public debtBorrowingFee = 5e17;

    // For protocol-WIDE pausing depositing or borrowing, incase there is a need to do so
    bool public protocolDepositingPaused = false;
    bool public protocolBorrowingPaused = false;
}
