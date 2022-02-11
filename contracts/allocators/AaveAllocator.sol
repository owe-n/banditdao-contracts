// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PercentageMath} from "../libraries/PercentageMath.sol";

import {Addresses, IAaveAllocator} from "./interfaces/IAaveAllocator.sol";
import {IHelper} from "../interfaces/IHelper.sol";
import {ILiquidityMining} from "./interfaces/ILiquidityMining.sol";
import {ILendingPoolAddressesProvider} from "./interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPool} from "./interfaces/ILendingPool.sol";
import {IProtocolDataProvider} from "./interfaces/IProtocolDataProvider.sol";

contract AaveAllocator is AccessControl, IAaveAllocator {
	using PercentageMath for uint256;
    using SafeERC20 for IERC20;

	bytes32 public constant BOND_DEPO = keccak256("BOND_DEPO");
	bytes32 public constant GOVERNOR = keccak256("GOVERNOR");
	bytes32 public constant TREASURY = keccak256("TREASURY");

	address public immutable addressProvider;
	address public immutable incentivesController;
	address public immutable helper;

	uint16 public referralCode;

	mapping(address => uint256) public lastATokenBalance;

	Addresses private addresses;

	constructor(
		address _addressProvider,
		address _incentivesController,
		address _helper) {
		require(_addressProvider != address(0), "Zero address");
		addressProvider = _addressProvider;
		require(_incentivesController != address(0), "Zero address");
		incentivesController = _incentivesController;
		require(_helper != address(0), "Zero address");
		helper = _helper;
		referralCode = 0;
		_setAddresses();
		Addresses memory _addresses = addresses;
		_grantRole(BOND_DEPO, _addresses.bondFactory);
		_grantRole(GOVERNOR, _addresses.governor);
		_grantRole(TREASURY, _addresses.treasury);
	}

	function _setAddresses() internal {
        address _helper = helper; // gas savings
        addresses = IHelper(_helper).getAddresses();
    }

	function getAddresses() external view returns (Addresses memory) {
		return addresses;
	}

	function changeReferralCode(uint16 newReferralCode) external onlyRole(GOVERNOR) {
		referralCode = newReferralCode;
	}

    function supplyToAave(
		address asset,
		uint256 amount)
		external
		onlyRole(BOND_DEPO)
		returns (address aToken) {
		address lendingPoolAddress = ILendingPoolAddressesProvider(addressProvider).getLendingPool();
		ILendingPool lendingPool = ILendingPool(lendingPoolAddress);
		IERC20(asset).safeIncreaseAllowance(address(lendingPool), amount);
		lendingPool.deposit(asset, amount, msg.sender, referralCode);
		aToken = getATokenAddress(asset);
		lastATokenBalance[aToken] = amount;
	}

	// if amount == 0, withdraws 50% of any earned earned interest and any liquidity mining rewards
	// if amount != 0, withdraws that amount along with rewards
    function redeemFromAave(
		address asset,
		uint256 amount)
		external
		onlyRole(TREASURY)
		returns (uint256 amount_, uint256 rewards_) {
		address lendingPoolAddress = ILendingPoolAddressesProvider(addressProvider).getLendingPool();
		ILendingPool lendingPool = ILendingPool(lendingPoolAddress);
		address aToken = getATokenAddress(asset);
		uint256 balance = IERC20(aToken).balanceOf(msg.sender);
		address[] memory assets;
		assets = new address[](1);
		assets[0] = aToken;
		uint256 rewards = ILiquidityMining(incentivesController).getRewardsBalance(assets, msg.sender);
		ILiquidityMining(incentivesController).claimRewards(assets, rewards, msg.sender);
		if (amount == 0) {
			uint256 amountToWithdraw = (balance - lastATokenBalance[aToken]).percentMul(5000); // 50%
			lendingPool.withdraw(asset, amountToWithdraw, msg.sender);
			lastATokenBalance[aToken] -= amountToWithdraw;
			return (amountToWithdraw, rewards);
		} else {
			lendingPool.withdraw(asset, amount, msg.sender);
			lastATokenBalance[aToken] -= amount;
			return (amount, rewards);
		}
	}

    function getATokenAddress(address asset) public view returns (address aToken) {
		bytes32 id = bytes32(bytes1(uint8(1))); // protocol data provider id = 0x1;
		address dataProviderAddress = ILendingPoolAddressesProvider(addressProvider).getAddress(id);
		IProtocolDataProvider protocolDataProvider = IProtocolDataProvider(dataProviderAddress);
		(aToken,,) = protocolDataProvider.getReserveTokensAddresses(asset);
	}
}