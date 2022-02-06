// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Addresses, IHelper} from "./interfaces/IHelper.sol";
import {BondParameters, DiscountParameters, IBondDepository} from "./interfaces/IBondDepository.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {IAaveAllocator} from "./allocators/interfaces/IAaveAllocator.sol";
import {IBandit} from "./tokens/interfaces/IBandit.sol";
import {IDynamicOracle} from "./interfaces/IDynamicOracle.sol";
import {INative} from "./interfaces/INative.sol";
import {IPair} from "./interfaces/IPair.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";
import {IWrappedStakedBandit} from "./tokens/interfaces/IWrappedStakedBandit.sol";

import {BondHelper} from "./libraries/BondHelper.sol";
import {FixedPoint} from "./libraries/FixedPoint.sol";
import {Math} from "./libraries/Math.sol";
import {PercentageMath} from "./libraries/PercentageMath.sol";

contract BondDepository is AccessControl, IBondDepository, ReentrancyGuard {
    using FixedPoint for *;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant FACTORY = keccak256("FACTORY");
    bytes32 public constant GOVERNOR = keccak256("GOVERNOR");

    address public immutable helper;

    // user details
    mapping(address => uint256) public bondStart;
    mapping(address => uint256) public userMaxPayout;
    mapping(address => uint256) public BNDTreleased;
    mapping(address => uint256) public totalBNDTreleased;
    mapping(address => bool) public isPayoutWrapped;

    Addresses private addresses;
    BondParameters private bondParameters;
    DiscountParameters private discountParameters;

    // if _bondAsset is a reserve asset and doesn't have a chainlink data feed, _useDynamicOracle should be set to true;
    constructor(
        address _bondAsset, 
        address _oracle,
        address _helper,
        address factory,
        address governor,
        address treasury,
        bool _isLiquidityToken,
        bool _isStablecoin,
        bool _useDynamicOracle,
        bool lendToAave) {
        bondParameters.bondAsset = _bondAsset;
        bondParameters.oracle = _oracle;
        helper = _helper;
        _grantRole(FACTORY, factory);
        _grantRole(GOVERNOR, governor);
        _grantRole(GOVERNOR, treasury); // for maxDebt adjustments
        if (_isLiquidityToken == true) {
            bondParameters.isLiquidityToken = true;
        } else {
            bondParameters.isReserveAsset = true;
        }
        if (_isStablecoin == true) {
            bondParameters.isStablecoin = true;
        }
        if (_useDynamicOracle == true) {
            bondParameters.useDynamicOracle = true;
        }
        if (lendToAave == true) {
            bondParameters.isLentOutOnAave = true;
        }
        _setAddresses();
    }

    receive() external payable {
        // gas savings
        Addresses memory _addresses = addresses;
        assert(msg.sender == _addresses.native); // only accept native chain token via fallback
    }

    // helper function for transferring native token (eg: AVAX, ETH, FTM)
    function safeTransferNative(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        require(success, "Native transfer failed");
    }

    function _setAddresses() internal {
        address _helper = helper; // gas savings
        addresses = IHelper(_helper).getAddresses();
    }

    // at bond genesis, verticalShift is 0
    function initialize(
        uint256 _amplitude,
        uint256 _maxDebt,
        int256 _verticalShift
    ) external onlyRole(FACTORY) {
        // gas savings
        Addresses memory _addresses = addresses;
        BondParameters memory _bondParameters = bondParameters;

        bondParameters.aToken = IAaveAllocator(_addresses.allocator)
            .getATokenAddress(_bondParameters.bondAsset);
        bondParameters.duration = 5 days; // vesting period starts at 5 days
        discountParameters.amplitude = _amplitude;
        discountParameters.maxDebt = _maxDebt;
        discountParameters.verticalShift = _verticalShift;
    }

    function getAddresses() external view returns (Addresses memory) {
        return addresses;
    }

    function getBondParameters() external view returns (BondParameters memory) {
        return bondParameters;
    }

    function getDiscountParameters() external view returns (DiscountParameters memory) {
        return discountParameters;
    }

    function updateDuration(uint256 newDuration) external onlyRole(GOVERNOR) {
        bondParameters.duration = newDuration;
    }

    function updateAmplitude(uint256 newAmplitude) external onlyRole(GOVERNOR) {
        discountParameters.amplitude = newAmplitude;
    }

    function updateMaxDebt(uint256 newMaxDebt) external onlyRole(GOVERNOR) {
        discountParameters.maxDebt = newMaxDebt;
    }

    function updateVerticalShift(int256 newVerticalShift) external onlyRole(GOVERNOR) {
        discountParameters.verticalShift = newVerticalShift;
    }

    function bond(address beneficiary, uint256 amount) public payable nonReentrant {
        // gas savings
        Addresses memory _addresses = addresses;
        BondParameters memory _bondParameters = bondParameters;
        DiscountParameters memory _discountParameters = discountParameters;

        uint256 payout = BondHelper.getPayout(_addresses, _bondParameters, _discountParameters, amount);
        uint256 wsBNDTbalance = IERC20(_addresses.wsBNDT).balanceOf(address(this));
        uint256 amountToUnwrap;
        require(_discountParameters.currentDebt + payout <= _discountParameters.maxDebt, "Bond exceeds maxDebt");
        require(payout <= _discountParameters.maxDebt.percentMul(5) /* 0.05% */, "Payout exceeds maximum");
        // payout is doubled because BNDT is minted for the bonder and distributor
        if (payout * 2 <= IWrappedStakedBandit(_addresses.wsBNDT).wrappedToStaked(wsBNDTbalance)) {
            isPayoutWrapped[msg.sender] = true;
            amountToUnwrap = IWrappedStakedBandit(_addresses.wsBNDT).stakedToWrapped(
                IWrappedStakedBandit(_addresses.wsBNDT).wrappedToStaked(wsBNDTbalance) - payout);
        } else {
            require(FixedPoint.fraction(ITreasury(_addresses.treasury).getRFV() - (2 * payout),
                IERC20(_addresses.BNDT).totalSupply()).decode() > 1, "Minting below intrinsic value");
        }
        discountParameters.currentDebt += payout;
        userMaxPayout[beneficiary] = payout;
        bondStart[msg.sender] = block.timestamp;
        if (_bondParameters.bondAsset == _addresses.native) {
            INative(_addresses.native).deposit{value: msg.value}();
            assert(INative(_addresses.native).transfer(address(this), msg.value));
            // refund dust, if any
            if (msg.value > amount) {
                safeTransferNative(msg.sender, msg.value - amount);
            }
        } else {
            IERC20(_bondParameters.bondAsset).safeTransferFrom(msg.sender, address(this), amount);
        }
        if (_bondParameters.isLentOutOnAave == true) {
            IAaveAllocator(_addresses.allocator)
                .supplyToAave(_bondParameters.bondAsset,
                IERC20(_bondParameters.bondAsset).balanceOf(address(this)));
            BondHelper.depositInTreasury(_bondParameters, IERC20(_bondParameters.aToken).balanceOf(address(this)),
                address(this), _addresses.treasury);
        } else {
            BondHelper.depositInTreasury(_bondParameters, IERC20(_bondParameters.bondAsset).balanceOf(address(this)),
                address(this), _addresses.treasury);
        }
        if (isPayoutWrapped[msg.sender] == true) {
            BondHelper.unwrapAndSend(_addresses, amountToUnwrap, address(this));
        } else {
            IBandit(_addresses.BNDT).mint(_addresses.distributor, payout);
        }
    }

    function claim() public nonReentrant {
        // gas savings
        Addresses memory _addresses = addresses;
        BondParameters memory _bondParameters = bondParameters;

        uint256 maxPayout = userMaxPayout[msg.sender];
        uint256 releasedBNDT = BNDTreleased[msg.sender];
        require(maxPayout - releasedBNDT > 0, "Nothing to claim");
        uint256 wsBNDTbalance = IERC20(_addresses.wsBNDT).balanceOf(address(this));
        uint256 releasable = BondHelper.vestedAmount(block.timestamp, bondStart[msg.sender],
            _bondParameters.duration, maxPayout);
        BNDTreleased[msg.sender] += releasable;
        // reset bond status if over
        if (maxPayout - releasedBNDT == 0) {
            userMaxPayout[msg.sender] = 0;
            BNDTreleased[msg.sender] = 0;
        }
        discountParameters.currentDebt -= releasable;
        uint256 amountToUnwrap = IWrappedStakedBandit(_addresses.wsBNDT).stakedToWrapped(
                IWrappedStakedBandit(_addresses.wsBNDT).wrappedToStaked(wsBNDTbalance) - releasable);
        if (isPayoutWrapped[msg.sender] == true) {
            BondHelper.unwrapAndSend(_addresses, amountToUnwrap, address(this));
        }
        IBandit(_addresses.BNDT).mint(msg.sender, releasable);
    }
}