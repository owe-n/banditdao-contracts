// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {BondDepository} from "./BondDepository.sol";

import {Addresses, IHelper} from "./interfaces/IHelper.sol";
import {IBondFactory} from "./interfaces/IBondFactory.sol";

contract BondFactory is AccessControl, IBondFactory {
    bytes32 public constant BOND_CREATOR = keccak256("BOND_CREATOR");

    address public helper;

    mapping(address => address) public getBond;
    address[] public allBonds;

    /// @dev Emitted when a bond is created
    event BondCreated(address indexed bond, address indexed bondAsset);

    constructor(address _helper) {
        helper = _helper;
        Addresses memory _addresses = IHelper(_helper).getAddresses();
        _grantRole(BOND_CREATOR, _addresses.governor);
        _grantRole(BOND_CREATOR, _addresses.pairFactory);
    }

    function allBondsLength() external view returns (uint256) {
        return allBonds.length;
    }

    function createBond(
        address bondAsset,
        address oracle,
        uint256 amplitude,
        uint256 maxDebt,
        int256 verticalShift,
        bool isLiquidityToken,
        bool isStablecoin,
        bool useDynamicOracle,
        bool lendToAave)
        external
        onlyRole(BOND_CREATOR)
        returns (BondDepository bond) {
        require(bondAsset != address(0), "Zero address");
        require(getBond[bondAsset] == address(0), "Bond already exists");
        require(oracle != address(0), "Zero address");
        require(amplitude > 0, "Amplitude cannot be zero");
        require(maxDebt > 0, "Max debt cannot be zero");
        // gas savings
        address _helper = helper;
        bond = new BondDepository{salt: keccak256(abi.encodePacked(bondAsset))}(
            bondAsset,
            oracle,
            _helper,
            isLiquidityToken,
            isStablecoin,
            useDynamicOracle,
            lendToAave
        );
        bond.initialize(
            amplitude,
            maxDebt,
            verticalShift
        );
        getBond[bondAsset] = address(bond);
        allBonds.push(bondAsset);
        emit BondCreated(address(bond), bondAsset);
    }
}