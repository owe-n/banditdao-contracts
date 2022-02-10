// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Addresses} from "./IHelper.sol";

struct BondParameters {
        uint256 duration;
        address aToken;
        address bondAsset;
        address oracle;
        bool isReserveAsset;
        bool isLiquidityToken;
        bool isLentOutOnAave;
        bool isStablecoin;
        bool useDynamicOracle;
    }

    struct DiscountParameters {
        uint256 amplitude;
        uint256 currentDebt;
        uint256 maxDebt;
        int256 verticalShift;
    }

interface IBondDepository is IAccessControl {
    function GOVERNOR() external pure returns (bytes32);

    function helper() external view returns (address);

    function bondStart(address) external view returns (uint256);

    function userMaxPayout(address) external view returns (uint256);

    function BNDTreleased(address) external view returns (uint256);

    function isPayoutWrapped(address) external view returns (bool);

    function getAddresses() external view returns (Addresses memory);

    function getBondParameters() external view returns (BondParameters memory);

    function getDiscountParameters() external view returns (DiscountParameters memory);

    function updateMaxDebt(uint256 newMaxDebt) external;

    function bond(address beneficiary, uint256 amount) external;

    function claim() external;
}