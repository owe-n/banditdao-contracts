// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

interface IBanditLP is IERC20, IERC20Permit {}