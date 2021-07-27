// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";
// import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "../controllers/UserVault.sol";
import "../config/VaultConfig.sol";

contract SummerTimeVault is Ownable, VaultCollateralConfig, UserVault {
    struct GeneralVaultInfo {
        // This collateral vault specific debt ceiling
        uint256 vaultDebtCeiling;
        // Default will be 50%, meaning user can borrow only up to 50% of their collateral value
        // Set to 51 to allow user to actually borrow up to 50% of it
        uint256 minimumDebtCollateralRatio;
        // Initially set to worth $1000, if 0, it means it's unlimited
        uint256 maximumAmountOfCollateralAccepted;
        // Both initialized with 0;
        uint256 currentTotalCollateralDeposited;
        uint256 currentTotalDebtBorrowed;
        // For pausing depositing or borrowing, incase there is a need to do so
        bool depositingPaused;
        bool borrowingPaused;
        // is this specific collateral vault disabled
        bool disabled;
    }

    address[] internal vaultCollateralAddresses;
    mapping(address => VaultInformation) internal vaultInformation;
    mapping(address => GeneralVaultInfo) internal generalVaultInfo;

    modifier vaultCollateralExists(address collateralAddress) {
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
            "vaultCollateralExists: COLLATERAL NOT AVAILABLE FOR BORROWING AGAINST"
        );
        _;
    }

    // token0Name, token1Name, token0, token1 can all be derived from the UniswapV2 interface
    constructor(
        string collateralDisplayName,
        address collateralTokenAddress,
        address collateralAddress,
        address stakingAddress,
        address strategyAddress,
        address priceOracleAddress
    ) {
        require(
            bytes(collateralDisplayName).length > 0,
            "VAULT: collateralDisplayName not provided"
        );
        require(
            address(collateralTokenAddress) != address(0),
            "VAULT: collateralTokenAddress not provided"
        );
        // require(address(stakingAddress) != address(0), "VAULT: stakingAddress not provided");
        // require(address(strategyAddress) != address(0), "VAULT: strategyAddress not provided");
        require(
            address(priceOracleAddress) != address(0),
            "VAULT: priceOracleAddress not provided"
        );

        IUniswapV2Pair tokenPairsForLP = IUniswapV2Pair(collateralTokenAddress);
        token0 = tokenPairsForLP.token0();
        token1 = tokenPairsForLP.token1();
    }

    function setCollateralName(
        address collateralAddress,
        string newCollateralDisplayName
    ) public onlyOwner vaultCollateralExists(collateralAddress) returns (bool) {
        if (bytes(newCollateralDisplayName).length > 0) return false;
        VaultInformation storage vault = vaultInformation[collateralAddress];
        vault.collateralDisplayName = newCollateralDisplayName;
        return true;
    }

    function setStakingAddress(
        address collateralAddress,
        address newStakingAddress
    ) public onlyOwner vaultCollateralExists(collateralAddress) returns (bool) {
        VaultInformation storage vault = vaultInformation[collateralAddress];
        // TODO: Check the previous staking address doesnt have tokens with it already
        // If it does, unstake those tokens and migrate them to the new stakingAddress
        vault.stakingAddress = newStakingAddress;
        return true;
    }

    function setStrategyAddress(
        address collateralAddress,
        address newStrategyAddress
    ) public onlyOwner vaultCollateralExists(collateralAddress) returns (bool) {
        VaultInformation storage vault = vaultInformation[collateralAddress];
        vault.strategyAddress = newStrategyAddress;
        return true;
    }

    function setPriceOracleAddress(
        address collateralAddress,
        address newPriceOracleAddress
    ) public onlyOwner vaultCollateralExists(collateralAddress) returns (bool) {
        VaultInformation storage vault = vaultInformation[collateralAddress];
        vault.priceOracleAddress = newPriceOracleAddress;
        return true;
    }

    function transferUserDebtFromVault(
        address newVaultOwnerAddress,
        address collateralAddress
    ) external onlyVaultOwner returns (bool) {
        UserVaultInfo storage userVaultInfo = userVaults[msg.sender];
        UserVaultInfo storage newVaultOwnerInfo = userVaults[
            newVaultOwnerAddress
        ];

        // If the new user doesn't have a vault, create one on the go
        if (newVaultOwnerInfo.ID == 0) {
            super.createUserVault(newVaultOwnerAddress);
        }

        // TODO:
        // get user's debt/collateral ratio,
        // then migrate the debt to the new vault along with enough collateral
        // according to the user's debt/collateral ratio
    }

    event NewCollateralVaultAvailable(
        address vaultCollateralAddress,
        address token0,
        address token1
    );
    // @dev: if borrowingDisabled is left in default mode (false),
    // then it's deposits that have been disabled
    event CollateralVaultDisabled(
        address vaultCollateralAddress,
        bool borrowingDisabled
    );
}
