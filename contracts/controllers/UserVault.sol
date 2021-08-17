// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "./SummerTimeVault.sol";

contract UserVault is PriceOracle {
    // VAULT ID count will start at 100,000
    uint256 private vaultIDCount = 100000;

    struct UserVaultInfo {
        uint256 ID;
        // The collateral amount of each collateral the user has deposited
        mapping(address => uint256) collateralAmount;
        // The collateral value of each collateral the user has
        mapping(address => uint256) collateralValue;
        // Calculated on each deposit, withdawal, borrowing and repayment
        uint256 totalCollateralValue;
        uint256 debtBorrowedAmount;
        uint256 collateralCoverageRatio;
        // default is 0, meaning the user has no debt
        uint256 lastDebtUpdate;
        bool softDeleted;
    }

    mapping(address => UserVaultInfo) internal userVaults;
    address[] internal vaultCurrentUsers;

    modifier onlyVaultOwner(address vaultOwner) {
        UserVaultInfo memory userVault = userVaults[msg.sender];
        if (vaultOwner != address(0)) {
            userVault = userVaults[vaultOwner];
        }
        require(
            userVault.ID != 0 || userVault.softDeleted != true,
            "onlyVaultOwner: VAULT DOES NOT EXISTS"
        );
        _;
    }

    function createUserVault(address userAddress)
        external
        returns (uint256 createdVaultId)
    {
        address memory vaultOwnerAddress = userAddress || msg.sender;
        // Check if the user has already created a vault with us
        UserVaultInfo storage userVault = userVaults[vaultOwnerAddress];
        require(
            userVault.ID == 0 && userVault.softDeleted == false,
            "createUserVault: VAULT EXISTS"
        );

        if (userVault.ID == 0) {
            uint256 memory createdVaultId = vaultIDCount++; // createdVaultId is return variable
            userVault.ID = createdVaultId;
            // userVault.tokenCollateralAmount[collateralType] = 0;
            vaultCurrentUsers.push(vaultOwnerAddress);
            emit UserVaultCreated(createdVaultId, vaultOwnerAddress, false);
        } else {
            // If the vault exits, just "undelete" it
            userVault.softDeleted = false;
            emit UserVaultCreated(createdVaultId, vaultOwnerAddress, true);
        }
        return createdVaultId;
    }

    function transferUserVault(address newVaultOwnerAddress)
        external
        virtual
        onlyVaultOwner
        returns (uint256)
    {
        // Overridden (defined well) in ShellDebtManager.sol contract
        // that inherits it from SummerTimeVault contract
    }

    function destroyUserVault()
        external
        onlyVaultOwner
        returns (uint256, bool)
    {
        UserVaultInfo storage userVault = userVaults[msg.sender];
        // Ensure user's $SHELL DEBT is 0 (fully paid back)
        require(
            userVault.debtBorrowedAmount == 0 && userVault.lastDebtUpdate == 0,
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
