// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./config/SummerTimeCoreConfig.sol";
import "./controllers/SummerTimeCore.sol";
import "./controllers/UserVault.sol";

import "./tokens/SHELL.sol";

import "./interfaces/SummerTimeVaults.sol";
import "./interfaces/InterestRateModel.sol";
import "./interfaces/FarmingStrategy.sol";

contract ShellDebtManager is
    Ownable,
    ReentrancyGuard,
    SummerTimeCore,
    UserVault,
    ShellStableCoin
{
    using SafeERC20 for IERC20;
    // @dev the interest rate model contract used to depict the interest rate
    InterestRateModel platformInterestRateModel;
    FarmingStrategy farmingStrategy;
    SummerTimeVault summerTimeVaults;

    // Check to see if any of the collateral being deposited by the user
    // is an accepted collateral by the protocol
    modifier isCollateralAvailable(address collateralAddress) {
        bool collateralExists = false;
        SummerTimeVault.VaultConfig memory collateralVault = summerTimeVaults.getCollateralVaultInfo(
            collateralAddress
        );
        if (collateralVault.token0 != address(0)) {
            collateralExists = true;
        }

        require(
            collateralExists,
            "isCollateralAvailable: COLLATERAL not available to borrow against."
        );
        // require(collateralAddress != address(0), "Address is not blackhole address");
        _;
    }

    // @dev constructor will initialize SHELL with a cap (debt ceiling) of $100,000
    constructor(
        address summerTimeVaultsAddress,
        address interestRateModel,
        address farmingStrategyAddress
    )
        internal
        ShellStableCoin(summerTimeDebtCeiling)
    {
        require(
            interestRateModel != address(0),
            "DebtManager: interest rate model not provided"
        );
        // TODO: Create the treasury vault, to absorb liquidation collateral fee
        // And also to absorb & hold other supported assets such as USDC
        platformTreasuryAdminAddress = msg.sender;
        summerTimeVaults = SummerTimeVault(summerTimeVaultsAddress);
        platformInterestRateModel = InterestRateModel(interestRateModel);
        farmingStrategy = FarmingStrategy(farmingStrategyAddress);
    }

    function depositCollateral(address collateralAddress)
        external
        payable
        isCollateralAvailable(collateralAddress)
        onlyVaultOwner(msg.sender)
        nonReentrant
    {
        UserVaultInfo storage userVault = userVaults[msg.sender];

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

        // @TIP: Assignments between storage and memory (or from calldata) always create an independent copy.
        uint256 previousUserCollateralValue = userVault.totalCollateralValue;
        // Update user's collateral total value to the current value according to current market prices
        // IF the user has any DEBT, calculate & add to the DEBT the new accrued interest amount
        updateUserCollateralCoverageRatio(userVault);

        platformTotalCollateralValue = SafeMath.add(
            SafeMath.sub(platformTotalCollateralValue, previousUserCollateralValue),
            userVault.totalCollateralValue
        );

        SummerTimeVault.VaultConfig memory collateralVault = summerTimeVaults.getCollateralVaultInfo(collateralAddress);
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
        isCollateralAvailable(collateralAddress)
        onlyVaultOwner(msg.sender)
        nonReentrant
    {
        UserVaultInfo storage userVault = userVaults[msg.sender];
        // user must withdraw amount equal to or less than their collateral vault balance
        require(
            requestedAmountToWithdraw <= userVault.info[collateralAddress].collateralAmount,
            "Withdraw: vault doesn't have the amount of collateral requested"
        );

        uint256 newCollateralBalance = SafeMath.sub(
            userVault.info[collateralAddress].collateralAmount,
            requestedAmountToWithdraw
        );
        uint256 newCollateralValue = newCollateralBalance.mul(
            summerTimeVaults.getCurrentFairLPTokenPrice(collateralAddress)
        );

        // Get the new CCR according to the updated collateral value
        uint256 newCollateralCoverageRatio = getCollateralCoverageRatio(
            newCollateralValue,
            userVault.info[collateralAddress].debtBorrowedAmount
        );

        // Check if user's new CCR will be below the minimum required CCR
        if (newCollateralCoverageRatio < liquidationThresholdCCR.div(BASE_COLLATERAL_COVERAGE_RATIO)) {
            revert(
                "Withdrawal: would put vault below minimum debt/collateral ratio"
            );
        }

        // If all is well, update user's collateral amount
        userVault.info[collateralAddress].collateralAmount = newCollateralBalance;
        // user's previous total collateral value
        uint256 userPrevTotalCollateralValue = userVault.totalCollateralValue;
        updateUserCollateralCoverageRatio(userVault);

        platformTotalCollateralValue = SafeMath.add(
            SafeMath.sub(
                platformTotalCollateralValue,
                userPrevTotalCollateralValue
            ),
            userVault.totalCollateralValue
        );

        SummerTimeVault.VaultConfig memory collateralVault = summerTimeVaults.getCollateralVaultInfo(collateralAddress);
        // now send the amount to the vault owner's address
        farmingStrategy.withdraw(
            collateralVault.index,
            msg.sender,
            collateralAddress,
            requestedAmountToWithdraw
        );

        emit UserWithdrewCollateral(
            userVault.ID,
            collateralAddress,
            requestedAmountToWithdraw
        );
    }

    function borrowShellStableCoin(address collateralAddress, uint256 requestedBorrowAmount)
        external
        isCollateralAvailable(collateralAddress)
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

        UserVaultInfo storage userVault = userVaults[msg.sender];
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

        // Check if new CCR isn't over the base CCR, thus allow the user to borrow
        if (newCollateralCoverageRatio < liquidationThresholdCCR.div(BASE_COLLATERAL_COVERAGE_RATIO)) {
            revert(
                "SHELL: new borrow would put vault below the min accepted CCR"
            );
        }

        // If all is well, let the user borrow SHELL stablecoin for use
        userVault.info[collateralAddress].debtBorrowedAmount = newTotalDebtBorrowed;
        _mint(msg.sender, requestedBorrowAmount);

        emit UserBorrowedDebt(userVault.ID, msg.sender, requestedBorrowAmount);
    }

    function repayShellStablecoinDebt(address collateralAddress, uint256 requestedRepayAmount)
        external
        isCollateralAvailable(collateralAddress)
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

        UserVaultInfo storage userVault = userVaults[msg.sender];
        updateUserCollateralCoverageRatio(userVault);

        uint256 amountBeingRepaid = requestedRepayAmount;
        uint256 userCurrentDebtBorrowed = userVault.info[collateralAddress].debtBorrowedAmount;
        // Get the old user CCR
        uint256 oldCollateralCoverageRatio = userVault.info[collateralAddress].collateralCoverageRatio;
        // Check to see if the repayed amount is larger or equal than the total user debt
        // IF IT IS, only deduct the DEBT owed, and send back the rest to the user
        if (amountBeingRepaid >= userCurrentDebtBorrowed) {
            amountBeingRepaid = userCurrentDebtBorrowed;
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

    // If one of the user's vault CCR is below 0.95, it is susceptible to being partially liquidated
    function buyRiskyUserVault(address collateralAddress, address userVaultAddress)
        external
        isCollateralAvailable(collateralAddress)
        nonReentrant
    {
        // Check to see if the platformStabilityPool is provided
        if (
            platformStabilityPool != address(0) &&
            msg.sender == platformStabilityPool
        ) {
            revert("buyRiskyVault: disabled for the community");
        }

        UserVaultInfo storage liquidatorVault = userVaults[msg.sender];
        if (liquidatorVault.ID == 0) {
            revert("buyRiskyUserVault: liquidator vault doesn't exist");
        }

        UserVaultInfo storage riskyUserVault = userVaults[
            userVaultAddress
        ];
        // Check if the vault exists
        if (riskyUserVault.ID == 0) {
            revert("buyRiskyUserVault: user vault doesn't exist");
        }

        updateUserCollateralCoverageRatio(riskyUserVault);

        // Check to see if the user's DEBT/Collateral ratio (CCR) is above 0.95
        if (
            riskyUserVault.info[collateralAddress].collateralCoverageRatio >
            liquidationThresholdCCR.div(BASE_COLLATERAL_COVERAGE_RATIO)
        ) {
            revert(
                "buyRiskyUserVault: Vault is not below minumum CCR"
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

        // Take 4/9th's of the collateral and sell it to pay back the debt
        // Apply the liquidationIncentive & liquidationFee (10% and 0.5%)
        uint256 collateralToClaim = SafeMath.mul(
            debtAmountToBePaid,
            SafeMath.add(uint256(1), liquidationIncentive.div(100e18))
        );

        UserVaultInfo storage treasuryVault = userVaults[
            platformTreasuryAdminAddress
        ];

        // Cut the collateral from the user vault
        riskyUserVault.info[collateralAddress].collateralAmount = SafeMath.sub(
            riskyUserVault.info[collateralAddress].collateralAmount,
            collateralToClaim
        );

        if (treasuryVault.ID != 0) {
            // Move 0.5% collateral to be liquidated to our treasury vault
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
        uint256 currentUserVaultCCRs = BASE_COLLATERAL_COVERAGE_RATIO;
        address[] memory collateralVaultAddresses = summerTimeVaults.getCollateralVaultAddresses();

        // @info LOOP thru each available collateral getting the user's collateral amount
        // Use that amount to calculate their current total collateral value according
        // to the new price for each LP collateral
        for (
            uint256 index = 0;
            index < collateralVaultAddresses.length;
            index++
        ) {
            address collateralAddress = collateralVaultAddresses[index];
            CollateralVaultInfo storage userCollateralVault = userVault.info[collateralAddress];

            // To start we are assuming the user's CCR is 1, no collateral, no debt
            userCollateralVault.collateralCoverageRatio = BASE_COLLATERAL_COVERAGE_RATIO;

            // The collateral amount can't be 0, if it is then we are sure there is not debt too
            if (userCollateralVault.collateralAmount == 0) continue;
            uint256 collateralFairLPPrice = summerTimeVaults.getCurrentFairLPTokenPrice(
                collateralAddress
            );
            uint256 oldCollateralValue = userCollateralVault.collateralValue;
            userCollateralVault.collateralValue = SafeMath.mul(
                userCollateralVault.collateralAmount,
                collateralFairLPPrice
            );
            newTotalCollateralValue = SafeMath.add(
                SafeMath.sub(userVault.totalCollateralValue, oldCollateralValue),
                userCollateralVault.collateralValue
            );

            // If the user has any DEBT, update the accrual
            if (userCollateralVault.debtBorrowedAmount == 0) continue;
            uint256 timeDifference = uint256(
                currentTimestamp - userCollateralVault.lastDebtUpdate
            );
            uint256 interestRateToBeApplied = timeDifference.mul(currentInterestPerSecond);
            uint256 accruedInterest = SafeMath.mul(
                userCollateralVault.debtBorrowedAmount,
                interestRateToBeApplied
            );

            // Update user's current DEBT amount
            uint256 newBorrowedDebtAmount = SafeMath.add(
                userCollateralVault.debtBorrowedAmount,
                accruedInterest
            );
            // TIP: Should be assert, using require to see issues faster
            require(
                newBorrowedDebtAmount > userCollateralVault.debtBorrowedAmount,
                "CalcCRR: new debtBorrowedAmount can not be less than the previous one"
            );
            userCollateralVault.debtBorrowedAmount = newBorrowedDebtAmount;
            newTotalDebtBorrowedAmount = newTotalDebtBorrowedAmount.add(accruedInterest);
            // Don't forget to update the lastDebtUpdate timestamp
            userCollateralVault.lastDebtUpdate = currentTimestamp;

            // Now calculate the current user's CCR
            uint256 thisCollateralCoverageRatio = getCollateralCoverageRatio(
                userCollateralVault.collateralValue,
                userCollateralVault.debtBorrowedAmount
            );

            userCollateralVault.collateralCoverageRatio = thisCollateralCoverageRatio;
            currentUserVaultCCRs = currentUserVaultCCRs.add(thisCollateralCoverageRatio);
        }

        userVault.totalCollateralValue = newTotalCollateralValue;
        userVault.totalDebtBorrowedAmount = newTotalDebtBorrowedAmount;
        // Get the user's average CCR by dividing by all of their vaults CCR
        userVault.collateralCoverageRatio = currentUserVaultCCRs.div(collateralVaultAddresses.length);
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
    event BuyRiskyVault(
        uint256 vaultID,
        // address previousVaultOwner,
        uint256 collateralAmount,
        uint256 debtBorrowedAmount,
        address newVaultOwner
    );
}
