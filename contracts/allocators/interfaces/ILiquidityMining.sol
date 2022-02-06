// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.11;

interface ILiquidityMining {
    function claimRewards(address[] calldata assets, uint256 amount, address to) external;

    function getRewardsBalance(address[] calldata assets, address user) external view returns (uint256);
}