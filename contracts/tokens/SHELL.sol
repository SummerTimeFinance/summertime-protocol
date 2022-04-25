// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20Capped.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/drafts/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract ShellStableCoin is ERC20, ERC20Burnable, ERC20Permit, AccessControl {
    uint256 internal _cap = 0;
    uint256 internal immutable decimalsPlaces18;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    constructor(uint256 cap_)
        public
        ERC20("SummerTime Shell Stablecoin", "SHELL")
        ERC20Permit("SummerTime Shell Stablecoin")
    {
        decimalsPlaces18 = 10**uint256(decimals());
        require(cap_ > 0, "ERC20Capped: cap is 0");
        _cap = cap_;
        // Grant the contract deployer the default admin role: it will be able
        // to grant and revoke any roles
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, msg.sender);
        _setupRole(BURNER_ROLE, msg.sender);
    }

    // @dev Returns the cap on the token's total supply.
    function cap() public view virtual returns (uint256) {
        return _cap;
    }

    function _mint(address account, uint256 amount)
        internal
        virtual
        override(ERC20)
    {
        require(hasRole(MINTER_ROLE, msg.sender), "Caller is not a minter");
        require(
            ERC20.totalSupply() + amount <= cap(),
            "SHELL: Max cap exceeded"
        );
        super._mint(account, amount);
    }

    function _updateCap(uint256 newCap_) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not an admin");
        require(
            newCap_ > 0 && newCap_ > ERC20.totalSupply(),
            "ERC20Capped: new cap is 0 or less than total supply"
        );
        _cap = newCap_;
    }

    function addMinter(address newMinter) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _setupRole(MINTER_ROLE, newMinter);
    }

    function addBurner(address newBurner) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _setupRole(BURNER_ROLE, newBurner);
    }

    function createMinterWithBurningPermission(address minterAndBurner) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _setupRole(MINTER_ROLE, minterAndBurner);
        _setupRole(BURNER_ROLE, minterAndBurner);
    }

    function _beforeTokenTransfer(
        address from,
        address recipient,
        uint256 amount
    ) internal virtual override(ERC20) {
        super._beforeTokenTransfer(from, recipient, amount);
        require(
            recipient != address(this),
            "beforeTransfer: invalid recipient"
        );
    }
}
