// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

contract UserVault {
    // VAULT ID count will start at 100,000
    uint256 private vaultIDCount = 100000;

    struct VaultInfo {
        uint256 collateralAmount;
        uint256 collateralValue;
        uint256 collateralCoverageRatio;
        uint256 debtBorrowedAmount;
        uint256 lastDebtUpdate;
    }

    struct UserVaultInfo {
        uint256 ID;
        // vaultInfo[0] - The total amount of each collateral the user has deposited
        // vaultInfo[1] - The value in dollars of each collateral the user has deposited
        // vaultInfo[2] - The collateral coverage ratio for each collateral
        // vaultInfo[3] - The debt borrowed from this collateral
        // vaultInfo[4] - The last time the debt was updated
        mapping(address => VaultInfo) info;
        // Calculated on each deposit, withdawal, borrowing and repayment
        uint256 totalCollateralValue;
        uint256 totalDebtBorrowedAmount;
        uint256 collateralCoverageRatio;
        bool softDeleted;
    }

    mapping(address => UserVaultInfo) internal platformUserVaults;
    address[] internal vaultCurrentUsers;

    modifier onlyVaultOwner(address vaultOwner) {
        UserVaultInfo memory userVault = platformUserVaults[msg.sender];
        if (vaultOwner != address(0)) {
            userVault = platformUserVaults[vaultOwner];
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
        bool userVaultUnarchived = false;
        address vaultOwnerAddress = userAddress;
        if (vaultOwnerAddress == address(0)) {
            vaultOwnerAddress = msg.sender;
        }
        // Check if the user has already created a vault with us
        UserVaultInfo storage userVault = platformUserVaults[vaultOwnerAddress];
        require(
            userVault.ID == 0 && userVault.softDeleted == false,
            "createUserVault: VAULT EXISTS"
        );

        if (userVault.ID == 0) {
            createdVaultId = vaultIDCount++; // createdVaultId is return variable
            userVault.ID = createdVaultId;
            // userVault.tokenCollateralAmount[collateralType] = 0;
            vaultCurrentUsers.push(vaultOwnerAddress);
        } else {
            // If the vault exits, just "undelete" it
            userVault.softDeleted = false;
            userVaultUnarchived = true;
        }

        emit UserVaultCreated(
            createdVaultId,
            vaultOwnerAddress,
            userVaultUnarchived
        );
        return createdVaultId;
    }

    function transferUserVault(address newVaultOwnerAddress)
        external
        virtual
        onlyVaultOwner(msg.sender)
        returns (uint256)
    {
        // Overridden (defined well) in ShellDebtManager.sol contract
        // that inherits it from SummerTimeVault contract
        (uint256 x, uint256 y) = (100, 100);
        return x - y;
    }

    function destroyUserVault()
        external
        onlyVaultOwner(msg.sender)
        returns (uint256, bool)
    {
        UserVaultInfo storage userVault = platformUserVaults[msg.sender];
        // Ensure user's $SHELL DEBT is 0 (fully paid back)
        require(
            userVault.debtBorrowedAmount == 0 && userVault.lastDebtUpdate == 0,
            "destroyUserVault: VAULT STILL HAS DEBT"
        );
        platformUserVaults[msg.sender].softDeleted = true;
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
