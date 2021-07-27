// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "./SummerTimeVault.sol";

contract UserVault {
  // VAULT ID count will start at 100,000
  uint private vaultIDCount = 100000;

  struct UserVaultInfo {
    uint ID;
    // A user can deposit more that 1 collateral to borrow against
    mapping (address => uint) tokenCollateralAmount;
    uint debtBorrowedAmount;
    uint debtCollateralRatio;
    bool softDeleted;
  }
  mapping (address => UserVaultInfo) internal userVaults;
  address[] internal vaultCurrentUsers;

  modifier onlyVaultOwner(uint256 vaultID) {
    UserVaultInfo storage userVaultInfo = userVaults[msg.sender];
    require(userVaultInfo.ID == 0 || userVaultInfo.softDeleted == true, "onlyVaultOwner: VAULT DOESNT EXISTS");
    _;
  }

  function createUserVault(address userAddress /*, address collateralType */) external returns (uint createdVaultId) {
    address memory userVaultAddress =  userAddress || msg.sender;
    // Check if the user has already created a vault with us
    UserVaultInfo storage userVaultInfo = userVaults[userVaultAddress];
    require(userVaultInfo.ID == 0 && userVaultInfo.softDeleted == false, "createUserVault: VAULT EXISTS");

    if (userVaultInfo.ID == 0) {
      uint memory createdVaultId = vaultIDCount++; // createdVaultId is return variable
      userVaultInfo.ID = createdVaultId;
      // userVaultInfo.tokenCollateralAmount[collateralType] = 0;
      vaultCurrentUsers.push(userVaultAddress);
      emit UserVaultCreated(createdVaultId, userVaultAddress, false);
    } else {
      // If the vault exits, just undelete it
      userVaultInfo.softDeleted = false;
      emit UserVaultCreated(createdVaultId, userVaultAddress, true);
    }
    return createdVaultId;
  }

  function transferUserVault(address newVaultOwnerAddress) external onlyVaultOwner returns (bool) {
    UserVaultInfo storage userVaultInfo = userVaults[msg.sender];
    UserVaultInfo storage newVaultOwnerInfo = userVaults[newVaultOwnerAddress];

    if (newVaultOwnerInfo.ID != 0)  {
      revert("transferUserVault: NEW OWNER ALREADY HAS A VAULT");
    }

    newVaultOwnerInfo = userVaultInfo;
    delete userVaults[msg.sender];
    return true;
  }

  function destroyUserVault() external onlyVaultOwner returns (bool) {
    UserVaultInfo storage userVaultInfo = userVaults[msg.sender];
    // Ensure user's SHELL DEBT is 0 (fully paid back)
    require(userVaultInfo.debtBorrowedAmount == 0, "destroyUserVault: VAULT STILL HAS DEBT");
    userVaults[msg.sender].softDeleted = true;
    return true;
  }

  event UserVaultCreated(uint newVaultID, address user, bool unarchived);
  event UserVaultTransfered(uint vaultID, address oldUserAddress, address newUserAddress);
  event UserVaultDestroyed(uint vauldID, address user);
}
