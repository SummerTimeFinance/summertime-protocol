// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "./SummerTimeVault.sol";

contract UserVault {
    // VAULT ID count will start at 100,000
    uint256 private vaultIDCount = 100000;

    struct UserVaultInfo {
        uint256 ID;
        // A user can deposit more that 1 collateral to borrow against
        mapping(address => uint256) collateralAmount;
        // Calculated on each deposit, withdawal, borrowing and repayment
        uint256 collateralValueAmount;
        uint256 debtBorrowedAmount;
        uint256 debtCollateralRatio;
        bool softDeleted;
    }

    mapping(address => UserVaultInfo) internal userVaults;
    address[] internal vaultCurrentUsers;

    modifier onlyVaultOwner(uint256 vaultID) {
        UserVaultInfo storage userVault = userVaults[msg.sender];
        require(
            userVault.ID != 0 || userVault.softDeleted != true,
            "onlyVaultOwner: VAULT DOES NOT EXISTS"
        );
        _;
    }

    function createUserVault(
        address userAddress /*, address collateralType */
    ) external returns (uint256 createdVaultId) {
        address memory userVaultAddress = userAddress || msg.sender;
        // Check if the user has already created a vault with us
        UserVaultInfo storage userVault = userVaults[userVaultAddress];
        require(
            userVault.ID == 0 && userVault.softDeleted == false,
            "createUserVault: VAULT EXISTS"
        );

        if (userVault.ID == 0) {
            uint256 memory createdVaultId = vaultIDCount++; // createdVaultId is return variable
            userVault.ID = createdVaultId;
            // userVault.tokenCollateralAmount[collateralType] = 0;
            vaultCurrentUsers.push(userVaultAddress);
            emit UserVaultCreated(createdVaultId, userVaultAddress, false);
        } else {
            // If the vault exits, just "undelete" it
            userVault.softDeleted = false;
            emit UserVaultCreated(createdVaultId, userVaultAddress, true);
        }
        return createdVaultId;
    }

    function transferUserVault(address newVaultOwnerAddress)
        external
        onlyVaultOwner
        returns (uint256)
    {
        UserVaultInfo storage userVault = userVaults[msg.sender];
        UserVaultInfo storage newVaultOwnerInfo = userVaults[
            newVaultOwnerAddress
        ];

        if (newVaultOwnerInfo.ID != 0) {
            revert("transferUserVault: NEW OWNER ALREADY HAS A VAULT");
        }

        newVaultOwnerInfo = userVault;
        delete userVaults[msg.sender];
        emit UserVaultTransfered(
            userVault.ID,
            msg.sender,
            newVaultOwnerAddress
        );
        return userVault.ID;
    }

    function destroyUserVault()
        external
        onlyVaultOwner
        returns (uint256, bool)
    {
        UserVaultInfo storage userVault = userVaults[msg.sender];
        // Ensure user's $SHELL DEBT is 0 (fully paid back)
        require(
            userVault.debtBorrowedAmount == 0,
            "destroyUserVault: VAULT STILL HAS DEBT"
        );
        userVaults[msg.sender].softDeleted = true;
        emit UserVaultDestroyed(userVault.ID, msg.sender);
        return (userVault.ID, true);
    }

    event UserVaultCreated(
        uint256 newVaultID,
        address vaultOwnerAddress,
        bool unarchived
    );
    event UserVaultTransfered(
        uint256 vaultID,
        address oldVaultOwnerAddress,
        address newVaultOwnerAddress
    );
    event UserVaultDestroyed(uint256 vauldID, address vaultOwnerAddress);
}
