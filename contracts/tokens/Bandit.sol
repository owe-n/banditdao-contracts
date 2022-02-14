// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";

import {Addresses, IHelper} from "../interfaces/IHelper.sol";
import {IBandit} from "./interfaces/IBandit.sol";

contract Bandit is AccessControl, ERC20, ERC20Permit, IBandit {
    bytes32 public constant MINTER = keccak256("MINTER");
    bytes32 public constant BURNER = keccak256("BURNER");

    address public immutable helper;

    Addresses private addresses;

    constructor(address _helper, address presale) ERC20("Bandit", "BNDT") ERC20Permit("Bandit") {
        helper = _helper;
        _setAddresses();
        Addresses memory _addresses = addresses; // gas savings
        _grantRole(MINTER, presale);
        _grantRole(MINTER, _addresses.treasury);
        _grantRole(BURNER, _addresses.staking);
    }

    function _setAddresses() internal {
        address _helper = helper; // gas savings
        addresses = IHelper(_helper).getAddresses();
    }

    function getAddresses() external view returns (Addresses memory) {
        return addresses;
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(BURNER) {
        _burn(from, amount);
    }

    function circulatingSupply() public view returns (uint256) {
        Addresses memory _addresses = addresses; // gas savings
        return totalSupply() - balanceOf(_addresses.distributor) - balanceOf(_addresses.staking);
    }
}