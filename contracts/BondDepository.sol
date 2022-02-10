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

    bytes32 public constant GOVERNOR = keccak256("GOVERNOR");

    address public immutable helper;

    // user details
    mapping(address => uint256) public bondStart;
    mapping(address => uint256) public userMaxPayout;
    mapping(address => uint256) public BNDTreleased;
    mapping(address => bool) public isPayoutWrapped;

    Addresses private addresses;
    BondParameters private bondParameters;
    DiscountParameters private discountParameters;

    event UserBonded(address indexed user, uint256 amount, uint256 payout, bool isPayoutWrapped);

    constructor(
        address _bondAsset, 
        address _oracle,
        address _helper,
        bool _isLiquidityToken,
        bool _isStablecoin,
        bool _useDynamicOracle,
        bool lendToAave) {
        bondParameters.bondAsset = _bondAsset;
        bondParameters.oracle = _oracle;
        helper = _helper;
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

    function _setAddresses() internal {
        address _helper = helper; // gas savings
        addresses = IHelper(_helper).getAddresses();
    }

    function initialize(
        uint256 _amplitude,
        uint256 _maxDebt,
        int256 _verticalShift
    ) external {
        // gas savings
        Addresses memory _addresses = addresses;
        BondParameters memory _bondParameters = bondParameters;

        require(msg.sender == _addresses.bondFactory, "Only bond factory can initialize");
        bondParameters.aToken = IAaveAllocator(_addresses.allocator)
            .getATokenAddress(_bondParameters.bondAsset);
        bondParameters.duration = 5 days; // vesting period starts at 5 days
        discountParameters.amplitude = _amplitude;
        discountParameters.maxDebt = _maxDebt;
        discountParameters.verticalShift = _verticalShift;
        _grantRole(GOVERNOR, _addresses.governor);
        _grantRole(GOVERNOR, _addresses.treasury); // for maxDebt adjustments
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

    function updateOracle(address newOracle) external onlyRole(GOVERNOR) {
        bondParameters.oracle = newOracle;
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

    function bond(address beneficiary, uint256 amount) public nonReentrant {
        require(beneficiary != address(0), "Zero address");
        require(amount > 0, "Amount must be positive");
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
        bondStart[beneficiary] = block.timestamp;
        IERC20(_bondParameters.bondAsset).safeTransferFrom(msg.sender, address(this), amount);
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
        emit UserBonded(beneficiary, amount, payout, isPayoutWrapped[msg.sender]);
    }

    function claim() public nonReentrant {
        // gas savings
        Addresses memory _addresses = addresses;
        BondParameters memory _bondParameters = bondParameters;

        uint256 maxPayout = userMaxPayout[msg.sender];
        uint256 releasedBNDT = BNDTreleased[msg.sender];
        require(maxPayout - releasedBNDT > 0, "Nothing to claim");
        uint256 releasable = BondHelper.vestedAmount(block.timestamp, bondStart[msg.sender],
            _bondParameters.duration, maxPayout);
        BNDTreleased[msg.sender] += releasable;
        discountParameters.currentDebt -= releasable;
        // reset bond status if over
        if (maxPayout - releasedBNDT == 0) {
            bondStart[msg.sender] = 0;
            userMaxPayout[msg.sender] = 0;
            BNDTreleased[msg.sender] = 0;
            isPayoutWrapped[msg.sender] = false;
        }
        if (isPayoutWrapped[msg.sender] == true) {
            uint256 amountToUnwrap = IWrappedStakedBandit(_addresses.wsBNDT).stakedToWrapped(releasable);
            BondHelper.unwrapAndSend(_addresses, amountToUnwrap, address(this));
        } else {
            IBandit(_addresses.BNDT).mint(msg.sender, releasable);
        }
    }
}