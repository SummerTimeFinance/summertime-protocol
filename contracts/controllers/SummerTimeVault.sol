// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";

import "../controllers/UserVault.sol";
import "../config/VaultConfig.sol";

contract SummmerTimeVault is Ownable, VaultCollateralConfig, UserVault {
    address private immutable uniswapFactoryAddress;
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
    mapping(address => VaultConfig) internal vaultAvailable;
    address[] internal vaultCollateralAddresses;

    // Check to see if any of the collateral being deposited by the user
    // is an accepted collateral by the protocol
    modifier collateralAccepted(address collateralAddress) {
        bool memory collateralExists = false;
        for (
            int256 index = 0;
            index < vaultCollateralAddresses.length;
            index++
        ) {
            if (collateralAddress == vaultCollateralAddresses[index]) {
                collateralExist = true;
                break;
            }
        }

        require(
            collateralExist,
            "collateralAccepted: COLLATERAL not available to borrow against."
        );
        _;
    }

    constructor(address _uniswapFactoryAddress) internal {
        if (_uniswapFactoryAddress == address(0)) {
            revert("SummerTimeVaultInit: Invalid factory address provided.");
        }
        uniswapFactoryAddress = _uniswapFactoryAddress;
    }

    function fetchCollateralPrice(address collateralAddress)
        external
        returns (uint256 fairLPPrice)
    {
        // Update the current price of the LP collateral (price oracle check)
        uint256 fairLPPrice = PriceOracle.getLastLPTokenPrice(
            collateralAddress
        );
        VaultConfig storage vault = vault[collateralAddress];
        vault.fairPrice = fairLPPrice;
    }

    function createNewCollateralVault(
        string collateralDisplayName,
        address token0Address,
        address token1Address,
        // address collateralAddress, // this is derived from token0 and token1
        uint256 minimumDebtCollateralRatio,
        // address farmContractAddress,
        // address strategyAddress,
        address token0PriceOracle,
        address token1PriceOracle
    ) external onlyOwner returns (VaultConfig) {
        if (bytes(collateralDisplayName).length > 0) {
            revert(
                "createNewCollateralVault: collateralDisplayName not provided"
            );
        }
        if (address(token0Address) != address(0)) {
            revert("createNewCollateralVault: token0Address not provided");
        }
        if (address(token1Address) != address(0)) {
            revert("createNewCollateralVault: token1Address not provided");
        }
        if (address(token0PriceOracle) != address(0)) {
            revert("createNewCollateralVault: token0PriceOracle not provided");
        }
        if (address(token1PriceOracle) != address(0)) {
            revert("createNewCollateralVault: token1PriceOracle not provided");
        }

        address addressForLPPair = UniswapV2Library.pairFor(
            uniswapFactoryAddress,
            token0Address,
            token1Address
        );
        IUniswapV2Pair tokenPairsForLP = IUniswapV2Pair(addressForLPPair);
        if (addressForLPPair == address(0)) {
            revert("createNewCollateralVault: LP pair doesn't EXIST");
        }

        // token0, token1 can all be derived from the UniswapV2 interface
        address token0 = tokenPairsForLP.token0();
        address token1 = tokenPairsForLP.token1();

        VaultConfig storage vault = vaultAvailable[addressForLPPair];
        // Check if the vault exists already
        if (vault.collateralAddress != address(0)) {
            revert("createNewCollateralVault: VAULT EXISTS");
        }

        vault = VaultConfig({
            collateralDisplayName: collateralDisplayName,
            collateralTokenAddress: addressForLPPair,
            token0: token0Address,
            token1: token1Address,
            token0PriceOracle: token0PriceOracle,
            token1PriceOracle: token1PriceOracle,
            minimumDebtCollateralRatio: minimumDebtCollateralRatio ||
                50 *
                10**17, // default: 1.5
            maxCollateralAmountAccepted: 1000 * 10**18
        });

        // Add vault collateral address to accepted collateral types
        vaultCollateralAddresses.push(addressForLPPair);

        return vault;
    }

    function updateCollateralName(
        address collateralAddress,
        string newCollateralDisplayName
    ) external onlyOwner collateralAccepted(collateralAddress) returns (bool) {
        if (bytes(newCollateralDisplayName).length == 0) {
            revert("CollateralName: invalid collateral name");
        }
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        vault.collateralDisplayName = newCollateralDisplayName;
        return true;
    }

    function updateFarmContractAddress(
        address collateralAddress,
        address farmContractAddress
    ) external onlyOwner collateralAccepted(collateralAddress) returns (bool) {
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        // TODO:
        // unstake those tokens, compound the harvested rewards
        // then restake/migrate them to the new farmContractAddress
        vault.farmContractAddress = farmContractAddress;
        emit VaultFarmContractAddressUpdated(farmContractAddress);
        return true;
    }

    function updateStrategyAddress(
        address collateralAddress,
        address newStrategyAddress
    ) external onlyOwner collateralAccepted(collateralAddress) returns (bool) {
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        // TODO:
        // unstake those tokens, compound the harvested rewards
        // then restake/migrate them to the new farmContractAddress
        vault.strategyAddress = newStrategyAddress;
        return true;
    }

    function updatePriceOracle1Address(
        address collateralAddress,
        address newPriceOracleAddress
    ) external onlyOwner collateralAccepted(collateralAddress) returns (bool) {
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        vault.priceOracleAddress = newPriceOracleAddress;
        emit VaultPriceOracleAddressUpdated(newPriceOracleAddress);
        return true;
    }

    function updatePriceOracle2Address(
        address collateralAddress,
        address newPriceOracle2Address
    ) external onlyOwner collateralAccepted(collateralAddress) returns (bool) {
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        vault.priceOracle2Address = newPriceOracle2Address;
        emit VaultPriceOracle2AddressUpdated(newPriceOracle2Address);
        return true;
    }

    function updateDebtCeiling(
        address collateralAddress,
        uint256 newDebtCeilingAmount
    ) external onlyOwner collateralAccepted(collateralAddress) returns (bool) {
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        vault.debtCeiling = newDebtCeilingAmount;
        emit VaultDebtCeilingUpdated(newDebtCeilingAmount);
        return true;
    }

    function updateDebtCollateralRatio(
        address collateralAddress,
        uint256 newDebtCollateralRatio
    ) external onlyOwner collateralAccepted(collateralAddress) returns (bool) {
        VaultConfig storage vault = vaultAvailable[collateralAddress];
        vault.minimumDebtCollateralRatio = newDebtCollateralRatio;
        emit VaultDebtCollateralRatioUpdated(newDebtCollateralRatio);
        return true;
    }

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

    event NewCollateralVaultAvailable(
        address collateralAddress,
        address token0,
        address token1
    );
    event CollateralVaultState(address collateralAddress, bool isDisabled);
    event VaultFarmContractAddressUpdated(address farmContractAddress);
    event VaultPriceOracle1AddressUpdated(address newPriceOracleAddress);
    event VaultPriceOracle2AddressUpdated(address newPriceOracle2Address);
    event VaultDebtCeilingUpdated(uint256 newDebtCeiling);
    event VaultDebtCollateralRatioUpdated(uint256 newDebtCollateralRatio);
    event VaultMaxCollateralAmountUpdated(uint256 newMaxCollateralAmount);
    event VaultDepositingState(bool isDisabled);
    event VaultBorrowingState(bool isDisabled);
}
