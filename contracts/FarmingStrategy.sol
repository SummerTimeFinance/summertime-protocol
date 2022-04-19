// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./interfaces/IPancakeswapFarm.sol";

// NOTE: Pancake's masterchef PROD contract
// https://bscscan.com/address/0x73feaa1ee314f8c655e354234017be2193c9e24e#code

contract FarmingStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public immutable summerTimeToken;
    // For v1.0, our initial/first focus is PancakeSwap(PCS) farming contract
    address public immutable tokenBeingEarned;
    // The address of the farming contract eg. PCS, Thugs etc. for each collateral
    address[] internal collateralFarmingContracts;
    // The collateral farming pool ID for their respective collaterals
    mapping(address => uint256) internal collateralPoolIDs;

    // address[2] public earnedToToken0Path;
    // address[2] public earnedToToken1Path;
    // address[2] public earnedToSummerTimeTokenPath;
    // structure: mapping(collateralAddress => earnedToCollateralTokenAorB)
    // mapping (address => address[]) internal earnedTokenToCollateralSwapPath;

    uint256 public totalAmountStaked = 0;
    mapping(address => uint256) public userAmountStaked;

    uint256 public performanceFeePercentage = 450; // 4.5%
    uint256 public buyBackPercentage = 0;
    uint256 public slippageFactor = 9500; // 5% default slippage tolerance
    uint256 internal constant oneHunderedPercent = 10000; // 100 = 1%

    uint256 public lastEarnBlock = 0;

    address public uniswapLikeRouterAddress;
    address public performanceFeeCollectingAddress;
    address public buyBackSummerTimeDaoAddress;

    // @TODO: Questions to answer:
    // 1. The farming contract we are depositing into
    // 2. The collateral contract address
    // 3. The pool ID of the collateral in the farming contract
    // 4. The user amount to deposit
    // 5. What's tracking the user's staked amount
    // 6. What's tracking the total amount staked, so as to unstake and restake at will

    constructor(
        address _summerTimeToken,
        address _tokenBeingEarned,
        address _farmingContract, // Add PCS contract as the 1st contract
        address _uniswapLikeRouterAddress,
        address _performanceFeeCollectingAddress,
        address _buyBackSummerTimeDaoAddress
    ) internal {
        require(
            _summerTimeToken != address(0),
            "_summerTimeToken cannot be nil or blackhole address"
        );

        require(
            _tokenBeingEarned != address(0),
            "_tokenBeingEarned cannot be nil or blackhole address"
        );

        require(
            _farmingContract != address(0),
            "PCS _farmingContract cannot be nil or blackhole address"
        );

        require(
            _uniswapLikeRouterAddress != address(0),
            "_uniswapLikeRouterAddress cannot be nil or blackhole address"
        );

        require(
            _performanceFeeCollectingAddress != address(0),
            "_performanceFeeCollectingAddress cannot be nil or blackhole address"
        );

        require(
            _buyBackSummerTimeDaoAddress != address(0),
            "_buyBackSummerTimeDaoAddress cannot be nil or blackhole address"
        );

        summerTimeToken = _summerTimeToken;
        tokenBeingEarned = _tokenBeingEarned;
        collateralFarmingContracts.push(_farmingContract);
    }

    function addFarmingContract(address _farmingContract)
        public
        onlyOwner
        nonReentrant
    {
        require(
            _farmingContract != address(0),
            "farming contract cannot be nil or blackhole address"
        );

        collateralFarmingContracts.push(_farmingContract);
    }

    function addCollateral(address collateralAddress, uint256 collateralPoolID)
        public
        onlyOwner
        nonReentrant
    {
        require(
            collateralAddress != address(0),
            "collateral address can not be nil or blackhole address"
        );
        uint256 poolID = collateralPoolIDs[collateralAddress];
        // Check to see if the poolID hadn't been set before
        if (poolID == 0) {
            collateralPoolIDs[collateralAddress] = collateralPoolID;
        }
    }

    function deposit(
        uint256 farmIndex,
        address collateralAddress,
        uint256 depositAmount
    ) public onlyOwner nonReentrant returns (uint256) {
        IERC20(collateralAddress).transferFrom(
            address(msg.sender),
            address(this),
            depositAmount
        );

        userAmountStaked[msg.sender] = SafeMath.add(
            userAmountStaked[msg.sender],
            depositAmount
        );

        harvest(farmIndex, collateralAddress);
        farm(farmIndex, collateralAddress, depositAmount);
    }

    function farm(
        uint256 farmIndex,
        address collateralAddress,
        uint256 depositAmount
    ) internal virtual {
        // Get the correct farm, for now it should be just 0, for PCS
        address farmingContract = collateralFarmingContracts[farmIndex];
        IERC20(collateralAddress).safeIncreaseAllowance(
            farmingContract,
            depositAmount
        );

        uint256 pid = collateralPoolIDs[collateralAddress];
        uint256 currentBalanceNotStaked = IERC20(collateralAddress).balanceOf(
            address(this)
        );
        IPancakeswapFarm(farmingContract).deposit(pid, currentBalanceNotStaked);

        totalAmountStaked = SafeMath.add(totalAmountStaked, depositAmount);
    }

    function unfarm(
        uint256 farmIndex,
        address collateralAddress,
        uint256 withdrawAmount
    ) internal virtual {
        address farmingContract = collateralFarmingContracts[farmIndex];
        uint256 pid = collateralPoolIDs[collateralAddress];

        totalAmountStaked = SafeMath.sub(totalAmountStaked, withdrawAmount);

        IPancakeswapFarm(farmingContract).withdraw(pid, withdrawAmount);
    }

    function withdraw(
        uint256 farmIndex,
        address userAddress,
        address collateralAddress,
        uint256 withdrawAmount
    ) public virtual onlyOwner nonReentrant returns (uint256) {
        require(withdrawAmount > 0, "withdrawAmount <= 0");

        // Check to see if the amount to withdraw is larger than what the user had staked
        uint256 amountUserStaked = userAmountStaked[msg.sender];
        require(
            withdrawAmount < amountUserStaked,
            "amount larger than what the user staked"
        );

        harvest(farmIndex, collateralAddress);
        unfarm(farmIndex, collateralAddress, withdrawAmount);

        uint256 amountWantedByUser = IERC20(collateralAddress).balanceOf(
            address(this)
        );
        require(
            amountWantedByUser <= withdrawAmount,
            "amount wanted larger than withdrawal request"
        );

        userAmountStaked[msg.sender] = SafeMath.sub(
            userAmountStaked[msg.sender],
            withdrawAmount
        );

        IERC20(collateralAddress).safeTransfer(userAddress, withdrawAmount);
        return withdrawAmount;
    }

    // 1. Harvest farmed tokens
    // 2. Converts farmed tokens into equal portions of the collateral tokens
    // 3. Add the portions as liquidity and stake them
    function harvest(uint256 farmIndex, address collateralAddress)
        public
        nonReentrant
    {
        address farmingContract = collateralFarmingContracts[farmIndex];
        uint256 pid = collateralPoolIDs[collateralAddress];
        // Fool the contract you've withdrawn some amount
        // which is 0 triggering the contract to send you the earned CAKE
        IPancakeswapFarm(farmingContract).withdraw(pid, 0);

        // Get the amount earned, and then deduct the peformance fee & buyback fee
        uint256 amountEarned = IERC20(tokenBeingEarned).balanceOf(
            address(this)
        );
        amountEarned = deductPerformanceFee(amountEarned);
        amountEarned = deductBuyBackFee(amountEarned);

        IERC20(tokenBeingEarned).safeApprove(uniswapLikeRouterAddress, 0);
        IERC20(tokenBeingEarned).safeIncreaseAllowance(
            uniswapLikeRouterAddress,
            amountEarned
        );

        IUniswapV2Pair pairInfo = IUniswapV2Pair(collateralAddress);
        address token0Address = pairInfo.token0();
        address token1Address = pairInfo.token1();

        if (tokenBeingEarned != token0Address) {
            address[] memory earnedToToken0Path;
            earnedToToken0Path[0] = tokenBeingEarned;
            earnedToToken0Path[1] = token0Address;

            // Swap half earned to token0
            swapEarnedTokenToDesired(
                uniswapLikeRouterAddress,
                SafeMath.div(amountEarned, 2),
                slippageFactor,
                earnedToToken0Path,
                address(this),
                SafeMath.add(block.timestamp, 600)
            );
        }

        if (tokenBeingEarned != token1Address) {
            address[] memory earnedToToken1Path;
            earnedToToken1Path[0] = tokenBeingEarned;
            earnedToToken1Path[1] = token1Address;

            // Swap half earned to token1
            swapEarnedTokenToDesired(
                uniswapLikeRouterAddress,
                SafeMath.div(amountEarned, 2),
                slippageFactor,
                earnedToToken1Path,
                address(this),
                SafeMath.add(block.timestamp, 600)
            );
        }

        // Get want tokens, ie. add liquidity
        uint256 token0Amount = IERC20(token0Address).balanceOf(address(this));
        uint256 token1Amount = IERC20(token1Address).balanceOf(address(this));

        if (token0Amount > 0 && token1Amount > 0) {
            IERC20(token0Address).safeIncreaseAllowance(
                uniswapLikeRouterAddress,
                token0Amount
            );
            IERC20(token1Address).safeIncreaseAllowance(
                uniswapLikeRouterAddress,
                token1Amount
            );
            // Add liquidity
            IUniswapV2Router02(uniswapLikeRouterAddress).addLiquidity(
                token0Address,
                token1Address,
                token0Amount,
                token1Amount,
                0,
                0,
                address(this),
                SafeMath.add(block.timestamp, 600)
            );
        }

        lastEarnBlock = block.number;
        // farm(0, collateralAddress, 0);
    }

    // Deduct and send the performance fee to the collection address
    function deductPerformanceFee(uint256 amountEarned)
        internal
        returns (uint256)
    {
        if (amountEarned > 0 && performanceFeePercentage > 0) {
            uint256 performanceFee = amountEarned
                .mul(performanceFeePercentage)
                .div(oneHunderedPercent);
            IERC20(tokenBeingEarned).safeTransfer(
                performanceFeeCollectingAddress,
                performanceFee
            );
            amountEarned = amountEarned.sub(performanceFee);
        }

        return amountEarned;
    }

    // Deduct and send the buy back fee to the collection address
    function deductBuyBackFee(uint256 amountEarned) internal returns (uint256) {
        if (amountEarned > 0 && buyBackPercentage > 0) {
            uint256 buybackFeeAmount = amountEarned.mul(buyBackPercentage).div(
                oneHunderedPercent
            );
            IERC20(tokenBeingEarned).safeIncreaseAllowance(
                uniswapLikeRouterAddress,
                buybackFeeAmount
            );

            address[] memory swappingFromTokenAtoB;
            swappingFromTokenAtoB[0] = tokenBeingEarned;
            swappingFromTokenAtoB[1] = summerTimeToken;

            swapEarnedTokenToDesired(
                uniswapLikeRouterAddress,
                buybackFeeAmount,
                slippageFactor,
                swappingFromTokenAtoB,
                buyBackSummerTimeDaoAddress,
                SafeMath.add(block.timestamp, 600)
            );

            return amountEarned.sub(buybackFeeAmount);
        }

        return amountEarned;
    }

    function swapEarnedTokenToDesired(
        address _uniRouterAddress,
        uint256 _amountIn,
        uint256 _slippageFactor,
        address[] memory _path,
        address _to,
        uint256 _deadline
    ) internal virtual {
        IUniswapV2Router02 ammSwap = IUniswapV2Router02(_uniRouterAddress);
        uint256[] memory amounts = ammSwap.getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length.sub(1)];

        ammSwap.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amountIn,
            amountOut.mul(_slippageFactor).div(oneHunderedPercent),
            _path,
            _to,
            _deadline
        );
    }
}
