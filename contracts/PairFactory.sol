// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

import {Pair} from "./Pair.sol";

import {Errors} from "./libraries/Errors.sol";

import {IPairFactory} from "./interfaces/IPairFactory.sol";

contract PairFactory is IPairFactory {
    address public immutable sBNDT;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    constructor(address _sBNDT) {
        if (_sBNDT == address(0)) revert Errors.ZeroAddress(_sBNDT);
        sBNDT = _sBNDT; 
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB)
        external
        override
        returns (Pair pair) {
        if (tokenA == sBNDT) revert Errors.InvalidToken(tokenA); // sBNDT pool can not be made
        if (tokenB == sBNDT) revert Errors.InvalidToken(tokenB); // sBNDT pool can not be made
        if (tokenA == tokenB) revert Errors.IdenticalAddress(tokenA, tokenB); // gas savings
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert Errors.ZeroAddress(token0); // gas savings
        if (getPair[token0][token1] != address(0)) revert Errors.PairExists(getPair[token0][token1]); // gas savings
        pair = new Pair{salt: keccak256(abi.encodePacked(token0, token1))}();
        Pair(pair).initialize(token0, token1);
        getPair[token0][token1] = address(pair);
        getPair[token1][token0] = address(pair); // populate mapping in the reverse direction
        allPairs.push(address(pair));
        emit PairCreated(token0, token1, address(pair), allPairs.length);
    }
}