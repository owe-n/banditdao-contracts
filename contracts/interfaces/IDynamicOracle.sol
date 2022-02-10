// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

interface IDynamicOracle {
    function factory() external view returns (address);

    function windowSize() external view returns (uint256);

    function granularity() external view returns (uint256);

    function periodSize() external view returns (uint256);

    function observationIndexOf(uint256 timestamp) external view returns (uint8 index);

    function update(address tokenA, address tokenB) external;

    function consult(
        address tokenIn,
        uint256 amountIn,
        address tokenOut)
        external
        view
        returns (uint256 amountOut);
}