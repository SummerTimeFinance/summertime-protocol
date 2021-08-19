// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./controllers/ShellDebtManager.sol";

contract SummerTimeCore is ShellDebtManager, Ownable {}
