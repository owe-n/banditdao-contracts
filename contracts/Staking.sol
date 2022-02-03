// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IBandit} from "./tokens/interfaces/IBandit.sol";
import {IStakedBandit} from "./tokens/interfaces/IStakedBandit.sol";
import {IStaking} from "./interfaces/IStaking.sol";

contract Staking is AccessControl, IStaking, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant DISTRIBUTOR = keccak256("DISTRIBUTOR");

    address public immutable BNDT;
    address public immutable sBNDT;

    uint256 public BNDTreserve;

    mapping(address => uint256) public startedStaking;

    constructor ( 
        address _BNDT,
        address _sBNDT,
        address distributor
    ) {
        BNDT = _BNDT;
        sBNDT = _sBNDT;
        _grantRole(DISTRIBUTOR, distributor);
    }

    event UserStaked(uint256 amountStaked);
    event UserUnstaked(uint256 amountUnstaked);

    function stake(uint256 amount) public nonReentrant {
        address _BNDT = BNDT; // gas savings
        address _sBNDT = sBNDT; // gas savings
        startedStaking[msg.sender] = block.timestamp;
        BNDTreserve += amount;
        IERC20(_BNDT).safeTransferFrom(msg.sender, address(this), amount);
        IStakedBandit(_sBNDT).mint(msg.sender, amount);
        emit UserStaked(amount);
    }

    function unstake(uint256 amount) public nonReentrant {
        // requires a user to be staked for at least 2 days before unstaking
        require(block.timestamp >= startedStaking[msg.sender] + 2 days, "Warmup period not over"); 
        address _BNDT = BNDT; // gas savings
        address _sBNDT = sBNDT; // gas savings
        BNDTreserve -= amount;
        IERC20(_sBNDT).safeTransferFrom(msg.sender, address(this), amount);
        IStakedBandit(_sBNDT).burn(address(this), amount);
        IERC20(_BNDT).safeTransfer(msg.sender, amount);
        emit UserUnstaked(amount);
    }

    function deposit(uint256 amount) external onlyRole(DISTRIBUTOR) {
        address _BNDT = BNDT; // gas savings;
        BNDTreserve += amount;
        IERC20(_BNDT).safeTransferFrom(msg.sender, address(this), amount);
        _rebase();
    }

    function getIndex() public view returns (uint256) {
        address _sBNDT = sBNDT; // gas savings
        return IStakedBandit(_sBNDT).index();
    }

    /// @notice trigger rebase if epoch over
    /// @dev is called by the distributor after rewards have been sent
    function _rebase() internal {
        address _BNDT = BNDT; // gas savings
        address _sBNDT = sBNDT; // gas savings
        _burnExcessBNDT();
        uint256 balance = IERC20(_BNDT).balanceOf(address(this));
        uint256 staked = IERC20(_sBNDT).totalSupply();
        if (balance > staked) {
            IStakedBandit(_sBNDT).updateIndex((balance / staked) - 1);
        }
        IStakedBandit(_sBNDT).updateRebaseProfit(balance - staked);
    }

    function _burnExcessBNDT() internal {
        address _BNDT = BNDT; // gas savings
        uint256 _BNDTreserve = BNDTreserve; // gas savings
        IBandit(_BNDT).burn(address(this), IERC20(_BNDT).balanceOf(address(this)) - _BNDTreserve);
    }
}