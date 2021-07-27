// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ShellStableCoin is ERC20, ERC20Permit, ERC20Capped, Ownable {
    uint256 private immutable decimalsPlaces18;

    constructor(uint debtCeilingAmount)
        ERC20Detailed("SummerTime Shell Stablecoin", "SHELL", 18)
        ERC20Permit("SummerTime Shell Stablecoin")
        // Maximum token cap is 500M
        ERC20Capped(debtCeilingAmount * 10 ** decimals())
    {
        decimalsPlaces18 = 10 ** decimals();
        // _mint(msg.sender, 0); // nothing to send to the user
    }

    function _mint(address account, uint256 amount) internal override(ERC20, ERC20Capped) {
        require(ERC20.totalSupply() + amount <= cap(), "LEMON ERC20Capped: Max cap exceeded");
        super._mint(account, amount);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        require(recipient != address(this));
        return super.transfer(recipient, amount);
    }
}
