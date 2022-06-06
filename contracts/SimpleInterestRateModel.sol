// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./interfaces/InterestRateModel.sol";

/// @notice this is only a temporary solution before we write a quadratic equation
/// to actively calculate the right interest rate dependent on collateral vs debt utilization
contract SimpleInterestRateModel is Ownable, InterestRateModel {
    using SafeMath for uint256;
    // base interest rate should 0.5%, will set to 0 for launch only
    uint256 internal constant BASE_INTEREST_RATE = 0;

    // @note setting this to 0
    uint256 public platformInterestRate = 0;

    function getBorrowRate(
        uint256 totalCollateralValue,
        uint256 totalDebtBorrowed,
        uint256 reserves
    ) external override returns (uint256) {
        uint256 protocolCurrentCCR = SafeMath.div(totalDebtBorrowed, totalCollateralValue.add(reserves));
        uint256 newInterestRate = SafeMath.mul(protocolCurrentCCR, platformInterestRate);
        return SafeMath.add(newInterestRate, BASE_INTEREST_RATE);
    }

    function getSupplyRate(
        uint256 totalCollateralValue,
        uint256 totalDebtBorrowed,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) external override returns (uint256) {
        uint256 protocolCurrentCCR = SafeMath.div(totalDebtBorrowed, totalCollateralValue.add(reserves));
        uint256 newInterestRate = SafeMath.mul(protocolCurrentCCR, platformInterestRate);
        return SafeMath.add(newInterestRate, BASE_INTEREST_RATE);
    }
}
