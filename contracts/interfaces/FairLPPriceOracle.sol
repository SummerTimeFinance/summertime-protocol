// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

interface FairLPPriceOracle {
    function getLastTokenPrice(address _token) external view returns (uint256);

    function getCurrentTokenPrice(address _token) external returns (uint256);

    function getLastKnownFairLPTokenPrice(address _pairAddress)
        external
        view
        returns (uint256);

    function getCurrentFairLPTokenPrice(address pairAddress)
        external
        returns (uint256);
}
