// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";
// import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "../controllers/UserVault.sol";
import "../config/VaultConfig.sol";

contract SummerTimeVault is Ownable, VaultCollateralConfig, UserVault {

  struct GeneralVaultInfo {
    // This collateral vault specific debt ceiling
    uint vaultDebtCeiling;

    // Default will be 50%, meaning user can borrow only up to 50% of their collateral value
    // Set to 51 to allow user to actually borrow up to 50% of it
    uint minimumDebtCollateralRatio;

    // Initially set to worth $1000
    uint maximumAmountOfCollateralAccepted;

    // Both initialized with 0;
    uint currentTotalCollateralDeposited;
    uint currentTotalDebtBorrowed;

    // For pausing depositing or borrowing, incase there is a need to do so
    bool depositingPaused;
    bool borrowingPaused;

    // is this specific collateral vault disabled
    bool disabled;
  }

  address[] internal availableCollateralVaults;
  mapping(address => GeneralVaultInfo) internal generalVaultInfo;

  // token0Name, token1Name, token0, token1 can all be derived from the UniswapV2 interface
  constructor(
    string collateralDisplayName,
    address collateralTokenAddress,
    address collateralAddress,
    address stakingAddress,
    address strategyAddress,
    address priceOracleAddress
  ) {
    require(bytes(collateralDisplayName).length > 0, "VAULT: collateralDisplayName not provided");
    require(address(collateralTokenAddress) != address(0), "VAULT: collateralTokenAddress not provided");
    // require(address(stakingAddress) != address(0), "VAULT: stakingAddress not provided");
    // require(address(strategyAddress) != address(0), "VAULT: strategyAddress not provided");
    require(address(priceOracleAddress) != address(0), "VAULT: priceOracleAddress not provided");

    IUniswapV2Pair tokenPairsForLP = IUniswapV2Pair(collateralTokenAddress);
    token0 = tokenPairsForLP.token0();
    token1 = tokenPairsForLP.token1();
  }

  function setCollateralName(string newCollateralDisplayName) public onlyOwner returns (bool) {
    if (bytes(newCollateralDisplayName).length > 0) return false;
    collateralDisplayName = newCollateralDisplayName;
    return true;
  }

  function setStakingAddress(address newStakingAddress) public onlyOwner returns (bool) {
    // TODO: Check the previous staking address doesnt have tokens with it already
    // If it does, unstake those tokens and migrate them to the new stakingAddress
    stakingAddress = newStakingAddress;
    return true;
  }

  function setStrategyAddress(address newStrategyAddress) public onlyOwner returns (bool) {
    strategyAddress = newStrategyAddress;
    return true;
  }

  function setPriceOracleAddress(address newPriceOracleAddress) public onlyOwner returns (bool) {
    priceOracleAddress = newPriceOracleAddress;
    return true;
  }

  function transferUserDebtFromVault(address newVaultOwnerAddress, address collateralAddress) external onlyVaultOwner returns (bool) {
    UserVaultInfo storage userVaultInfo = userVaults[msg.sender];
    UserVaultInfo storage newVaultOwnerInfo = userVaults[newVaultOwnerAddress];

    // If the new user doesn't have a vault, create one on the go
    if (newVaultOwnerInfo.ID == 0) super.createUserVault(newVaultOwnerAddress);
    // TODO:
    // get user's debt/collateral ratio,
    // then migrate the debt to the new vault along with enough collateral
    // according to the user's debt/collateral ratio
  }

  event NewCollateralVaultAvailable(address vaultCollateralAddress, address token0, address token1);
  // @dev: if borrowingDisabled is false (default), then it's deposits that have been disabled
  event CollateralVaultDisabled(address vaultCollateralAddress, bool borrowingDisabled);
}
