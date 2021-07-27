// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./config/SummerTimeCoreConfig.sol";
import "./controllers/SummerTimeVault.sol";
import "./tokens/SHELL.sol";

contract SummerTimeCore is Ownable, SummerTimeCoreConfig, ShellStableCoin, SummerTimeVault {
  // @dev constructor will initialize SHELL with a cap of $100,000
  // @param uint: summerTimeTotalDebtCeiling (global config variable)
  constructor() ShellStableCoin(summerTimeTotalDebtCeiling) {
    // Do some magic!
  }
}
