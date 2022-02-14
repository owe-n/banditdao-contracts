// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

interface IGovernanceBandit is IERC20, IERC20Permit {
    function sBNDT() external view returns (address);

    function wrap(uint256 amount) external returns (uint256 value);

    function unwrap(uint256 amount) external returns (uint256 value);

    function wrappedToStaked(uint256 amount) external view returns (uint256);

    function stakedToWrapped(uint256 amount) external view returns (uint256);
}