// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Capped.sol";
import "@openzeppelin/contracts/drafts/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SummerTimeToken is ERC20, ERC20Capped, ERC20Permit, Ownable {
    enum Allocations {
        MAXIMUM_SUPPLY,
        FARMING_REWARDS,
        COMMUNITY_RESERVES,
        TEAM,
        PRESALE,
        ECOSYSTEM_FUND,
        FOUNDATION
    }

    uint256 private constant oneMillion = 1000000;
    uint256 private immutable decimalsPlaces18;

    // SummerTime Finance LEMONS tokenomics
    mapping(Allocations => uint256) public Tokenomics;

    constructor()
        public
        ERC20("SummerTime Token", "SUMMER")
        ERC20Permit("SummerTime Token")
        // Maximum token cap is 500M
        ERC20Capped(500 * oneMillion * 10**decimals())
    {
        decimalsPlaces18 = 10**decimals();

        // The complete breakdown of how the SUMMMER token will be distributed;
        Tokenomics[Allocations.MAXIMUM_SUPPLY] = 500 * oneMillion;
        Tokenomics[Allocations.FARMING_REWARDS] = 150 * oneMillion;
        Tokenomics[Allocations.COMMUNITY_RESERVES] = 150 * oneMillion;
        Tokenomics[Allocations.TEAM] = 90 * oneMillion;
        Tokenomics[Allocations.PRESALE] = 30 * oneMillion;
        Tokenomics[Allocations.ECOSYSTEM_FUND] = 30 * oneMillion;
        Tokenomics[Allocations.FOUNDATION] = 50 * oneMillion;

        // TypeError: decimalsPlaces18 Immutable variables cannot be read during contract creation time
        _mint(msg.sender, Tokenomics[Allocations.PRESALE] * 10**decimals());
    }

    // TIP: Removed "virtual" to disallow any overriding of this function again
    function cap() public view override(ERC20Capped) returns (uint256) {
        return Tokenomics[Allocations.MAXIMUM_SUPPLY] * 10**decimals();
    }

    function _mint(address account, uint256 amount) internal override(ERC20) {
        require(
            ERC20.totalSupply() + amount <= cap(),
            "SUMMER ERC20Capped: Max cap exceeded"
        );
        super._mint(account, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address recipient,
        uint256 amount
    ) internal virtual override(ERC20, ERC20Capped) {
        super._beforeTokenTransfer(from, recipient, amount);
        require(
            recipient != address(this),
            "beforeTransfer: invalid recipient"
        );
    }

    // function updateTokenomics(Allocations alloc, uint256 amount) public onlyOwner return (Boolean) {
    //   Tokenomics[alloc] = amount ** decimalsPlaces18;
    // }
}
