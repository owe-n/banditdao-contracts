// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";

import {IBanditLP} from "./interfaces/IBanditLP.sol";

contract BanditLP is ERC20, ERC20Permit, IBanditLP {
    constructor() ERC20("BanditLP", "bLP") ERC20Permit("BanditLP") {}

    function mint(address to, uint256 amount) internal {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) internal {
        _burn(from, amount);
    }
}
