// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.11;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PercentageMath} from "../libraries/PercentageMath.sol";

import {Addresses, IHelper} from "../interfaces/IHelper.sol";
import {IStakedBandit} from "./interfaces/IStakedBandit.sol";

contract StakedBandit is AccessControl, ERC20, ERC20Permit, IStakedBandit {
    using PercentageMath for uint256;

    bytes32 public constant STAKING = keccak256("STAKING");

    uint256 public index; // in hundreds
    uint256 public rebaseProfit; // running total

    event IndexUpdated(uint256 newIndex);
    event RebaseProfitUpdated(uint256 newRebaseProfit);

    constructor(address helper) ERC20("StakedBandit", "sBNDT") ERC20Permit("StakedBandit") {
        Addresses memory addresses = IHelper(helper).getAddresses();
        _grantRole(STAKING, addresses.staking);
    }

    function mint(address to, uint256 amount) external onlyRole(STAKING) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(STAKING) {
        _burn(from, amount);
    }

    function totalSupply() public view override (ERC20, IStakedBandit) returns (uint256) {
        uint256 _rebaseProfit = rebaseProfit; // gas savings
        return super.totalSupply() + _rebaseProfit;
    }

    function balanceOf(address account) public view override(ERC20, IStakedBandit) returns (uint256) {
        uint256 _index = index; // gas savings
        return (super.balanceOf(account) * _index).percentDiv(100);
    }

    function updateIndex(uint256 amount) external onlyRole(STAKING) {
        index += amount;
        uint256 _index = index; // gas savings
        emit IndexUpdated(_index);
    }

    function updateRebaseProfit(uint256 amount) external onlyRole(STAKING) {
        rebaseProfit += amount;
        uint256 _rebaseProfit = rebaseProfit; // gas savings
        emit RebaseProfitUpdated(_rebaseProfit);
    }
}