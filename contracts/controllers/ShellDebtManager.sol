// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../config/SummerTimeCoreConfig.sol";
import "../tokens/SHELL.sol";
import "../interfaces/InterestRateModel.sol";
import "../interfaces/FarmingStrategy.sol";

import "./SummerTimeVault.sol";

contract ShellDebtManager is
    Ownable,
    ReentrancyGuard,
    SummerTimeCoreConfig,
    SummerTimeVault,
    ShellStableCoin
{
    /// @dev the interest rate model contract used to depict the interest rate
    InterestRateModel internal platformInterestRateModel;
    FarmingStrategy internal farmingStrategy;

    // @dev constructor will initialize SHELL with a cap (debt ceiling) of $100,000
    // @param uint: summerTimeDebtCeiling (global config variable)
    // @param address: _uniswapFactoryAddress this is PancakeSwap's LP Factory address
    constructor(
        address fairLPPriceOracle,
        address interestRateModel,
        address farmingStrategyAddress
    )
        internal
        ShellStableCoin(summerTimeDebtCeiling)
        SummerTimeVault(fairLPPriceOracle)
    {
        require(
            interestRateModel != address(0),
            "DebtManager: interest rate model not provided"
        );
        // TODO: Create the treasury vault, to absorb liquidation collateral fee
        // And also to absorb & hold other supported assets such as USDC
        platformTreasuryAdminAddress = msg.sender;
        platformInterestRateModel = InterestRateModel(interestRateModel);
        farmingStrategy = FarmingStrategy(farmingStrategyAddress);
    }

    function depositCollateral(address collateralAddress)
        external
        payable
        collateralAccepted(collateralAddress)
        onlyVaultOwner(msg.sender)
        nonReentrant
    {
        UserVaultInfo storage userVault = platformUserVaults[msg.sender];

        // Check to see if depositing is disabled globally
        require(
            !protocolDepositingPaused,
            "depositCollateral: deposits are paused."
        );

        // User must deposit an amount larger than 0
        require(
            msg.value > 0,
            "depositCollateral: Must deposit an amount larger than 0"
        );

        uint256 currentCollateralAmount = userVault.info[collateralAddress].collateralAmount;
        uint256 newCollateralAmount = currentCollateralAmount.add(msg.value);
        require(
            newCollateralAmount > currentCollateralAmount,
            "depositCollateral: new total collateral should be more than previous"
        );
        // Update the user's current collateral amount & value
        userVault.info[collateralAddress].collateralAmount = newCollateralAmount;

        // @TIP: Assignments between storage and memory
        // (or from calldata) always create an independent copy.
        uint256 previousUserCollateralValue = userVault.totalCollateralValue;
        // Update user's collateral total value to the current value according to current market prices
        // IF the user has any DEBT, calculate & add to the DEBT the new accrued interest amount
        updateUserCollateralCoverageRatio(userVault);

        platformTotalCollateralValue = SafeMath.sub(
            platformTotalCollateralValue,
            previousUserCollateralValue
        );
        platformTotalCollateralValue = SafeMath.add(
            platformTotalCollateralValue,
            userVault.totalCollateralValue
        );

        VaultConfig storage collateralVault = vaultAvailable[collateralAddress];
        // NOTE: the farming strategy can be a dummy one to only be used to
        // hold funds safely in another address, not exactly yeild farm any tokens
        // Move the user's amount from their wallet to the collateral's farming strategy
        farmingStrategy.deposit(
            collateralVault.index,
            collateralAddress,
            msg.value
        );

        emit UserDepositedCollateral(
            userVault.ID,
            collateralAddress,
            msg.value
        );
    }

    function withdrawCollateral(
        address collateralAddress,
        uint256 requestedAmountToWithdraw
    )
        external
        payable
        collateralAccepted(collateralAddress)
        onlyVaultOwner(msg.sender)
        nonReentrant
    {
        UserVaultInfo storage userVault = platformUserVaults[msg.sender];
        uint256 currentCollateralBalance = userVault.info[collateralAddress].collateralAmount;
        // user must withdraw amount equal to or less than their collateral vault balance
        require(
            requestedAmountToWithdraw <= currentCollateralBalance,
            "Withdraw: vault doesn't have the amount of collateral requested"
        );

        uint256 newCollateralBalance = SafeMath.sub(
            currentCollateralBalance,
            requestedAmountToWithdraw
        );
        uint256 collateralFairLPPrice = this.fetchCollateralPrice(
            collateralAddress
        );
        uint256 newCollateralValue = newCollateralBalance.mul(collateralFairLPPrice);

        // Get the new CCR according to the updated collateral value
        uint256 newCollateralCoverageRatio = getCollateralCoverageRatio(
            newCollateralValue,
            userVault.info[collateralAddress].debtBorrowedAmount
        );

        // Check if user's new CCR will be below the minimum required CCR
        if (newCollateralCoverageRatio < liquidationThresholdCCR.div(baseCollateralCoverageRatio)) {
            revert(
                "Withdrawal: would put vault below minimum debt/collateral ratio"
            );
        }

        // If all is well, update user's collateral amount
        userVault.info[collateralAddress].collateralAmount = newCollateralBalance;
        // user's previous total collateral value
        uint256 userPrevTotalCollateralValue = userVault.totalCollateralValue;
        // Update user's collateral total value according to current market prices
        // IF the user has any DEBT, update add the accrued interest rate to the user's DEBT
        updateUserCollateralCoverageRatio(userVault);
        platformTotalCollateralValue = SafeMath.sub(
            platformTotalCollateralValue,
            userPrevTotalCollateralValue
        );
        platformTotalCollateralValue = SafeMath.add(
            platformTotalCollateralValue,
            userVault.totalCollateralValue
        );

        VaultConfig storage collateralVault = vaultAvailable[collateralAddress];
        // now send the amount to the vault owner's address
        farmingStrategy.withdraw(
            collateralVault.index,
            msg.sender,
            collateralAddress,
            requestedAmountToWithdraw
        );
        // NOTE: the transfer is done by the farming strategy withdraw function above
        // _transfer(address(this), msg.sender, requestedAmountToWithdraw);

        emit UserWithdrewCollateral(
            userVault.ID,
            collateralAddress,
            requestedAmountToWithdraw
        );
    }

    function borrowShellStableCoin(address collateralAddress, uint256 requestedBorrowAmount)
        external
        collateralAccepted(collateralAddress)
        onlyVaultOwner(msg.sender)
        nonReentrant
    {
         // Check if borrowing disabled globally
        require(protocolBorrowingPaused == false, "Borrowing is paused.");

        // Check if the global DEBT ceiling been hit
        uint256 SHELLTotalSupply = totalSupply();
        require(
            SHELLTotalSupply.add(requestedBorrowAmount) < ShellStableCoin.cap(),
            "SHELL: Debt ceiling hit, no more borrowing."
        );

        // User must borrow an amount larger than 0
        require(
            requestedBorrowAmount > 0,
            "SHELL: Must borrow an amount above 0"
        );

        UserVaultInfo storage userVault = platformUserVaults[msg.sender];
        // Update user's collateral total value according to current market prices
        // IF the user has any DEBT, update add the accrued interest rate to the user's DEBT
        updateUserCollateralCoverageRatio(userVault);

        uint256 newTotalDebtBorrowed = SafeMath.add(
            userVault.info[collateralAddress].debtBorrowedAmount,
            requestedBorrowAmount
        );

        // Get the new CCR according to the updated collateral value
        uint256 newCollateralCoverageRatio = getCollateralCoverageRatio(
            userVault.info[collateralAddress].collateralValue,
            newTotalDebtBorrowed
        );

        // VaultConfig storage vault = vaultAvailable[collateralAddress];
        // Check if new CCR isn't over the base CCR, thus allow the user to borrow
        if (newCollateralCoverageRatio < liquidationThresholdCCR.div(baseCollateralCoverageRatio)) {
            revert(
                "SHELL: new borrow would put vault below the min accepted CCR"
            );
        }

        // If all is well, let the user borrow SHELL stablecoin for use
        // Total debt borrowed is updated automatically in the SHELL smart contract
        userVault.info[collateralAddress].debtBorrowedAmount = newTotalDebtBorrowed;

        // IF all is well, mint & transfer SHELL borrowed to the user
        _mint(msg.sender, requestedBorrowAmount);
        emit UserBorrowedDebt(userVault.ID, msg.sender, requestedBorrowAmount);
    }

    function repayShellStablecoinDebt(address collateralAddress, uint256 requestedRepayAmount)
        external
        collateralAccepted(collateralAddress)
        onlyVaultOwner(msg.sender)
        nonReentrant
    {
        // User must request to payback an amount larger than 0
        require(
            requestedRepayAmount > 0,
            "Repay: Must request to pay back an amount larger than 0"
        );

        // User must have the equivalent SHELLs or more of the amount in the wallet
        require(
            IERC20(collateralAddress).balanceOf(address(msg.sender)) >= requestedRepayAmount,
            "Repay: Your balance is less than repayment request amount"
        );

        UserVaultInfo storage userVault = platformUserVaults[msg.sender];
        // Update user's collateral value to the current value according to current market prices
        // IF the user has any DEBT, calculate & add to the DEBT the new accrued interest amount
        updateUserCollateralCoverageRatio(userVault);

        uint256 amountBeingRepaid = requestedRepayAmount;
        uint256 userCurrentDebtBorrowed = userVault.info[collateralAddress].debtBorrowedAmount;
        // Get the old user CCR
        uint256 oldCollateralCoverageRatio = userVault.info[collateralAddress].collateralCoverageRatio;
        // Check to see if the repayed amount is larger or equal than the total user debt
        // IF IT IS, only deduct the DEBT owed, and send back the rest to the user
        if (amountBeingRepaid >= userCurrentDebtBorrowed) {
            amountBeingRepaid = userCurrentDebtBorrowed;
            // remainderAmount = amountBeingRepaid.sub(userVault.debtBorrowedAmount);
            // Send back the SHELL balance that was left after paying the DEBT
            // _transfer(address(this), msg.sender, remainderAmount);
        }

        uint256 newDebtBorrowedAmount = SafeMath.sub(
            userCurrentDebtBorrowed,
            amountBeingRepaid
        );
        // Update the user's current DEBT
        userVault.info[collateralAddress].debtBorrowedAmount = newDebtBorrowedAmount;

        // Once more update the user's overall CCR
        updateUserCollateralCoverageRatio(userVault);
        // Check if user's new collateral vault specific CCR is larger than their old one
        require(
            userVault.info[collateralAddress].collateralCoverageRatio > oldCollateralCoverageRatio,
            "Repay: new CCR should be larger than previous user's CCR"
        );

        // Get the reserve amount, and send it to the treasury address
        uint256 amountToSendToReserves = SafeMath.mul(
            amountBeingRepaid,
            reserveFactor.div(100e18)
        );
        platformTotalReserves = SafeMath.add(
            platformTotalReserves,
            amountToSendToReserves
        );
        // Send reserve amount deducted to the reserves
        _transfer(
            msg.sender,
            platformTreasuryAdminAddress,
            amountToSendToReserves
        );

        // Burn the rest
        uint256 amountRepaidBeingBurned = SafeMath.sub(
            amountBeingRepaid,
            amountToSendToReserves
        );
        // Destroy the SHELL paid back
        _burn(msg.sender, amountRepaidBeingBurned);
        emit UserRepayedDebt(userVault.ID, msg.sender, amountBeingRepaid);
    }

    // A user's collateral coverage ratio in each collateral vault should be above or equal to 0.95
    // If one of the user's collateral vault's is below it, it is susceptible to being partially liquidated
    function buyRiskyUserVault(address collateralAddress, address userVaultAddress)
        external
        collateralAccepted(collateralAddress)
        nonReentrant
    {
        // Check to see if the platformStabilityPool is provided
        // IF provided, ensure the liquidator is the platformStabilityPool address
        if (
            platformStabilityPool != address(0) &&
            msg.sender == platformStabilityPool
        ) {
            revert("buyRiskyVault: disabled for the community");
        }

        UserVaultInfo storage liquidatorVault = platformUserVaults[msg.sender];
        if (liquidatorVault.ID == 0) {
            revert("buyRiskyUserVault: liquidator vault doesn't exist");
        }

        UserVaultInfo storage riskyUserVault = platformUserVaults[
            userVaultAddress
        ];
        // Check if the vault exists
        if (riskyUserVault.ID == 0) {
            revert("buyRiskyUserVault: user vault doesn't exist");
        }

        // Update user's collateral value to the current value according to current market prices
        // IF the user has any DEBT, calculate & add to the DEBT the new accrued interest amount
        updateUserCollateralCoverageRatio(riskyUserVault);

        // Check to see if the user's DEBT/Collateral ratio (CCR) is above 0.95
        if (
            riskyUserVault.info[collateralAddress].collateralCoverageRatio >
            liquidationThresholdCCR.div(baseCollateralCoverageRatio)
        ) {
            revert(
                "buyRiskyUserVault: Vault is not below minumum debt/collateral ratio"
            );
        }

        // IF it is, let the liquidation begin :)
        uint256 debtAmountToBePaid = SafeMath.mul(
            riskyUserVault.info[collateralAddress].debtBorrowedAmount,
            liquidationFraction
        );
        require(
            balanceOf(msg.sender) < debtAmountToBePaid,
            "buyRiskyUserVault: liquidator doesn't have enough to pay debt"
        );

        // Now burn the SHELL tokens that the liquidator offered to pay the debt
        _burn(msg.sender, debtAmountToBePaid);

        // This is where we partially liquidate the user's vault
        // Take 4/9th's of the collateral and sell it to pay back the debt
        // Apply the liquidationIncentive & liquidationFee (10% and 0.5%)
        uint256 collateralToClaim = SafeMath.mul(
            debtAmountToBePaid,
            SafeMath.add(uint256(1), liquidationIncentive.div(100e18))
        );

        UserVaultInfo storage treasuryVault = platformUserVaults[
            platformTreasuryAdminAddress
        ];

        // Cut the collateral from the user vault
        riskyUserVault.info[collateralAddress].collateralAmount = SafeMath.sub(
            riskyUserVault.info[collateralAddress].collateralAmount,
            collateralToClaim
        );


        // TODO: Make sure to bootstrap treasury vault in constructor
        // Move 0.5% collateral to be liquidated to our treasury vault
        if (treasuryVault.ID != 0) {
            // revert("buyRiskyUserVault: treasury vault doesn't exist");
            treasuryVault.info[collateralAddress].collateralAmount = SafeMath
                .add(
                    treasuryVault.info[collateralAddress].collateralAmount,
                    SafeMath.mul(
                        collateralToClaim,
                        liquidationFee.div(uint256(100e18))
                    )
                );
        }


        // Move the collateral to be liquidated to the liquidator vault
        liquidatorVault.info[collateralAddress].collateralAmount = SafeMath.add(
            liquidatorVault.info[collateralAddress].collateralAmount,
            collateralToClaim
        );

        emit BuyRiskyVault(
            riskyUserVault.ID,
            riskyUserVault.totalCollateralValue,
            debtAmountToBePaid,
            msg.sender
        );
    }

    function transferUserVault(address newVaultOwnerAddress)
        external
        override(UserVault)
        onlyVaultOwner(msg.sender)
        nonReentrant
        returns (uint256)
    {
        UserVaultInfo storage previousUserVault = platformUserVaults[
            msg.sender
        ];
        // Update user's collateral value to the current value according to current market prices
        // IF the user has any DEBT, calculate & add to the DEBT the new accrued interest amount
        updateUserCollateralCoverageRatio(previousUserVault);

        UserVaultInfo storage nextUserVault = platformUserVaults[
            newVaultOwnerAddress
        ];
        // Check to see if the new owner already has a vault
        if (nextUserVault.ID > 0) {
            revert("Transfer: msg.sender(address) already has an active vault");
        }

        // If the new user doesn't have a vault, create one and do the trenasfer;
        this.createUserVault(newVaultOwnerAddress);
        nextUserVault = platformUserVaults[newVaultOwnerAddress];

        // Save the IDs into the memory, so that they are set back to what they were
        uint256 nextVaultOwnerID = nextUserVault.ID;
        uint256 previousVaultOwnerID = previousUserVault.ID;

        // Swap the properties of the vaults, to reset the previous one
        // and pass all the previous vault information into the next one
        (nextUserVault, previousUserVault) = (previousUserVault, nextUserVault);
        nextUserVault.ID = nextVaultOwnerID;
        previousUserVault.ID = previousVaultOwnerID;

        emit UserTransferredVault(
            msg.sender,
            newVaultOwnerAddress,
            nextUserVault.totalCollateralValue,
            nextUserVault.debtBorrowedAmount
        );
        return nextVaultOwnerID;
    }

    function updateUserCollateralValue(UserVaultInfo storage userVault)
        internal
        returns (uint256)
    {
        // reset user totalCollateralValue to 0
        uint256 userTotalCollateralValue = userVault.totalCollateralValue;

        // @info LOOP thru each available collateral getting the user's collateral amount
        // Use that amount to calculate their current total collateral value according
        // to the new price for each LP collateral
        for (
            uint256 index = 0;
            index < vaultCollateralAddresses.length;
            index++
        ) {
            address collateralAddress = vaultCollateralAddresses[index];
            uint256 collateralAmount = userVault.info[collateralAddress].collateralAmount;
            if (collateralAmount > 0) {
                uint256 collateralFairLPPrice = this.fetchCollateralPrice(
                    collateralAddress
                );
                userVault.info[collateralAddress].collateralValue = collateralAmount.mul(collateralFairLPPrice);
                userTotalCollateralValue = SafeMath.add(
                    userVault.totalCollateralValue,
                    userVault.info[collateralAddress].collateralValue
                );
            }
        }

        userVault.totalCollateralValue = userTotalCollateralValue;
        return userVault.totalCollateralValue;
    }

    function updateUsersDebtValue(UserVaultInfo storage userVault)
        internal
        returns (uint256)
    {
        // the time past since last debt accrued update (in seconds)
        uint256 currentTimestamp = block.timestamp;
        uint256 newTotalDebtBorrowedAmount = 0;
        uint256 currentInterestPerSecond = perSecondInterestRate(
            platformInterestRateModel.getBorrowRate(
                platformTotalCollateralValue,
                // The SHELL supply units is also the platform's total debt value
                totalSupply(),
                platformTotalReserves
            )
        );

        // @info LOOP thru each available collateral getting the user's collateral amount
        // Use that amount to calculate their current total collateral value according
        // to the new price for each LP collateral
        for (
            uint256 index = 0;
            index < vaultCollateralAddresses.length;
            index++
        ) {
            address collateralAddress = vaultCollateralAddresses[index];
            uint256 debtBorrowedAmount = userVault.info[collateralAddress].debtBorrowedAmount;

            if (debtBorrowedAmount > 0) {
                uint256 timeDifference = uint256(
                    currentTimestamp - userVault.info[collateralAddress].lastDebtUpdate
                );
                uint256 interestRateToBeApplied = timeDifference.mul(currentInterestPerSecond);
                uint256 accruedInterest = SafeMath.mul(
                    userVault.info[collateralAddress].debtBorrowedAmount,
                    interestRateToBeApplied
                );

                // Update user's current DEBT amount
                uint256 newBorrowedDebtAmount = SafeMath.add(
                    userVault.info[collateralAddress].debtBorrowedAmount,
                    accruedInterest
                );
                // TIP: Should be assert, using require to see issues faster
                require(
                    newBorrowedDebtAmount > debtBorrowedAmount,
                    "Deposit: new debtBorrowedAmount can not be less than the previous one"
                );
                userVault.info[collateralAddress].debtBorrowedAmount = newBorrowedDebtAmount;
                newTotalDebtBorrowedAmount = newTotalDebtBorrowedAmount.add(newBorrowedDebtAmount);
                // Don't forget to update the lastDebtUpdate timestamp
                userVault.info[collateralAddress].lastDebtUpdate = currentTimestamp;
            }
        }

        userVault.totalDebtBorrowedAmount = newTotalDebtBorrowedAmount;
        return newTotalDebtBorrowedAmount;
    }

    function updateUserCollateralCoverageRatio(UserVaultInfo storage userVault)
        internal
        returns (uint256, uint256, uint256)
    {
        // the time past since last debt accrued update (in seconds)
        uint256 currentTimestamp = block.timestamp;
        uint256 currentInterestPerSecond = perSecondInterestRate(
            platformInterestRateModel.getBorrowRate(
                platformTotalCollateralValue,
                // The SHELL supply units is also the platform's total debt value
                totalSupply(),
                platformTotalReserves
            )
        );

        uint256 newTotalDebtBorrowedAmount = 0;
        uint256 newTotalCollateralValue = userVault.totalCollateralValue;
        uint256 currentUserVaultCCRs = baseCollateralCoverageRatio;

        // @info LOOP thru each available collateral getting the user's collateral amount
        // Use that amount to calculate their current total collateral value according
        // to the new price for each LP collateral
        for (
            uint256 index = 0;
            index < vaultCollateralAddresses.length;
            index++
        ) {
            address collateralAddress = vaultCollateralAddresses[index];
            uint256 collateralAmount = userVault.info[collateralAddress].collateralAmount;
            uint256 debtBorrowedAmount = userVault.info[collateralAddress].debtBorrowedAmount;

            // To start we are assuming the user's CCR is 1, no collateral, no debt
            userVault.info[collateralAddress].collateralCoverageRatio = baseCollateralCoverageRatio;

            // The collateral amount can't be 0, if it is then we are sure there is not debt too
            if (collateralAmount == 0) continue;
            uint256 collateralFairLPPrice = this.fetchCollateralPrice(
                collateralAddress
            );
            userVault.info[collateralAddress].collateralValue = collateralAmount.mul(collateralFairLPPrice);
            newTotalCollateralValue = SafeMath.add(
                userVault.totalCollateralValue,
                userVault.info[collateralAddress].collateralValue
            );


            if (debtBorrowedAmount == 0) continue;
            uint256 timeDifference = uint256(
                currentTimestamp - userVault.info[collateralAddress].lastDebtUpdate
            );
            uint256 interestRateToBeApplied = timeDifference.mul(currentInterestPerSecond);
            uint256 accruedInterest = SafeMath.mul(
                debtBorrowedAmount,
                interestRateToBeApplied
            );

            // Update user's current DEBT amount
            uint256 newBorrowedDebtAmount = SafeMath.add(
                debtBorrowedAmount,
                accruedInterest
            );
            // TIP: Should be assert, using require to see issues faster
            require(
                newBorrowedDebtAmount > debtBorrowedAmount,
                "Deposit: new debtBorrowedAmount can not be less than the previous one"
            );
            userVault.info[collateralAddress].debtBorrowedAmount = newBorrowedDebtAmount;
            newTotalDebtBorrowedAmount = newTotalDebtBorrowedAmount.add(newBorrowedDebtAmount);
            // Don't forget to update the lastDebtUpdate timestamp
            userVault.info[collateralAddress].lastDebtUpdate = currentTimestamp;

            // Now calculate the current user's CCR
            uint256 thisCollateralCoverageRatio = getCollateralCoverageRatio(
                userVault.info[collateralAddress].collateralValue,
                userVault.info[collateralAddress].debtBorrowedAmount
            );

            userVault.info[collateralAddress].collateralCoverageRatio = thisCollateralCoverageRatio;
            currentUserVaultCCRs = currentUserVaultCCRs.add(thisCollateralCoverageRatio);
        }

        userVault.totalCollateralValue = newTotalCollateralValue;
        userVault.totalDebtBorrowedAmount = newTotalDebtBorrowedAmount;
        // Get the user's average CCR by dividing by all of their vaults CCR
        userVault.collateralCoverageRatio = currentUserVaultCCRs.div(vaultCollateralAddresses.length);
        return (userVault.collateralCoverageRatio, newTotalCollateralValue, newTotalDebtBorrowedAmount);
    }

    function getCollateralCoverageRatio(
        uint256 collateralValue,
        uint256 loanBorrowedValue
    ) internal view returns (uint256) {
        uint256 collateralCoverageRatio = platformDefaultDiscountApplied
            .mul(collateralValue)
            .div(loanBorrowedValue);
        return collateralCoverageRatio;
    }

    function calculateCollateralChunks(UserVaultInfo storage userVault)
        internal
        view
        returns (uint256[] memory)
    {
        uint256[] memory collateralChunks;
        for (
            uint256 index = 0;
            index < vaultCollateralAddresses.length;
            index++
        ) {
            address collateralAddress = vaultCollateralAddresses[index];
            // Calculate what is the fractional contribution to
            // each of the user's collateral
            uint256 collateralFraction = SafeMath.div(
                userVault.collateralValue[collateralAddress],
                userVault.totalCollateralValue
            );
            collateralChunks[index] = collateralFraction;
        }
        return collateralChunks;
    }

    function perSecondInterestRate(uint256 interestRate)
        internal
        pure
        returns (uint256)
    {
        uint256 interestRatePerSecond = SafeMath.div(
            SafeMath.mul(interestRate, decimal18Places),
            secondsInYear
        );
        return interestRatePerSecond;
    }

    event UserDepositedCollateral(
        uint256 vaultID,
        address collateralAddress,
        uint256 amountDeposited
    );
    event UserWithdrewCollateral(
        uint256 vaultID,
        address collateralAddress,
        uint256 amountWithdrawn
    );
    event UserBorrowedDebt(uint256 vaultID, address vaultOwner, uint256 amount);
    event UserRepayedDebt(uint256 vaultID, address vaultOwner, uint256 amount);
    event UserTransferredVault(
        address previousVaultOwnerAddress,
        address nextVaultOwnerAddress,
        uint256 collateralAmount,
        uint256 debtBorrowedAmount
    );
    event BuyRiskyVault(
        uint256 vaultID,
        // address previousVaultOwner,
        uint256 collateralAmount,
        uint256 debtBorrowedAmount,
        address newVaultOwner
    );
}
