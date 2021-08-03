// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../libraries/MathUtils.sol";

// @reference https://blog.alphafinance.io/fair-lp-token-pricing/
// @reference (Converting Fixed Point Values in the Binary Numerical System) https://cutt.ly/cQzTpyn
contract FairLPPriceOracle is PriceOracle {
    using SafeMath for uint256;
    using MathUtils for uint256;

    /// @dev Return the value of the given input as ETH per unit
    /// @param address The Uniswap token pair to check the value.
    function getETHPx(address pairAddress)
        external
        view
        override
        returns (uint256)
    {
        IUniswapV2Pair pairInfo = IUniswapV2Pair(pairAddress);
        address token0 = pairInfo.token0();
        address token1 = pairInfo.token1();
        uint256 totalSupply = pairInfo.totalSupply();

        (uint256 reserveAmount0, uint256 reserveAmount1, ) = lpPair
            .getReserves();
        uint256 sqrtR = MathUtils.sqrt(
            SafeMath.mul(reservereserveAmount0, reserveAmount1)
        );

        uint256 tokenPrice0 = PriceOracle.getLastTokenPrice(token0);
        uint256 tokenPrice1 = PriceOracle.getLastTokenPrice(token1);
        uint256 sqrtP = MathUtils.sqrt(SafeMath.mul(tokenPrice0, tokenPrice1));

        return
            SafeMath.div(
                SafeMath.mul(2, SafeMath.mul(sqrtR, sqrtP)),
                totalSupply
            );
    }
}
