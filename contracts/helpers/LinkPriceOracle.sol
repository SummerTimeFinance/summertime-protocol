// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

// NOTE: We use ChainLink compatible oracles to compare token values.
// ChainLink oracles provide all USD pairs with 8 digits shift currently.
// E.g. value 100,000,000 = 1 USD.
contract PriceOracle is Ownable {
    using SafeMath for uint256;

    struct PriceInfo {
        uint80 roundID;
        uint256 price;
        uint256 startedAt;
        uint256 timestamp;
        uint80 answeredInRound;
    }

    uint256 private constant decimalPlaces10 = 10**10;
    // The collateral token and it's price aggregator
    mapping(address => AggregatorV3Interface) public tokenAggregator;
    // Last acquired token to price mapping.
    mapping(address => PriceInfo) public tokenPriceFeed;

    // constructor() public { }

    // @dev: Returns the last stored price
    function getTokenThePrice(address _token) external view returns (uint256) {
        PriceInfo storage _tokenPriceFeed = tokenPriceFeed[_token];
        require(_tokenPriceFeed.price > 0, "PRICE: token price can not be 0");
        return _tokenPriceFeed.price;
    }

    function fetchCurrentTokenPrice(address _token) external returns (uint256) {
        AggregatorV3Interface _tokenPriceFeed = tokenAggregator[_token];
        (
            uint80 roundID,
            int256 price,
            uint256 startedAt,
            uint256 timestamp,
            uint80 answeredInRound
        ) = _tokenPriceFeed.latestRoundData();
        uint256 priceToUint = SafeCast.toUint256(price);

        // Check if the price returned is 8 or 18 decimals places
        // Do all Chainlink feeds return prices with 8 decimals of precision?
        // https://ethereum.stackexchange.com/q/92508
        if (_tokenPriceFeed.decimals() < 18) {
            priceToUint = priceToUint.mul(decimalPlaces10);
        }

        tokenPriceFeed[_token] = PriceInfo(
            roundID,
            priceToUint,
            startedAt,
            timestamp,
            answeredInRound
        );
        return priceToUint;
    }

    function createOrUpdateTokenPriceOracle(address _token, address _oracle)
        external
        onlyOwner
        returns (uint256)
    {
        tokenAggregator[_token] = AggregatorV3Interface(_oracle);
        return this.fetchCurrentTokenPrice(_token);
    }
}
