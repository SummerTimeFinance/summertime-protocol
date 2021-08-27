pragma solidity ^0.6.6;

/**
 * @title Compound's InterestRateModel Interface
 * @author Compound
 */
abstract InterestRateModel {
    /// @notice Indicator that this is an InterestRateModel contract (for inspection)
    bool public constant isInterestRateModel = true;

    /**
     * @notice Calculates the current borrow interest rate per block
     * @param totalCollateralValue The total value of the collateral the market has
     * @param totalDebtBorrowed The total amount of debt the market has outstanding
     * @param reserves The total amnount of reserves the market has
     * @return The borrow rate per block (as a percentage, and scaled by 1e18)
     */
    function getBorrowRate(
        uint256 totalCollateralValue,
        uint256 totalDebtBorrowed,
        uint256 reserves
    ) external view returns (uint256);

    /**
     * @notice Calculates the current supply interest rate per block
     * @param totalCollateralValue The total value of the collateral the market has
     * @param totalDebtBorrowed The total amount of debt the market has outstanding
     * @param reserves The total amnount of reserves the market has
     * @param reserveFactorMantissa The current reserve factor the market has
     * @return The supply rate per block (as a percentage, and scaled by 1e18)
     */
    function getSupplyRate(
        uint256 totalCollateralValue,
        uint256 totalDebtBorrowed,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) external view returns (uint256);
}
