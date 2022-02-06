// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.11;

interface IProtocolDataProvider {
    function getReserveTokensAddresses(address asset)
        external
        view
        returns (
        address aTokenAddress,
        address stableDebtTokenAddress,
        address variableDebtTokenAddress);
}