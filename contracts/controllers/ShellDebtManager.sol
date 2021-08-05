// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../config/CoreConfig.sol";
import "../helpers/FairLPPriceOracle.sol";
import "../tokens/SHELL.sol";
import "./SummerTimeVault.sol";

contract ShellDebtManager is
    SummerTimeCoreConfig,
    SummerTimeVault,
    ShellStableCoin,
    ReentrancyGuard,
    Ownable
{
    using SafeMath for uint256;

    // @dev constructor will initialize SHELL with a cap (debt ceiling) of $100,000
    // @param uint: summerTimeTotalDebtCeiling (global config variable)
    // @param address: uniswapFactoryAddress_ this is PancakeSwap's LP Factory address
    constructor(address uniswapFactoryAddress_)
        internal
        ShellStableCoin(summerTimeTotalDebtCeiling)
        SummerTimeVault(uniswapFactoryAddress_)
    {
        // Do some magic!
    }

    function depositCollateral(address collateralAddress)
        external
        payable
        collateralAccepted(collateralAddress)
        onlyVaultOwner
    {
        UserVaultInfo storage userVault = userVaults[msg.sender];
        // Update the vault's fair LP price
        uint256 fairLPPrice = this.fetchCollateralPrice(collateralAddress);

        // Is depositing disabled globally
        require(!protocolDepositingPaused, "Deposits are paused.");

        // User must deposit an amount larger than 0
        require(msg.value > 0, "Must deposit an amount larger than 0");

        uint256 memory currentCollateralAmount = userVault.collateral[
            collateralAddress
        ];
        uint256 newCollateralAmount = currentCollateralAmount.add(msg.value);
        require(
            newCollateralAmount <= currentCollateralAmount,
            "depositCollateral: new total collateral should be more than previous"
        );
        // Update the user's current collateral amount & value
        userVault.collateral[collateralAddress] = newCollateralAmount;
        // Update user's collateral total value to the current value
        this.updateUserCollateralValue(userVault);

        // IF the user has any DEBT,
        // calculate accrued interest amount, and add it to existing debt
        this.updateUserDebtState(userVault);

        // TODO:
        // - Collect rewards, and compound this vault (yeild-optimization part not written yet)
        emit DepositCollateral(userVault.ID, collateralAddress, msg.value);
    }

    function borrowShellStableCoin(uint256 amountBorrowed)
        external
        onlyVaultOwner
    {
        UserVaultInfo storage userVault = userVaults[msg.sender];
        // Update user's collateral total value to the current value
        this.updateUserCollateralValue(userVault);
        // IF the user has any DEBT,
        // calculate accrued interest amount, and add it to existing debt
        this.updateUserDebtState(userVault);

        // User must deposit an amount larger than 0
        require(
            amountBorrowed > 0,
            "Borrow: Must borrow more an amount above 0"
        );

        // Is borrrowing disabled globally
        require(!protocolBorrowingPaused, "Borrowing is paused.");

        // Has the global DEBT ceiling been hit
        uint256 SHELLTotalSupply = ShellStableCoin.totalSupply();
        require(
            !(SHELLTotalSupply.add(amountBorrowed) <= ShellStableCoin.cap()),
            "Borrow: debt ceiling hit, can't not borrow."
        );

        uint256 memory newUserTotalDebtBorrowed = userVault.debtBorrowedAmount.add(
            amountBorrowed
        );
        uint256 memory newDebtCollateralRatio = newUserTotalDebtBorrowed.div(
            userVault.collateralValueAmount
        );

        // Check if new Debt/Collateral ratio allows user to borrow
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        if (newDebtCollateralRatio < vault.minimumDebtCollateralRatio) {
            revert(
                "Borrow: new borrow would put vault below minimum debt/collateral ratio"
            );
        }
        // TODO: Inform user the vault is close to the min debt/collateral ratio
        // Set the new DC ratio for user
        userVault.debtCollateralRatio = newDebtCollateralRatio;

        // If all is well, let the user borrow SHELL stablecoin for use
        // Add borrowed amount to the total amount borrowed by the user [if borrowed]
        userVault.debtBorrowedAmount = newUserTotalDebtBorrowed;

        // Update protocol's reserve amount (sell SHELL for USDC)
        // Transfer SHELL borrowed to ther user
        _mint(msg.sender, amountBorrowed);
        emit UserBorrowedDebt(vaultID, msg.sender, amountBorrowed);
    }

    function repayShellStablecoinDebt(uint256 amountRepayed) external onlyVaultOwner {
        UserVaultInfo storage userVault = userVaults[msg.sender];
        // Update user's collateral value to the current value
        this.updateUserCollateralValue(userVault);
        // IF the user has any DEBT,
        // calculate accrued interest amount, and add it to existing debt
        this.updateUserDebtState(userVault);

        // User must deposit an amount larger than 0
        require(
            amountRepayed > 0,
            "Repay: Must borrow more an amount above 0"
        );

        // User must have the amount in the wallet too
        require(
            balanceOf(msg.sender) >= amountRepayed,
            "Repay: your balance is lesser than amount for repayment"
        );

        uint256 memory newUserTotalDebtBorrowed;
        uint256 memory newDebtCollateralRatio;
        uint256 memory amountBalance;

        newUserTotalDebtBorrowed = userVault.debtBorrowedAmount.sub(
            amountRepayed
        );
        // Check to see if the repayed amount is larger or equal than the actual debt
        // In this scenario, only deduct the DEBT owed, and send back the rest to the user
        if (amountRepayed >= userVault.debtBorrowedAmount) {
            newUserTotalDebtBorrowed = userVault.debtBorrowedAmount.sub(
                userVault.debtBorrowedAmount
            );
            amountBalance = amountRepayed.sub(userVault.debtBorrowedAmount);
            // Send back the SHELL balance that was left after paying the DEBT
            _transfer(address(this), msg.sender, amountBalance);
        }

        // Get the new debt/collateral ratio
        newDebtCollateralRatio = newUserTotalDebtBorrowed.div(
            userVault.collateralValueAmount
        );

        userVault.debtCollateralRatio = newDebtCollateralRatio;
        userVault.debtBorrowedAmount = newUserTotalDebtBorrowed;

        // Destroy the SHELL paid back
        _burn(msg.sender, amountRepayed);
        emit UserRepayedDebt(vaultID, msg.sender, amountRepayed);
    }

    function transferUserDebtFromVault(
        address newVaultOwnerAddress,
        address collateralAddress
    ) external onlyVaultOwner returns (bool) {
        UserVaultInfo storage userVault = userVaults[msg.sender];
        UserVaultInfo storage newVaultOwnerVault = userVaults[
            newVaultOwnerAddress
        ];

        // If the new user doesn't have a vault, create one on the go for them
        if (newVaultOwnerVault.ID == 0) {
            this.createUserVault(newVaultOwnerAddress);
        }

        UserVaultInfo storage newVaultOwner = userVaults[newVaultOwnerAddress];
        newVaultOwner.collateralAmount = userVault.collateralAmount;
        newVaultOwner.collateralValueAmount = userVault.collateralValueAmount;
        newVaultOwner.debtBorrowedAmount = userVault.debtBorrowedAmount;
        newVaultOwner.debtCollateralRatio = userVault.debtCollateralRatio;
        newVaultOwner.lastDebtUpdate = userVault.lastDebtUpdate;
        newVaultOwner.softDeleted = userVault.softDeleted;

        // Clear up the information of the previous owner's vault
        // reset all properties to defaults;
        for (
            int256 index = 0;
            index < vaultCollateralAddresses.length;
            index++
        ) {
            UserVault.collateralAmount[vaultCollateralAddresses[index]] = 0;
        }
        userVault.collateralValueAmount = 0;
        userVault.debtBorrowedAmount = 0;
        userVault.debtCollateralRatio = 0;
        userVault.lastDebtUpdate = 0;
        userVault.softDeleted = false;

        emit UserTransferedVault(
            msg.sender,
            newVaultOwnerAddress,
            amount,
            debtAmount
        );
    }

    function updateUserCollateralValue(UserVaultInfo storage userVault)
        internal
        returns (uint256)
    {
        // reset user collateralValueAmount to 0
        userVault.collateralValueAmount = 0;

        // @info LOOP thru each available collateral getting the user's collateral amount
        // Use that amount to calculate thier current total collateral value
        // according to the new price for each LP collateral
        for (
            int256 index = 0;
            index < vaultCollateralAddresses.length;
            index++
        ) {
            address memory collateralAddress = vaultCollateralAddresses[index];
            if (userVault.collateralAmount[collateralAddress] > 0) {
                uint256 collateralAmount = userVault.collateralAmount[
                    collateralAddress
                ];
                uint256 fairLPPrice = this.fetchCollateralPrice(
                    collateralAddress
                );
                userVault.collateralValueAmount += collateralAmount.mul(
                    fairLPPrice
                );
            }
        }

        return userVault.collateralValueAmount;
    }

    function updateUserDebtState(UserVaultInfo storage UserVault) internal {
        if (userVault.debtBorrowedAmount > 0) {
            // the time past since last debt accrued update (in seconds)
            uint256 currentTimestamp = block.timestamp;
            uint256 timeDifference = uint256(
                currentTimestamp - userVault.lastDebtUpdate
            );
            uint256 interestToBeApplied = timeDifference.mul(
                perSecondInterestRate()
            );
            uint256 accruedInterest = interestToBeApplied.mul(
                userVault.debtBorrowedAmount
            );

            // Update user's current DEBT amount
            uint256 newBorrowedDebtAmount = userVault.debtBorrowedAmount.add(
                accruedInterest
            );
            require(
                userVault.debtBorrowedAmount > newBorrowedDebtAmount,
                "Deposit: new debtBorrowedAmount can not be less than previous"
            );
            userVault.debtBorrowedAmount = newBorrowedDebtAmount;

            // Update user's debt/collateral ratio
            uint256 newDebtCollateralRatio = debtBorrowedAmount.div(
                userVault.collateralValueAmount
            );
            require(
                userVault.debtCollateralRatio > newDebtCollateralRatio,
                "Deposit: new debt/collateral ratio can not be less than previous"
            );
            userVault.debtCollateralRatio = newDebtCollateralRatio;
            // Don't forget to update the lastDebtUpdate timestamp
            userVault.lastDebtUpdate = currentTimestamp;
        }
    }

    event UserDepositedCollateral(
        uint256 vaultID,
        address collateralAddress,
        address vaultOwner
    );
    event UserBorrowedDebt(uint256 vaultID, address vaultOwner, uint256 amount);
    event UserRepayedDebt(uint256 vaultID, address vaultOwner, uint256 amount);
    event UserTransferedVault(
        address previousOwnerAddress,
        address newDebtOwnerAddress,
        address collateralAddress,
        uint256 collateralAmount,
        uint256 debtBorrowedAmount
    );
}
