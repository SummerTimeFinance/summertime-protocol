// SPDX-License-Identifier: MIT
pragma solidity ^0.5.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SummerTimeLemonToken is ERC20, ERC20Permit, ERC20Capped, Ownable {
    // Maximum token cap is 500M
    uint256 private constant maximumTokenSupply = 500 * 1000000 * 10 ** decimals();
    // Initial amount minted to be used in Presale: 8M
    unit256 private constant presaleTokenAmount = 8 * 1000000 * 10 ** decimals();

    constructor()
        ERC20("SummerTime Lemons", "LEMON")
        ERC20Permit("SummerTime Lemons")
        ERC20Capped(maximumTokenSupply)
    {
        _mint(msg.sender, presaleTokenAmount);
    }

    function mint(address accountAddress, uint256 amount) public onlyOwner {
        _mint(accountAddress, amount);
    }
}
