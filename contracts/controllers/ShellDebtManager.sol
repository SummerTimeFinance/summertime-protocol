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
        // Update the vault's fair LP price
        this.fetchCollateralPrice(collateralAddress);

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

        uint256 currentCollateralAmount = userVault.collateralAmount[
            collateralAddress
        ];
        uint256 newCollateralAmount = currentCollateralAmount.add(msg.value);
        require(
            newCollateralAmount > currentCollateralAmount,
            "depositCollateral: new total collateral should be more than previous"
        );
        // Update the user's current collateral amount & value
        userVault.collateralAmount[collateralAddress] = newCollateralAmount;

        // @TIP: Assignments between storage and memory
        // (or from calldata) always create an independent copy.
        uint256 previousUserCollateralValue = userVault.totalCollateralValue;
        platformTotalCollateralValue = SafeMath.sub(
            platformTotalCollateralValue,
            previousUserCollateralValue
        );

        // Update user's collateral total value to the current value according to current market prices
        // IF the user has any DEBT, calculate & add to the DEBT the new accrued interest amount
        updateUserCollateralCoverageRatio(userVault);

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
        uint256 amountToWithdraw
    )
        external
        payable
        collateralAccepted(collateralAddress)
        onlyVaultOwner(msg.sender)
        nonReentrant
    {
        UserVaultInfo storage userVault = platformUserVaults[msg.sender];
        uint256 currentCollateralBalance = userVault.collateralAmount[
            collateralAddress
        ];
        // user's previous total collateral value
        uint256 userPrevTotalCollateralValue = userVault.totalCollateralValue;

        require(
            amountToWithdraw <= currentCollateralBalance,
            "Vault doesn't have the amount of collateral requested"
        );

        uint256 newCollateralBalance = SafeMath.sub(
            currentCollateralBalance,
            amountToWithdraw
        );

        userVault.collateralAmount[collateralAddress] = newCollateralBalance;
        updateUserCollateralCoverageRatio(userVault);

        // Check if user's new CCR will be below the required CCR
        if (userVault.collateralCoverageRatio < baseCollateralCoverageRatio) {
            revert(
                "Withdrawal: would put vault below minimum debt/collateral ratio"
            );
        }

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
            amountToWithdraw
        );
        // msg.sender.transfer(amountToWithdraw);

        emit UserWithdrewCollateral(
            userVault.ID,
            collateralAddress,
            amountToWithdraw
        );
    }

    function borrowShellStableCoin(uint256 requestedBorrowAmount)
        external
        onlyVaultOwner(msg.sender)
        nonReentrant
    {
        UserVaultInfo storage userVault = platformUserVaults[msg.sender];
        // Update user's collateral total value according to current market prices
        // IF the user has any DEBT, update add the accrued interest rate to the user's DEBT
        updateUserCollateralCoverageRatio(userVault);

        // User must borrow an amount larger than 0
        require(
            requestedBorrowAmount > 0,
            "SHELL: Must borrow an amount above 0"
        );

        // Check if borrowing disabled globally
        require(protocolBorrowingPaused == false, "Borrowing is paused.");

        // Check if the global DEBT ceiling been hit
        uint256 SHELLTotalSupply = totalSupply();
        require(
            SHELLTotalSupply.add(requestedBorrowAmount) < ShellStableCoin.cap(),
            "SHELL: Debt ceiling hit, no more borrowing."
        );

        uint256 newTotalDebtBorrowed = SafeMath.add(
            userVault.debtBorrowedAmount,
            requestedBorrowAmount
        );
        uint256 newCollateralCoverageRatio = getCollateralCoverageRatio(
            userVault.totalCollateralValue,
            newTotalDebtBorrowed
        );
        // VaultConfig storage vault = vaultAvailable[collateralAddress];

        // Check if new CCR isn't over the base CCR, thus allow the user to borrow
        if (newCollateralCoverageRatio < baseCollateralCoverageRatio) {
            revert(
                "SHELL: new borrow would put vault below the min accepted CCR"
            );
        }
        // If the new CCR is all good, set the new DC ratio for user
        // TODO: Inform user the vault is close to the base CCR (frontend)
        userVault.collateralCoverageRatio = newCollateralCoverageRatio;

        // If all is well, let the user borrow SHELL stablecoin for use
        // Total debt borrowed is updated automatically in the SHELL smart contract
        userVault.debtBorrowedAmount = newTotalDebtBorrowed;

        // Mint & transfer SHELL borrowed to the user
        _mint(msg.sender, requestedBorrowAmount);
        emit UserBorrowedDebt(userVault.ID, msg.sender, requestedBorrowAmount);
    }

    function repayShellStablecoinDebt(uint256 requestedRepayAmount)
        external
        onlyVaultOwner(msg.sender)
        nonReentrant
    {
        UserVaultInfo storage userVault = platformUserVaults[msg.sender];
        // Update user's collateral value to the current value according to current market prices
        // IF the user has any DEBT, calculate & add to the DEBT the new accrued interest amount
        updateUserCollateralCoverageRatio(userVault);

        // User must deposit an amount larger than 0
        require(
            requestedRepayAmount > 0,
            "Repay: Must borrow an amount above 0"
        );

        // User must have the equivalent amount in the wallet
        require(
            balanceOf(msg.sender) >= requestedRepayAmount,
            "Repay: your balance is lesser than amount for repayment"
        );

        uint256 amountBeingRepaid = requestedRepayAmount;
        // Check to see if the repayed amount is larger or equal than the actual debt
        // In this scenario, only deduct the DEBT owed, and send back the rest to the user
        if (requestedRepayAmount >= userVault.debtBorrowedAmount) {
            amountBeingRepaid = userVault.debtBorrowedAmount;
            // amountBalance = requestedRepayAmount.sub(userVault.debtBorrowedAmount);
            // Send back the SHELL balance that was left after paying the DEBT
            // _transfer(address(this), msg.sender, amountBalance);
        }

        // Get the new debt/collateral ratio
        uint256 newCollateralCoverageRatio = getCollateralCoverageRatio(
            userVault.totalCollateralValue,
            userVault.debtBorrowedAmount
        );
        require(
            newCollateralCoverageRatio > userVault.collateralCoverageRatio,
            "Repay: new CCR should be less than previous user's CCR"
        );

        userVault.collateralCoverageRatio = newCollateralCoverageRatio;
        userVault.debtBorrowedAmount = SafeMath.sub(
            userVault.debtBorrowedAmount,
            amountBeingRepaid
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
        _transfer(msg.sender, platformTreasuryAdminAddress, amountToSendToReserves);

        // Burn the rest
        uint256 amountRepaidBeingBurned = SafeMath.sub(
            amountBeingRepaid,
            amountToSendToReserves
        );
        // Destroy the SHELL paid back
        _burn(msg.sender, amountRepaidBeingBurned);
        emit UserRepayedDebt(userVault.ID, msg.sender, amountBeingRepaid);
    }

    // A user's collateral coverage ratio should be above or equal to 0.95
    // If below the user is susceptible to being partially liquidated
    function buyRiskyUserVault(address userVaultAddress) external nonReentrant {
        // Check to see if the platformStabilityPool is not provided yet
        // And ensure the liquidator is the platformStabilityPool address
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
        uint256 currentUserCCR = updateUserCollateralCoverageRatio(
            riskyUserVault
        );

        // Check to see if the user's DEBT/Collateral ratio (CCR) is above the
        // liquidation threshold: 0.95
        if (
            currentUserCCR >
            liquidationThreshold.div(baseCollateralCoverageRatio)
        ) {
            revert(
                "buyRiskyUserVault: Vault is not below minumum debt/collateral ratio"
            );
        }

        uint256 debtAmountToBePaid = SafeMath.mul(
            riskyUserVault.debtBorrowedAmount,
            liquidationFraction
        );
        require(
            balanceOf(msg.sender) < debtAmountToBePaid,
            "buyRiskyUserVault: liquidator doesn't have enough to pay debt"
        );

        // This is where we partially liquidate the user's vault
        // Take 4/9th's of the collateral and sell it to pay back the debt
        // Apply the liquidationIncentive & liquidationFee (10% and 0.5%)
        uint256 collateralToClaim = SafeMath.mul(
            debtAmountToBePaid,
            SafeMath.add(uint256(1), liquidationIncentive.div(100e18))
        );
        // Calculate how much collateral you need to take from each vault
        uint256[] memory collateralChunks = calculateCollateralChunks(
            riskyUserVault
        );

        UserVaultInfo storage treasuryVault = platformUserVaults[
            platformTreasuryAdminAddress
        ];
        // Then migrate the chunk of collateral taken to the liquidator's vault
        for (uint256 index = 0; index < collateralChunks.length; index++) {
            address collateralAddress = vaultCollateralAddresses[index];
            // Cut the collateral from the user vault
            riskyUserVault.collateralAmount[collateralAddress] = SafeMath.sub(
                riskyUserVault.collateralAmount[collateralAddress],
                SafeMath.mul(collateralToClaim, collateralChunks[index])
            );
            // M<ove the collateral chunks to the liquidator vault
            liquidatorVault.collateralAmount[collateralAddress] = SafeMath.add(
                liquidatorVault.collateralAmount[collateralAddress],
                SafeMath.mul(collateralToClaim, collateralChunks[index])
            );

            // TODO: Make sure to bootstrap treasury vault in constructor
            // Move 0.5% collateral chunks to our treasury vault
            if (treasuryVault.ID != 0) {
                // revert("buyRiskyUserVault: treasury vault doesn't exist");
                treasuryVault.collateralAmount[collateralAddress] = SafeMath
                    .add(
                        treasuryVault.collateralAmount[collateralAddress],
                        SafeMath.mul(
                            collateralToClaim.mul(collateralChunks[index]),
                            liquidationFee.div(uint256(100e18))
                        )
                    );
            }
        }

        // Now burn the SHELL tokens that the liquidator offered to pay the debt
        _burn(msg.sender, debtAmountToBePaid);
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
            revert("Transfer: user already has a vault");
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
        userVault.totalCollateralValue = 0;

        // @info LOOP thru each available collateral getting the user's collateral amount
        // Use that amount to calculate their current total collateral value
        // according to the new price for each LP collateral
        for (
            uint256 index = 0;
            index < vaultCollateralAddresses.length;
            index++
        ) {
            address collateralAddress = vaultCollateralAddresses[index];
            if (userVault.collateralAmount[collateralAddress] > 0) {
                uint256 collateralAmount = userVault.collateralAmount[
                    collateralAddress
                ];
                uint256 fairLPPrice = this.fetchCollateralPrice(
                    collateralAddress
                );
                userVault.collateralValue[collateralAddress] = collateralAmount
                    .mul(fairLPPrice);
                userVault.totalCollateralValue = SafeMath.add(
                    userVault.totalCollateralValue,
                    userVault.collateralValue[collateralAddress]
                );
            }
        }

        return userVault.totalCollateralValue;
    }

    function updateUsersDebtValue(UserVaultInfo storage userVault)
        internal
        returns (uint256)
    {
        // the time past since last debt accrued update (in seconds)
        uint256 currentTimestamp = block.timestamp;
        uint256 timeDifference = uint256(
            currentTimestamp - userVault.lastDebtUpdate
        );
        uint256 interestRateToBeApplied = timeDifference.mul(
            perSecondInterestRate(
                platformInterestRateModel.getBorrowRate(
                    platformTotalCollateralValue,
                    // The SHELL supply units is also the platform's total debt value
                    totalSupply(),
                    platformTotalReserves
                )
            )
        );
        uint256 accruedInterest = SafeMath.mul(
            userVault.debtBorrowedAmount,
            interestRateToBeApplied
        );

        // Update user's current DEBT amount
        uint256 newBorrowedDebtAmount = SafeMath.add(
            userVault.debtBorrowedAmount,
            accruedInterest
        );
        // TIP: Should be assert, using require to see issues faster
        require(
            newBorrowedDebtAmount > userVault.debtBorrowedAmount,
            "Deposit: new debtBorrowedAmount can not be less than the previous one"
        );
        userVault.debtBorrowedAmount = newBorrowedDebtAmount;
        // Don't forget to update the lastDebtUpdate timestamp
        userVault.lastDebtUpdate = currentTimestamp;
        return newBorrowedDebtAmount;
    }

    // This is where we update the user's CCR
    function updateUserCollateralCoverageRatio(UserVaultInfo storage userVault)
        internal
        returns (uint256)
    {
        // initialize the CCR with the default value
        uint256 currentUserCCR = baseCollateralCoverageRatio;
        // 1st update the user's collateral value
        updateUserCollateralValue(userVault);

        if (userVault.debtBorrowedAmount > 0) {
            updateUsersDebtValue(userVault);
            // Now calculate the current user's CCR
            uint256 newCollateralCoverageRatio = getCollateralCoverageRatio(
                userVault.totalCollateralValue,
                userVault.debtBorrowedAmount
            );

            userVault.collateralCoverageRatio = newCollateralCoverageRatio;
            currentUserCCR = newCollateralCoverageRatio;
        }
        return currentUserCCR;
    }

    function getCollateralCoverageRatio(
        uint256 currentCollateralValue,
        uint256 loanValue
    ) internal view returns (uint256) {
        uint256 collateralCoverageRatio = platformDefaultDiscountApplied
            .mul(currentCollateralValue)
            .div(loanValue);
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
