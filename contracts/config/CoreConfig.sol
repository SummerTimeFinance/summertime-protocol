// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "../constants/Defaults.sol";

contract SummerTimeCoreConfig is DefaultConfig {
    // Initial protocol-WIDE DEBT ceiling is: $100,000
    uint256 public summerTimeDebtCeiling = 100000;

    // The base can be used to calculate a new CCR for a new vault,
    // or updating an existing one, equal to 100%
    uint256 public constant baseDebtCollateralRatio = 100;

    // Default CCR: 150%
    uint256 public defaultDebtCollateralRatio = 150;

    // Default platform interest rate: 5%
    uint256 public defaultInterestRate = 5;

    // Vault liquidation incentive: 5%
    uint256 public constant liquidationIncentive = 5;

    // The portion of accrued interest that goes into reserves, initial set to: 0.10%
    uint256 reserveFactor = 10;
    uint256 reserveAmount = 0;

    // NOTE: Setting to 1000 since there's a very high probabilty we'll never
    // get to 1000 assets available to borrow against, but who knows!!!
    uint256 maxAssetsThatCanBeUsedForBorrowing = 1000;

    // From the onset there will be no vault opening fee
    uint256 public vaultOpeningFee = 0;

    // Initial set to: 0.5%
    uint256 public vaultClosingFee = 50;

    // Debt borrowing onetime fee: 0.5%
    uint256 public debtBorrowingFee = 0;

    // For protocol-WIDE pausing depositing or borrowing, incase there is a need to do so
    bool public protocolDepositingPaused;
    bool public protocolBorrowingPaused;

    function perSecondInterestRate(uint256 givenInterestRate) internal pure returns (uint256) {
        uint256 everySecondInterestRate = (givenInterestRate * decimal18Places) / secondsInYear;
        return everySecondInterestRate;
    }
}
