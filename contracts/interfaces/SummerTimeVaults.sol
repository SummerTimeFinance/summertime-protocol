// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;
pragma experimental ABIEncoderV2;

interface SummerTimeVault {
    struct VaultConfig {
        address token0;
        address token1;
        address token0PriceOracle;
        address token1PriceOracle;
        uint256 price;
        uint256 index;
        uint256 maxCollateralAmountAccepted;
        uint256 discountApplied;
        bool depositingPaused;
        bool borrowingPaused;
    }

    // mapping(address => VaultConfig) public vaultAvailable;
    // address[] public vaultCollateralAddresses;

    function getCollateralVaultInfo(address collateralAddress) external view returns (VaultConfig memory);

    function getCollateralVaultAddresses() external view returns (address[] memory);

    function getCurrentFairLPTokenPrice(address collateralAddress) external returns (uint256);
}
