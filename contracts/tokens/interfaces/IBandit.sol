// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

import {Addresses} from "../../interfaces/IHelper.sol";

interface IBandit is IAccessControl, IERC20, IERC20Permit {
    function MINTER() external pure returns (bytes32);

    function BURNER() external pure returns (bytes32);

    function getAddresses() external view returns (Addresses memory);

    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;

    function circulatingSupply() external view returns (uint256);
}