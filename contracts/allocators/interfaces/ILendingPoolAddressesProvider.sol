// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.11;

interface ILendingPoolAddressesProvider {
    function getAddress(bytes32 id) external view returns (address);

    function getLendingPool() external view returns (address);
}