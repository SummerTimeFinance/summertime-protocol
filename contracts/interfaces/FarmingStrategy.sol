// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

interface FarmingStrategy {
    function addCollateral(address collateralAddress, uint256 collateralPoolID) external;

    function deposit(uint256 farmIndex, address collateralAddress, uint256 depositAmount) external returns (uint256);

    function withdraw(uint256 farmIndex, address userAddress, address collateralAddress, uint256 withdrawAmount) external returns (uint256);

    function harvest(uint256 farmIndex, address collateralAddress) external;
}
