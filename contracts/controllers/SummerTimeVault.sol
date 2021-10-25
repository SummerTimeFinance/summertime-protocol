// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
// import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "../config/GeneralVaultConfig.sol";
import "../config/CollateralVaultConfig.sol";
import "../controllers/UserVault.sol";

import "../interfaces/FairLPPriceOracle.sol";

// The following collateral addresses will be supported (progressively):
// BTCB-ETH (old is gold, proven) [127M]
// BTCB-BUSD [118M] 
// ETH-BNB [139M]
// BTCB-BNB [118M]
// BUSD-BNB [460M]
// USDT-BNB [230M]
// CAKE-BNB (has largest liquidity) [600M]
// Stablecoin LPs:
// USDC-BUSD [122M]
// USDT-BUSD [289M]
// USDC-USDT [90M]
// Total addressable market size: $2.2B (BSC, using PancakeSwap only)
// current collaterals that are accepted

contract SummerTimeVault is Ownable, GeneralVaultConfig, CollateralVaultConfig, UserVault {
    using SafeMath for uint256;

    FairLPPriceOracle internal fairLPPriceSource;
    // structure: mapping(collateralAddress => VaultConfig)
    mapping(address => VaultConfig) internal vaultAvailable;
    address[] internal vaultCollateralAddresses;

    // Check to see if any of the collateral being deposited by the user
    // is an accepted collateral by the protocol
    modifier collateralAccepted(address collateralAddress) {
        bool collateralExists = false;
        for (
            uint256 index = 0;
            index < vaultCollateralAddresses.length;
            index++
        ) {
            if (collateralAddress == vaultCollateralAddresses[index]) {
                collateralExists = true;
                break;
            }
        }

        require(
            collateralExists,
            "collateralAccepted: COLLATERAL not available to borrow against."
        );
        _;
    }

    constructor(address fairLPPriceOracleAddress) internal {
        if (fairLPPriceOracleAddress == address(0)) {
            revert(
                "SummerTimeVaultConstructor: Invalid factory address provided."
            );
        }
        fairLPPriceSource = FairLPPriceOracle(fairLPPriceOracleAddress);
        // Warning: that external functions of a contract cannot be called while it is being constructed.
        // this.createUserVault(msg.sender);
    }

    function createNewCollateralVault(
        string memory displayName,
        address token0Address,
        address token1Address,
        address token0PriceOracle,
        // address collateralAddress, // this is derived from token0 and token1
        address token1PriceOracle,
        address uniswapV2FactoryAddress,
        uint256 farmingContractIndex,
        uint256 discountApplied,
        // address farmContractAddress, // this is only used in the strategy contract
        address strategyAddress
    ) external onlyOwner returns (address) {
        if (bytes(displayName).length > 0) {
            revert("createNewCollateralVault: displayName not provided");
        }
        if (token0Address != address(0)) {
            revert("createNewCollateralVault: token0Address not provided");
        }
        if (token1Address != address(0)) {
            revert("createNewCollateralVault: token1Address not provided");
        }
        if (token0PriceOracle != address(0)) {
            revert("createNewCollateralVault: token0PriceOracle not provided");
        }
        if (token1PriceOracle != address(0)) {
            revert("createNewCollateralVault: token1PriceOracle not provided");
        }
        if (strategyAddress != address(0)) {
            revert("createNewCollateralVault: strategyAddress not provided");
        }
        if (uniswapV2FactoryAddress != address(0)) {
            revert(
                "createNewCollateralVault: uniswapFactoryAddress not provided"
            );
        }

        IUniswapV2Factory uniswapV2Factory = IUniswapV2Factory(
            uniswapV2FactoryAddress
        );
        address addressForLPPair = uniswapV2Factory.getPair(
            token0Address,
            token1Address
        );
        if (addressForLPPair == address(0)) {
            revert("createNewCollateralVault: LP pair doesn't EXIST yet");
        }

        IUniswapV2Pair tokenPairsForLP = IUniswapV2Pair(addressForLPPair);
        // token0, token1 can all be derived from the UniswapV2 interface
        address token0 = tokenPairsForLP.token0();
        address token1 = tokenPairsForLP.token1();
        require(
            token0 == token0Address && token1 == token1Address,
            "createNewCollateralVault: pair token addresses aren't the same as provided"
        );

        VaultConfig storage newCollateralVault = vaultAvailable[
            addressForLPPair
        ];
        // Check if the vault already exists
        if (newCollateralVault.collateralTokenAddress != address(0)) {
            revert("createNewCollateralVault: VAULT EXISTS");
        }

        newCollateralVault.displayName = displayName;
        newCollateralVault.collateralTokenAddress = addressForLPPair;
        newCollateralVault.token0 = token0;
        newCollateralVault.token1 = token1;
        newCollateralVault.token0PriceOracle = token0PriceOracle;
        newCollateralVault.token1PriceOracle = token1PriceOracle;
        newCollateralVault.fairPrice = fairLPPriceSource.getLastLPTokenPrice(
            addressForLPPair
        );
        newCollateralVault.uniswapFactoryAddress = tokenPairsForLP.factory();
        // newCollateralVault.farmContractAddress = uniswapFactoryAddress;
        newCollateralVault.strategyAddress = strategyAddress;
        // @dev may use this in v2.0, may complicate a lot of things in this iteration
        newCollateralVault.discountApplied = 5e17;
        newCollateralVault.maxCollateralAmountAccepted = SafeMath.mul(
            uint256(1000),
            uint256(10**18)
        );
        newCollateralVault.depositingPaused = false;
        newCollateralVault.borrowingPaused = false;
        newCollateralVault.disabled = false;

        if (discountApplied > 1e16) {
            newCollateralVault.discountApplied = discountApplied;
        }

        // @dev the default value 0 references PCS, so it doesn't have to be set
        if (farmingContractIndex != 0) {
            newCollateralVault.index = farmingContractIndex;
        }

        // Add vault collateral address to accepted collateral types
        vaultCollateralAddresses.push(addressForLPPair);
        return addressForLPPair;
    }

    function updateCollateralName(
        address collateralAddress,
        string memory newDisplayName
    ) external onlyOwner collateralAccepted(collateralAddress) returns (bool) {
        if (bytes(newDisplayName).length == 0) {
            revert("CollateralName: invalid collateral name");
        }
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        vault.displayName = newDisplayName;
        return true;
    }

    function updateVaultFarmIndexAndPoolId(
        address collateralAddress,
        uint256 newFarmIndex,
        uint256 newFarmPoolID
    ) external onlyOwner collateralAccepted(collateralAddress) returns (bool) {
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        require(
            vault.index != newFarmIndex,
            "newFarmIndex provided is similar with current index in storage"
        );
        require(
            vault.farmPoolID != newFarmPoolID,
            "newFarmPoolID provided is similar with current farmPoolID in storage"
        );

        // TODO:
        // unstake those tokens, compound the harvested rewards
        // then restake/migrate them to the new index
        uint256 previousFarmIndex = vault.index;
        vault.index = newFarmIndex;
        emit VaultFarmIndexAndPoolIDUpdated(previousFarmIndex, newFarmIndex, newFarmPoolID);
        return true;
    }

    function updateStrategyAddress(
        address collateralAddress,
        address newStrategyAddress
    ) external onlyOwner collateralAccepted(collateralAddress) returns (bool) {
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        // TODO:
        // unstake those tokens, compound the harvested rewards
        // then restake/migrate them to the new newStrategyAddress
        vault.strategyAddress = newStrategyAddress;
        return true;
    }

    function updatePriceOracle0Address(
        address collateralAddress,
        address newPriceOracle0Address
    ) external onlyOwner collateralAccepted(collateralAddress) returns (bool) {
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        vault.token0PriceOracle = newPriceOracle0Address;
        emit VaultPriceOracle0AddressUpdated(newPriceOracle0Address);
        return true;
    }

    function updatePriceOracle1Address(
        address collateralAddress,
        address newPriceOracle1Address
    ) external onlyOwner collateralAccepted(collateralAddress) returns (bool) {
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        vault.token1PriceOracle = newPriceOracle1Address;
        emit VaultPriceOracle1AddressUpdated(newPriceOracle1Address);
        return true;
    }

    // function updateDebtCeiling(
    //     address collateralAddress,
    //     uint256 newDebtCeilingAmount
    // ) external onlyOwner collateralAccepted(collateralAddress) returns (bool) {
    //     VaultConfig storage vault = vaultAvailable[collateralAddress];
    //     vault.debtCeiling = newDebtCeilingAmount;
    //     emit VaultDebtCeilingUpdated(newDebtCeilingAmount);
    //     return true;
    // }

    // function updateCollateralCoverageRatio(
    //     address collateralAddress,
    //     uint256 newCollateralCoverageRatio
    // ) external onlyOwner collateralAccepted(collateralAddress) returns (bool) {
    //     VaultConfig storage vault = vaultAvailable[collateralAddress];
    //     vault.minimumDebtCollateralRatio = newCollateralCoverageRatio;
    //     emit VaultCollateralCoverageRatioUpdated(newCollateralCoverageRatio);
    //     return true;
    // }

    function updateMaxCollateralAmountAccepted(
        address collateralAddress,
        uint256 newMaxCollateralAmountAccept
    ) external onlyOwner collateralAccepted(collateralAddress) returns (bool) {
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        vault.maxCollateralAmountAccepted = newMaxCollateralAmountAccept;
        emit VaultMaxCollateralAmountAcceptedUpdated(
            newMaxCollateralAmountAccept
        );
        return true;
    }

    // Enable or disable the vault
    function toggleVaultActiveState(address collateralAddress)
        external
        onlyOwner
        collateralAccepted(collateralAddress)
        returns (bool)
    {
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        vault.disabled = !vault.disabled;
        emit CollateralVaultState(collateralAddress, vault.disabled);
        return vault.disabled;
    }

    function toggleDepositingState(address collateralAddress)
        external
        onlyOwner
        collateralAccepted(collateralAddress)
        returns (bool)
    {
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        vault.depositingPaused = !vault.depositingPaused;
        emit VaultDepositingState(vault.depositingPaused);
        return vault.depositingPaused;
    }

    function toggleBorrowingState(address collateralAddress)
        external
        onlyOwner
        collateralAccepted(collateralAddress)
        returns (bool)
    {
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        vault.borrowingPaused = !vault.borrowingPaused;
        emit VaultBorrowingState(vault.borrowingPaused);
        return vault.borrowingPaused;
    }

    function fetchCollateralPrice(address collateralAddress)
        external
        collateralAccepted(collateralAddress)
        returns (uint256)
    {
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        // Update the current price of the LP collateral (price oracle check)
        uint256 fairLPPrice = fairLPPriceSource.getLastLPTokenPrice(
            collateralAddress
        );
        vault.fairPrice = fairLPPrice;
        return fairLPPrice;
    }

    event NewCollateralVaultAvailable(
        address collateralAddress,
        address token0,
        address token1
    );
    event CollateralVaultState(address collateralAddress, bool isDisabled);
    event VaultFarmIndexAndPoolIDUpdated(uint256 previousFarmIndex, uint256 newFarmIndex, uint256 newFarmPoolID);
    event VaultPriceOracle0AddressUpdated(address newPriceOracle0Address);
    event VaultPriceOracle1AddressUpdated(address newPriceOracle1Address);
    event VaultDebtCeilingUpdated(uint256 newDebtCeiling);
    event VaultCollateralCoverageRatioUpdated(
        uint256 newCollateralCoverageRatio
    );
    event VaultMaxCollateralAmountAcceptedUpdated(
        uint256 newMaxCollateralAmount
    );
    event VaultDepositingState(bool isDisabled);
    event VaultBorrowingState(bool isDisabled);
}
