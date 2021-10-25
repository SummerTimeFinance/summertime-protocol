// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./controllers/ShellDebtManager.sol";

abstract contract SummerTimeCore is Ownable, ShellDebtManager {
    function updatePlatformStabilityPoolAddress(address newPlatformStabilityPool)
        external
        onlyOwner
        returns (bool)
    {
        require(
            newPlatformStabilityPool != address(0),
            "must not be nil or blackhole address"
        );
        platformStabilityPool = newPlatformStabilityPool;
        return true;
    }


    function updateMinimumDebtAmount(uint256 newMinimumDebtAmount)
        external
        onlyOwner
        returns (bool)
    {
        require(
            newMinimumDebtAmount > 0,
            "newMinimumDebtAmount must be an amount larger than 0"
        );
        minimumDebtAmount = newMinimumDebtAmount;
        return true;
    }

    function updateVaultLiquidationIncentive(uint256 newLiquidationIncentive)
        external
        onlyOwner
        returns (bool)
    {
        require(
            newLiquidationIncentive > 3e18,
            "newLiquidationIncentive must be an amount larger than 3%"
        );
        liquidationIncentive = newLiquidationIncentive;
        return true;
    }

    function updateLiquidationFee(uint256 newLiquidationFee)
        external
        onlyOwner
        returns (bool)
    {
        require(
            newLiquidationFee > 0,
            "newLiquidationFee must be an amount larger than 0"
        );
        liquidationFee = newLiquidationFee;
        return true;
    }

    function updateDebtBorrowingFee(uint256 newDebtBorrowingFee)
        external
        onlyOwner
        returns (bool)
    {
        require(
            newDebtBorrowingFee > 0,
            "newDebtBorrowingFee must be an amount larger than 0"
        );
        debtBorrowingFee = newDebtBorrowingFee;
        return true;
    }
}
