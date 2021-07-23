// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.8.0;

contract SummerTimeCoreConfig {
  // Vault liquidation incentive: 5%
  uint256 public constant liquidationIncentive = 500;

  // Setting to 1000 since there's a very high probabilty we'll never
  // get to 1000 assets available to borrow against
  uint256 maxAssetsThatCanBeUsedForBorrowing = 1000;

  // The portion of accrued interest that goes into reserves, initial set to: 0.10%
  uint256 reserveFactor = 10;

  // Initial DEBT ceiling is: $100,000
  uint256 public summerTimeDebtCeiling = 100000;

  // From the onset there will be no vault opening fee
  uint256 public vaultOpeningFee = 0;

  // Initial configuration is: 0.5%
  uint256 public vaultClosingFee = 50;
}
