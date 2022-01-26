// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {BondDepository} from "./BondDepository.sol";

import {IBondDepository} from "./interfaces/IBondDepository.sol";
import {IBondFactory} from "./interfaces/IBondFactory.sol";

contract BondFactory is AccessControl, IBondFactory {
    bytes32 public constant BOND_CREATOR = keccak256("BOND_CREATOR");

    address public native;
    address public nativeOracle;
    address public BNDT;
    address public sBNDT;
    address public wsBNDT;
    address public allocator;
    address public distributor;
    address public governor;
    address public pairFactory;
    address public router;
    address public staking;
    address public treasury;

    mapping(address => address) public override getBond;
    address[] public override allBonds;

    event BondCreated(address bond, address bondAsset);

    constructor(
        address _native,
        address _nativeOracle,
        address _BNDT,
        address _sBNDT,
        address _wsBNDT,
        address _allocator,
        address _distributor,
        address _governor,
        address _pairFactory,
        address _router,
        address _staking,
        address _treasury) {
        _grantRole(BOND_CREATOR, _governor);
        _grantRole(BOND_CREATOR, _pairFactory);
        native = _native;
        nativeOracle = _nativeOracle;
        BNDT = _BNDT;
        sBNDT = _sBNDT;
        wsBNDT = _wsBNDT;
        allocator = _allocator;
        distributor = _distributor;
        governor = _governor;
        pairFactory = _pairFactory;
        router = _router;
        staking = _staking;
        treasury = _treasury;
    }

    function allBondsLength() external override view returns (uint256) {
        return allBonds.length;
    }

    function createBond(
        address bondAsset,
        address oracle,
        uint256 amplitude,
        uint256 maxDebt,
        int256 verticalShift,
        bool isLiquidityToken,
        bool useDynamicOracle,
        bool lendToAave) 
        external
        override
        onlyRole(BOND_CREATOR)
        returns (address bond) {
        require(bondAsset != address(0), "Zero address");
        require(getBond[bondAsset] == address(0), "Bond already exists");
        bond = new BondDepository{salt: keccak256(abi.encodePacked(bondAsset))}(
            bondAsset,
            address(this),
            governor,
            oracle,
            isLiquidityToken,
            useDynamicOracle,
            lendToAave);
        IBondDepository(bond).initialize(
            amplitude,
            maxDebt,
            verticalShift,
            native,
            nativeOracle,
            BNDT,
            sBNDT,
            wsBNDT,
            allocator,
            distributor,
            pairFactory,
            router,
            staking,
            treasury
        );
        getBond[bondAsset] = bond;
        allBonds.push(bondAsset);
        emit BondCreated(bond, bondAsset);
    }
}