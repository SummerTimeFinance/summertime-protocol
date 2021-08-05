// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Capped.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/drafts/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ShellStableCoin is
    ERC20,
    ERC20Capped,
    ERC20Burnable,
    ERC20Permit,
    Ownable
{
    uint256 internal immutable decimalsPlaces18;

    constructor(uint256 debtCeilingAmount)
        public
        ERC20("SummerTime Shell Stablecoin", "SHELL")
        ERC20Permit("SummerTime Shell Stablecoin")
        // Maximum token cap is 500M
        ERC20Capped(debtCeilingAmount * 10**decimals())
    {
        decimalsPlaces18 = 10**decimals();
        // _mint(msg.sender, 0); // nothing to send to the user
    }

    function _mint(address account, uint256 amount)
        internal
        virtual
        override(ERC20)
    {
        require(
            ERC20.totalSupply() + amount <= cap(),
            "SHELL: Max cap exceeded"
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
}
