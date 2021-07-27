// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

contract SummerTimeCoreConfig {
    // Initial protocol-WIDE DEBT ceiling is: $100,000
    uint256 public summerTimeTotalDebtCeiling = 100000;

    // Vault liquidation incentive: 5%
    uint256 public constant liquidationIncentive = 500;

    // The portion of accrued interest that goes into reserves, initial set to: 0.10%
    uint256 reserveFactor = 10;

    // NOTE: Setting to 1000 since there's a very high probabilty we'll never
    // get to 1000 assets available to borrow against, but who knows!!!
    uint256 maxAssetsThatCanBeUsedForBorrowing = 1000;

    // From the onset there will be no vault opening fee
    uint256 public vaultOpeningFee = 0;

    // Initial set to: 0.5%
    uint256 public vaultClosingFee = 50;

    // For protocol-WIDE pausing depositing or borrowing, incase there is a need to do so
    // Withdrawals should never be paused.
    bool public protocolDepositingPaused;
    bool public protocolBorrowingPaused;
}
