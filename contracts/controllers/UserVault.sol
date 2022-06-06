// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract UserVault is ReentrancyGuard {
    // VAULT ID count will start at 100,000
    uint256 private vaultIDCount = 100000;

    struct CollateralVaultInfo {
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
        mapping(address => CollateralVaultInfo) info;
        // Calculated on each deposit, withdawal, borrowing and repayment
        uint256 totalCollateralValue;
        uint256 totalDebtBorrowedAmount;
        uint256 collateralCoverageRatio;
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
        internal
        returns (uint256 createdVaultId)
    {
        bool userVaultUnarchived = false;
        address vaultOwnerAddress = userAddress;
        if (vaultOwnerAddress == address(0)) {
            vaultOwnerAddress = msg.sender;
        }
        // Check if the user has already created a vault with us
        UserVaultInfo storage userVault = userVaults[vaultOwnerAddress];
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
        onlyVaultOwner(msg.sender)
        nonReentrant
        returns (uint256)
    {
        UserVaultInfo storage previousUserVault = userVaults[
            msg.sender
        ];
        // updateUserCollateralCoverageRatio(previousUserVault);

        UserVaultInfo storage nextUserVault = userVaults[
            newVaultOwnerAddress
        ];
        // Check to see if the new owner already has a vault
        if (nextUserVault.ID > 0) {
            revert("Transfer: msg.sender(address) already has an active vault");
        }

        // If the new user doesn't have a vault, create one and do the trenasfer;
        createUserVault(newVaultOwnerAddress);
        nextUserVault = userVaults[newVaultOwnerAddress];

        // Save the IDs into the memory, so that they are set back to what they were
        uint256 nextVaultOwnerID = nextUserVault.ID;
        uint256 previousVaultOwnerID = previousUserVault.ID;

        // Swap the properties of the vaults, to reset the previous one
        (nextUserVault, previousUserVault) = (previousUserVault, nextUserVault);
        nextUserVault.ID = nextVaultOwnerID;
        previousUserVault.ID = previousVaultOwnerID;

        emit UserVaultTransfered(
            msg.sender,
            newVaultOwnerAddress,
            nextUserVault.totalCollateralValue,
            nextUserVault.totalDebtBorrowedAmount
        );
        return nextVaultOwnerID;
    }

    function destroyUserVault()
        external
        onlyVaultOwner(msg.sender)
        nonReentrant
        returns (uint256, bool)
    {
        UserVaultInfo storage userVault = userVaults[msg.sender];
        // Ensure user's $SHELL DEBT is 0 (fully paid back)
        require(
            userVault.totalDebtBorrowedAmount == 0 && userVault.totalCollateralValue == 0,
            "destroyUserVault: Still has DEBT or COLLATERAL"
        );
        userVaults[msg.sender].softDeleted = true;
        emit UserVaultDestroyed(userVault.ID, msg.sender);
        return (userVault.ID, true);
    }

    event UserVaultCreated(
        uint256 newVaultID,
        address vaultOwner,
        bool unarchived
    );
    event UserVaultTransfered(
        address previousVaultOwner,
        address nextVaultOwner,
        uint256 collateralAmount,
        uint256 debtBorrowedAmount
    );
    event UserVaultDestroyed(uint256 vauldID, address vaultOwner);
}
