// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
// import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "../config/CollateralVaultConfig.sol";

import "../interfaces/FairLPPriceOracle.sol";

contract SummerTimeVault is Ownable, CollateralVaultConfig {
    using SafeMath for uint256;

    // Can be set to $25, same as the cost to opening a bank account
    uint256 public vaultOpeningFee = 0;
    // Initial set to: 0
    uint256 public vaultClosingFee = 0;

    // Our price source of each of the LP collateral on the platform
    FairLPPriceOracle fairLPPriceSource;

    // structure: mapping(collateralAddress => VaultConfig)
    mapping(address => VaultConfig) public vaultAvailable;
    address[] public vaultCollateralAddresses;

    // Check to see if any of the collateral being deposited by the user
    // is an accepted collateral by the protocol
    modifier isCollateralAccepted(address collateralAddress) {
        bool collateralExists = false;
        if (vaultAvailable[collateralAddress].token0 != address(0)) {
            collateralExists = true;
        }

        require(
            collateralExists,
            "isCollateralAccepted: COLLATERAL not available to borrow against."
        );
        _;
    }

    constructor(address fairLPPriceOracleAddress) internal {
        if (fairLPPriceOracleAddress == address(0)) {
            revert("VaultConstructor: Invalid price oracle address provided.");
        }
        fairLPPriceSource = FairLPPriceOracle(fairLPPriceOracleAddress);
    }

    function createNewCollateralVault(
        // string calldata displayName,
        // address token0Address,
        // address token1Address,
        // address token0PriceOracle,
        // address token1PriceOracle,
        // address collateralAddress, //#[commented] this is derived from token0 and token1
        // address strategyAddress,
        // address uniswapV2FactoryAddress,
        address[6] calldata LPTokenInformation,
        // address farmContractAddress, // this is only used in the strategy contract
        uint256 farmingContractIndex,
        uint256 discountApplied
    ) external onlyOwner returns (address) {
        if (LPTokenInformation.length < 5) {
            revert("createNewCollateralVault: Important vault configuration parameters missing.");
        }

        IUniswapV2Factory uniswapV2Factory = IUniswapV2Factory(
            LPTokenInformation[5]
        );
        address addressForLPPair = uniswapV2Factory.getPair(
            LPTokenInformation[0], // token0Address,
            LPTokenInformation[1]  // token1Address
        );
        if (addressForLPPair == address(0)) {
            revert("createNewCollateralVault: LP pair doesn't EXIST yet");
        }

        IUniswapV2Pair tokenPairsForLP = IUniswapV2Pair(addressForLPPair);
        if (
            tokenPairsForLP.token0() == LPTokenInformation[0] &&
            tokenPairsForLP.token1() == LPTokenInformation[1]
        ) {
            revert("createNewCollateralVault: pair token addresses aren't the same as provided");
        }

        VaultConfig storage newCollateralVault = vaultAvailable[
            addressForLPPair
        ];
        // Check if the vault already exists
        if (newCollateralVault.token0 != address(0)) {
            revert("createNewCollateralVault: VAULT EXISTS");
        }

        // newCollateralVault.displayName = displayName;
        // newCollateralVault.collateralTokenAddress = addressForLPPair;
        // token0, token1 can all be derived from the UniswapV2 interface
        newCollateralVault.token0 = tokenPairsForLP.token0();
        newCollateralVault.token1 = tokenPairsForLP.token1();
        newCollateralVault.token0PriceOracle = LPTokenInformation[2];
        newCollateralVault.token1PriceOracle = LPTokenInformation[3];
        newCollateralVault.price = fairLPPriceSource.getCurrentFairLPTokenPrice(addressForLPPair);
        // newCollateralVault.uniswapFactoryAddress = tokenPairsForLP.factory();
        // newCollateralVault.strategyAddress = LPTokenInformation[4];
        // @dev may use this in v2.0, may complicate a lot of things in this iteration
        newCollateralVault.discountApplied = 6e17;
        newCollateralVault.maxCollateralAmountAccepted = SafeMath.mul(
            uint256(1000),
            uint256(10**18)
        );
        // newCollateralVault.depositingPaused = false;
        // newCollateralVault.borrowingPaused = false;
        // newCollateralVault.disabled = false;

        // The discount provided to be applied should be larger than 1%
        if (discountApplied > 1e16) {
            newCollateralVault.discountApplied = discountApplied;
        }

        // @dev the default value 0 references PCS, so it doesn't have to be set
        if (farmingContractIndex != 0) {
            newCollateralVault.index = farmingContractIndex;
        }

        // Add vault collateral address to accepted this collateral type from users
        vaultCollateralAddresses.push(addressForLPPair);
        return addressForLPPair;
    }

    function getCollateralVaultInfo(address collateralAddress) external view returns (VaultConfig memory) {
         VaultConfig memory vault = vaultAvailable[collateralAddress];
         return vault;
    }

    function getCollateralVaultAddresses() external view returns (address[] memory) {
         return vaultCollateralAddresses;
    }

    function updatePriceOracle0Address(
        address collateralAddress,
        address newPriceOracle0Address
    ) external onlyOwner isCollateralAccepted(collateralAddress) returns (bool) {
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        vault.token0PriceOracle = newPriceOracle0Address;
        emit VaultPriceOracle0AddressUpdated(newPriceOracle0Address);
        return true;
    }

    function updatePriceOracle1Address(
        address collateralAddress,
        address newPriceOracle1Address
    ) external onlyOwner isCollateralAccepted(collateralAddress) returns (bool) {
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        vault.token1PriceOracle = newPriceOracle1Address;
        emit VaultPriceOracle1AddressUpdated(newPriceOracle1Address);
        return true;
    }

    function updateDiscountApplied(
        address collateralAddress,
        uint256 newDiscountApplied
    ) external onlyOwner isCollateralAccepted(collateralAddress) returns (bool) {
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        // Only update the collateral discount applied if it's less than the previous one
        // To prevent automated user liquidations that would happen after if you increased the discout
        if (vault.discountApplied > newDiscountApplied) {
            vault.discountApplied = newDiscountApplied;
            emit VaultCollateralDiscountAppliedUpdated(newDiscountApplied);
            return true;
        }
    }

    function updateMaxCollateralAmountAccepted(
        address collateralAddress,
        uint256 newMaxCollateralAmountAccept
    ) external onlyOwner isCollateralAccepted(collateralAddress) returns (bool) {
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        vault.maxCollateralAmountAccepted = newMaxCollateralAmountAccept;
        emit VaultMaxCollateralAmountAcceptedUpdated(
            newMaxCollateralAmountAccept
        );
        return true;
    }

    // Enable or disable the vault
    function toggleVaultActiveState(address collateralAddress, bool depositingState, bool borrowingState)
        external
        onlyOwner
        isCollateralAccepted(collateralAddress)
        returns (bool)
    {
        VaultConfig storage vault = vaultAvailable[collateralAddress];

        if (depositingState != vault.depositingPaused) vault.depositingPaused = !vault.depositingPaused;
        if (borrowingState != vault.borrowingPaused) vault.borrowingPaused = !vault.borrowingPaused;

        emit CollateralVaultOperationState(collateralAddress, vault.depositingPaused, vault.borrowingPaused);
        return vault.depositingPaused;
    }

    function getCurrentFairLPTokenPrice(address collateralAddress)
        external
        isCollateralAccepted(collateralAddress)
        returns (uint256)
    {
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        // Update the current price of the LP collateral (price oracle check)
        uint256 fairLPPrice = fairLPPriceSource.getCurrentFairLPTokenPrice(
            collateralAddress
        );
        vault.price = fairLPPrice;
        return fairLPPrice;
    }

    event NewCollateralVaultAvailable(
        address collateralAddress,
        address token0,
        address token1
    );
    event CollateralVaultOperationState(
        address collateralAddress,
        bool depositingState,
        bool borrowingState
    );
    event VaultFarmIndexAndPoolIDUpdated(
        uint256 previousFarmIndex,
        uint256 newFarmIndex,
        uint256 newFarmPoolID
    );
    event VaultPriceOracle0AddressUpdated(address newPriceOracle0Address);
    event VaultPriceOracle1AddressUpdated(address newPriceOracle1Address);
    event VaultDebtCeilingUpdated(uint256 newDebtCeiling);
    event VaultCollateralDiscountAppliedUpdated(
        uint256 newCollateralCoverageRatio
    );
    event VaultMaxCollateralAmountAcceptedUpdated(
        uint256 newMaxCollateralAmount
    );
}
