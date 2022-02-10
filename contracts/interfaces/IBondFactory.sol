// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {BondDepository} from "../BondDepository.sol";

interface IBondFactory is IAccessControl {
    function BOND_CREATOR() external pure returns (bytes32);

    function helper() external view returns (address);

    function getBond(address) external view returns (address);

    function allBonds(uint256) external view returns (address);

    function allBondsLength() external view returns (uint256);

    function createBond(
        address bondAsset,
        address oracle,
        uint256 amplitude,
        uint256 maxDebt,
        int256 verticalShift,
        bool isLiquidityToken,
        bool isStablecoin,
        bool useDynamicOracle,
        bool lendToAave
    ) external returns (BondDepository bond);
}