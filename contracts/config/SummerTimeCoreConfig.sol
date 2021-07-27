// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

contract SummerTimeCoreConfig {
  // Initial protocol-WIDE DEBT ceiling is: $100,000
  uint public summerTimeTotalDebtCeiling = 100000;

  // Vault liquidation incentive: 5%
  uint public constant liquidationIncentive = 500;

  // The portion of accrued interest that goes into reserves, initial set to: 0.10%
  uint reserveFactor = 10;

  // Setting to 1000 since there's a very high probabilty we'll never
  // get to 1000 assets available to borrow against, but who knows!!!
  uint maxAssetsThatCanBeUsedForBorrowing = 1000;

  // From the onset there will be no vault opening fee
  uint public vaultOpeningFee = 0;

  // Initial set to: 0.5%
  uint public vaultClosingFee = 50;

  // For protocol-WIDE pausing depositing or borrowing, incase there is a need to do so
  // Withdrawals should never be paused.
  bool public vaultDepositingPaused;
  bool public vaultBorrowingPaused;
}
