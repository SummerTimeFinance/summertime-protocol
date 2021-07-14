// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SummerTimeLemonToken is ERC20, ERC20Permit, ERC20Capped, Ownable {
    // Maximum token cap is 500M
    uint256 private constant maximumTokenSupply = 500 * 1000000;
    // Initial amount minted to be used in Presale: 8M
    uint256 private constant presaleTokenAmount = 8 * 1000000;

    constructor()
        ERC20("SummerTime Lemons", "LEMON")
        ERC20Permit("SummerTime Lemons")
        // Maximum token cap is 500M
        ERC20Capped(500 * 1000000 * (10 ** uint256(18)))
    {
        _mint(msg.sender, presaleTokenAmount * 10 ** uint256(decimals()));
    }

    // TIP: Removed "virtual" to disallow any overriding of this function again
    function cap() public view override(ERC20Capped) returns (uint256) {
        return maximumTokenSupply * (10 ** decimals());
    }


    function _mint(address account, uint256 amount) internal override(ERC20, ERC20Capped) {
        require(ERC20.totalSupply() + amount <= cap(), "LEMON ERC20Capped: cap exceeded");
        super._mint(account, amount);
    }
}
