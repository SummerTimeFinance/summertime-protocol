// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "../constants/Defaults.sol";

contract SummerTimeCoreConfig is DefaultConfig {
    // Note: The treasury admin will be set as the deployer address
    address public platformTreasuryAdminAddress;

    // Default platform interest rate: 5%
    address public platformInterestRateAddress;

    // The platform's stability pool address, used for liquidations
    // @reference: https://docs.liquity.org/faq/stability-pool-and-liquidations
    address public platformStabilityPool;

    // Holds the total collateral value deposited into SummerTime finance
    uint256 public platformTotalCollateralValue = 0;

    // The amount of collateral that is in the reserves
    // @TODO: When debt is repaid, send the the 0.10% of the interest rate accrued to the reserves
    uint256 public platformTotalReserves = 0;

    // The portion of accrued interest that goes into reserves
    // initially default percentage: 0.10%
    uint256 public reserveFactor = 1e17;

    // Initial PROTOCOL-WIDE DEBT ceiling is: $100,000
    uint256 public summerTimeDebtCeiling = 100000e18;

    // Used to set the mininum amount of debt a user can borrow
    uint256 public minimumDebtAmount = 0;

    // The base can be used to calculate a new CCR for a new vault,
    // or updating an existing one, equal to 1
    uint256 public constant baseCollateralCoverageRatio = 1e18;

    // Targeted CCR of a vault (1.2), once liquidation is triggered
    uint256 public targetedCollateralCoverageRatio = 12e17;

    // The collateral discount applied to the user's collateral: 60% (0.6)
    uint256 public platformDefaultDiscountApplied = 6e17;

    // The threshold at which a borrow position will be considered
    // undercollateralized and subjected to liquidation for each collateral: 0.95
    uint256 public liquidationThresholdCCR = 95e17;

    // On liquidation, 4/9 of a vault's collateral is taken
    uint256 public liquidationFraction = 44444e13;

    // Vault liquidation incentive: 10%
    uint256 public liquidationIncentive = 10e18;

    // Liquidation fee of 0.5% is applied to all liquidations
    uint256 public liquidationFee = 5e17;

    // Debt borrowing one-time fee: 0.5%
    uint256 public debtBorrowingFee = 5e17;

    // For protocol-WIDE pausing depositing or borrowing, incase there is a need to do so
    bool public protocolDepositingPaused = false;
    bool public protocolBorrowingPaused = false;
}
