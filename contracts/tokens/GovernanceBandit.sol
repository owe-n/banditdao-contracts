// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.11;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PercentageMath} from "../libraries/PercentageMath.sol";

import {Addresses, IHelper} from "../interfaces/IHelper.sol";
import {IStakedBandit} from "./interfaces/IStakedBandit.sol";
import {IGovernanceBandit} from "./interfaces/IGovernanceBandit.sol";

contract GovernanceBandit is ERC20, ERC20Permit, ERC20Votes, IGovernanceBandit {
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;

    address public immutable sBNDT;
    address public immutable treasury;

    constructor(address helper) ERC20("GovernanceBandit", "gBNDT") ERC20Permit("GovernanceBandit") {
        require(helper != address(0), "Zero address");
        Addresses memory addresses = IHelper(helper).getAddresses();
        sBNDT = addresses.sBNDT;
        treasury = addresses.treasury;
    }

    /**
        @notice wrap sBNDT
        @param amount uint256
     */
    function wrap(uint256 amount) public returns (uint256 value) {
        address _sBNDT = sBNDT; // gas savings
        IERC20(_sBNDT).safeTransferFrom(msg.sender, address(this), amount);
        value = stakedToWrapped(amount);
        _mint(msg.sender, value);
    }

    /**
        @notice unwrap sBNDT
        @param amount uint
     */
    function unwrap(uint256 amount) public returns (uint256 value) {
        address _sBNDT = sBNDT; // gas savings
        _burn(msg.sender, amount);
        value = wrappedToStaked(amount);
        IERC20(_sBNDT).safeTransfer(msg.sender, value);
    }

    /**
        @notice converts wsBNDT amount to sBNDT
        @param amount uint256
        @return uint256
     */
    function wrappedToStaked(uint256 amount) public view returns (uint256) {
        address _sBNDT = sBNDT; // gas savings
        return ((amount * IStakedBandit(_sBNDT).index()).percentDiv(100)) / 10 ** decimals();
    }

    /**
        @notice converts sBNDT amount to wsBNDT
        @param amount uint
        @return uint
     */
    function stakedToWrapped(uint256 amount) public view returns (uint256) {
        address _sBNDT = sBNDT; // gas savings
        return (amount * 10 ** decimals()) / (IStakedBandit(_sBNDT).index()).percentDiv(100);
    }

    function circulatingSupply() public view returns (uint256) {
        address _treasury = treasury; // gas savings
        return totalSupply() - balanceOf(_treasury);
    }

    // The following functions are overrides required by Solidity
    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }
}