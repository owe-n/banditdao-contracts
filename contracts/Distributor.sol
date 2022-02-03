// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PercentageMath} from "./libraries/PercentageMath.sol";

import {IDistributor} from "./interfaces/IDistributor.sol";
import {IStaking} from "./interfaces/IStaking.sol";

contract Distributor is IDistributor {
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;

    address public immutable BNDT;
    address public immutable treasury;
    address public immutable staking;

    uint256 public startOfLastEpoch;

    constructor(
        address _BNDT,
        address _treasury,
        address _staking
    ) {
        BNDT = _BNDT;
        treasury = _treasury;
        staking = _staking;
        startOfLastEpoch = block.timestamp;
    }

    function distribute() public {
        uint256 _startOfLastEpoch = startOfLastEpoch; // gas savings
        require(block.timestamp >= _startOfLastEpoch + 8 hours); // epoch is 8 hours
        startOfLastEpoch = block.timestamp;
        uint256 balance = IERC20(BNDT).balanceOf(address(this));
        uint256 amount = balance.percentMul(100); // 1%
        IERC20(BNDT).safeIncreaseAllowance(staking, amount);
        IStaking(staking).deposit(amount);
    }

    function secondsToNextEpoch() external view returns (uint256) {
        return block.timestamp - (startOfLastEpoch + 8 hours);
    }
}