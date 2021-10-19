// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./interfaces/InterestRateModel.sol";

/// @notice this is only a temporary solution before we write a quadratic equation
// to actively calculate the right interest rate dependent on collateral vs debt utilization
contract SimpleInterestRateModel is Ownable, InterestRateModel {
    using SafeMath for uint256;
    // base interest rate is 0.5%
    uint256 internal constant baseInterestRate = 5e17;

    // @note setting this to 0, due to the above notice
    uint256 internal platformInterestRate = 0;

    function getBorrowRate(
        uint256 totalCollateralValue,
        uint256 totalDebtBorrowed,
        uint256 reserves
    ) external override returns (uint256) {
        return SafeMath.add(platformInterestRate, baseInterestRate);
    }

    function getSupplyRate(
        uint256 totalCollateralValue,
        uint256 totalDebtBorrowed,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) external override returns (uint256) {
        return SafeMath.add(0, baseInterestRate);
    }
}
