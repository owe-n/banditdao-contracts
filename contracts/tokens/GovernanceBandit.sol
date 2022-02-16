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

    IStakedBandit public immutable sBNDT;
    address public immutable treasury;

    event Wrap(address indexed user, uint256 sBNDTamount, uint256 gBNDTamount);
    event Unwrap(address indexed user, uint256 gBNDTamount, uint256 sBNDTamount);

    constructor(address helper) ERC20("GovernanceBandit", "gBNDT") ERC20Permit("GovernanceBandit") {
        require(helper != address(0), "Zero address");
        Addresses memory addresses = IHelper(helper).getAddresses();
        sBNDT = IStakedBandit(addresses.sBNDT);
        treasury = addresses.treasury;
    }

    
    /// @notice wrap sBNDT to gBNDT
    function wrap(uint256 amount) public returns (uint256 value) {
        IStakedBandit _sBNDT = sBNDT; // gas savings
        IERC20(_sBNDT).safeTransferFrom(msg.sender, address(this), amount);
        value = stakedToWrapped(amount);
        _mint(msg.sender, value);
        emit Wrap(msg.sender, amount, value);
    }

    /// @notice unwrap gBNDT to sBNDT
    function unwrap(uint256 amount) public returns (uint256 value) {
        IStakedBandit _sBNDT = sBNDT; // gas savings
        _burn(msg.sender, amount);
        value = wrappedToStaked(amount);
        IERC20(_sBNDT).safeTransfer(msg.sender, value);
        emit Unwrap(msg.sender, amount, value);
    }

    
    /// @notice converts gBNDT amount to sBNDT
    function wrappedToStaked(uint256 amount) public view returns (uint256) {
        IStakedBandit _sBNDT = sBNDT; // gas savings
        return amount.percentMul(_sBNDT.index());
    }

    
    /// @notice converts sBNDT amount to gBNDT
    function stakedToWrapped(uint256 amount) public view returns (uint256) {
        IStakedBandit _sBNDT = sBNDT; // gas savings
        return amount.percentDiv(_sBNDT.index());
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