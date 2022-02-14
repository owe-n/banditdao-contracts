// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.11;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

interface IStakedBandit is IAccessControl, IERC20, IERC20Permit {
    function STAKING() external pure returns (bytes32);

    function index() external view returns (uint256);

    function rebaseProfit() external view returns (uint256);

    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;
    
    function totalSupply() external view override returns (uint256);

    function balanceOf(address account) external view override returns (uint256);

    function updateIndex(uint256 amount) external;

    function updateRebaseProfit(uint256 amount) external;
}