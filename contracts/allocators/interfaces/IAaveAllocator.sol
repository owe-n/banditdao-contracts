// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {Addresses} from "../../interfaces/IHelper.sol";

interface IAaveAllocator is IAccessControl {
    function BOND_DEPO() external pure returns (bytes32);
    
    function GOVERNOR() external pure returns (bytes32);

    function TREASURY() external pure returns (bytes32);

    function addressProvider() external view returns (address);

    function incentivesController() external view returns (address);

    function helper() external view returns (address);

    function referralCode() external view returns (uint16);

    function lastATokenBalance(address) external view returns (uint256);

    function getAddresses() external view returns (Addresses memory);

    function supplyToAave(address asset, uint256 amount) external returns (address aToken);

    function redeemFromAave(address asset, uint256 amount) external returns (uint256 amount_, uint256 rewards_);

    function getATokenAddress(address asset) external view returns (address aToken);
}