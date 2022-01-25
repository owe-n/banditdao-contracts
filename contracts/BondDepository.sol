// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {IAaveAllocator} from "./allocators/interfaces/IAaveAllocator.sol";
import {IBandit} from "./tokens/interfaces/IBandit.sol";
import {IBondDepository} from "./interfaces/IBondDepository.sol";
import {IDynamicOracle} from "./interfaces/IDynamicOracle.sol";
import {IPair} from "./interfaces/IPair.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import {IStaking} from "./interfaces/IStaking.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";
import {IWrappedStakedBandit} from "./tokens/interfaces/IWrappedStakedBandit.sol";

import {FixedPoint} from "./libraries/FixedPoint.sol";
import {Math} from "./libraries/Math.sol";
import {PercentageMath} from "./libraries/PercentageMath.sol";
import {Trigonometry} from "./libraries/Trigonometry.sol";

contract BondDepository is AccessControl, IBondDepository, ReentrancyGuard {
    using FixedPoint for *;
    using Math for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;
    
    bytes32 public constant FACTORY = keccak256("FACTORY");
    bytes32 public constant GOVERNOR = keccak256("GOVERNOR");

    address public immutable native;
    address public immutable BNDT;
    address public immutable sBNDT;
    address public immutable wsBNDT;

    address public immutable allocator;
    address public immutable bondAsset;
    address public immutable distributor;
    address public immutable pairFactory;
    address public immutable router;
    address public immutable staking;
    address public immutable treasury;

    address public immutable nativeOracle;
    address public immutable oracle;

    mapping(address => bool) public isReserveAsset;
    mapping(address => bool) public isLiquidityToken;
    mapping(address => bool) public isLentOutOnAave;
    mapping(address => bool) public isPayoutWrapped;
    mapping(address => bool) public useDynamicOracle;

    mapping(address => uint256) public BNDTreleased; // for a user
    mapping(address => uint256) public totalBNDTreleased;
    mapping(address => uint256) public userMaxPayout;

    uint256 public amplitude; // represents the max/min discount scaled by 1000
    uint256 public currentDebt;
    // represents the max supply of the bond in BNDT
    uint256 public maxDebt;
    int256 public verticalShift;

    // if _bondAsset is a reserve asset and doesn't have a chainlink data feed, _useDynamicOracle should be set to true;
    constructor( 
        address _bondAsset, 
        address factory,
        address _oracle,
        bool _isLiquidityToken,
        bool _useDynamicOracle,
        bool lendToAave) {
        bondAsset = _bondAsset;
        oracle = _oracle;
        grantRole(FACTORY, factory);
        if (_isLiquidityToken == true) {
            isLiquidityToken[bondAsset] = true;
            isReserveAsset[bondAsset] = false;
        } else {
            isReserveAsset[bondAsset] = true;
            isLiquidityToken[bondAsset] = false;
        }
        if (_useDynamicOracle == true) {
            useDynamicOracle[bondAsset] = true;
        }
        if (lendToAave == true) {
            isLentOutOnAave[bondAsset] = true;
        }
    }

    // at genesis, verticalShift should be 0
    function initialize(
        uint256 _amplitude,
        uint256 _maxDebt,
        int256 _verticalShift,
        address _native,
        address _nativeOracle,
        address _BNDT,
        address _sBNDT,
        address _wsBNDT,
        address _allocator,
        address _bootstrapper,
        address _distributor,
        address governor,
        address _pairFactory,
        address _router,
        address _staking,
        address _treasury)
        external
        onlyRole(FACTORY) {
        amplitude = _amplitude;
        maxDebt = _maxDebt;
        verticalShift = _verticalShift;
        native = _native;
        nativeOracle = _nativeOracle;
        BNDT = _BNDT;
        sBNDT = _sBNDT;
        wsBNDT = _wsBNDT;
        allocator = _allocator;
        bootstrapper = _bootstrapper;
        distributor = _distributor;
        grantRole(GOVERNOR, governor);
        pairFactory = _pairFactory;
        router = _router;
        staking = _staking;
        treasury = _treasury;
    }

    function updateAmplitude(uint256 newAmplitude) external onlyRole(GOVERNOR) {
        amplitude = newAmplitude;
    }

    function updateMaxDebt(uint256 newMaxDebt) external onlyRole(GOVERNOR) {
        maxDebt = newMaxDebt;
    }

    function updateVerticalShift(int256 newVerticalShift) external onlyRole(GOVERNOR) {
        verticalShift = newVerticalShift;
    }

    function bond(address beneficiary, uint256 amount) public nonReentrant {
        uint112 maxPayout = uint112(maxDebt.percentMul(5)); // 0.05%
        uint112 payout = getPayout(amount);
        uint256 wsBNDTbalance = IERC20(wsBNDT).balanceOf(address(this));
        uint256 amountToUnwrap;
        require(currentDebt + payout <= maxDebt, "Bond exceeds maxDebt");
        require(payout <= maxPayout, "Payout exceeds maximum");
        // payout is doubled because BNDT is minted for the bonder and distributor
        if (payout * 2 <= IWrappedStakedBandit(wsBNDT).wrappedToStaked(wsBNDTbalance)) {
            isPayoutWrapped[msg.sender] = true;
            amountToUnwrap = IWrappedStakedBandit(wsBNDT).wrappedToStaked(wsBNDTbalance) - payout;
        } else {
            require(FixedPoint.fraction(ITreasury(treasury).getRFV() - (2 * uint256(payout)),
                IERC20(BNDT).totalSupply()).decode() > 1, "Can't mint below min intrinsic value");
        }
        IERC20(bondAsset).safeTransferFrom(msg.sender, address(this), amount);
        if (isLentOutOnAave[bondAsset] == true) {
            address aToken = IAaveAllocator(allocator).getATokenAddress(bondAsset);
            IAaveAllocator(allocator).supplyToAave(bondAsset, IERC20(bondAsset).balanceOf(address(this)));
            depositInTreasury(IERC20(aToken).balanceOf(address(this)));
        } else {
            depositInTreasury(IERC20(bondAsset).balanceOf(address(this)));
        }
        currentDebt += payout;
        userMaxPayout[beneficiary] = payout;
        if (isPayoutWrapped[msg.sender] == true) {
            IERC20(wsBNDT).safeIncreaseAllowance(wsBNDT, amountToUnwrap);
            IWrappedStakedBandit(wsBNDT).unwrap(amountToUnwrap);
            IERC20(sBNDT).safeIncreaseAllowance(staking, IERC20(sBNDT).balanceOf(address(this)));
            IStaking(staking).unstake(IERC20(sBNDT).balanceOf(address(this)));
            IERC20(BNDT).safeTransfer(distributor, IERC20(BNDT).balanceOf(address(this)));
        } else {
            IBandit(BNDT).mint(distributor, payout);
        }
    }

    function claim() public nonReentrant {
        require(userMaxPayout[msg.sender] > 0, "Haven't bonded yet");
        require(userMaxPayout[msg.sender] - BNDTreleased[msg.sender] > 0, "Payout already claimed");
        uint256 releasable = _vestedAmount(uint64(block.timestamp)) - BNDTreleased[msg.sender];
        BNDTreleased[msg.sender] += releasable;
        // reset bond status if over
        if (userMaxPayout[msg.sender] - BNDTreleased[msg.sender] == 0) {
            userMaxPayout[msg.sender] = 0;
            BNDTreleased[msg.sender] = 0;
        }
        currentDebt -= releasable;
        uint256 amountToUnwrap = IWrappedStakedBandit(wsBNDT).wrappedToStaked(wsBNDTbalance) - payout;
        if (isPayoutWrapped[msg.sender] == true) {
            IERC20(wsBNDT).safeIncreaseAllowance(wsBNDT, amountToUnwrap);
            IWrappedStakedBandit(wsBNDT).unwrap(amountToUnwrap);
            IERC20(sBNDT).safeIncreaseAllowance(staking, IERC20(sBNDT).balanceOf(address(this)));
            IStaking(staking).unstake(IERC20(sBNDT).balanceOf(address(this)));
            IERC20(BNDT).safeTransfer(msg.sender, IERC20(BNDT).balanceOf(address(this)));
        }
        IBandit(BNDT).mint(msg.sender, releasable);
    }

    function _vestedAmount(uint64 timestamp) internal view returns (uint256) {
        uint64 start = bondStart[msg.sender] + 5 days;
        if (timestamp < start) {
            return 0;
        } else if (timestamp > start + duration) {
            return userMaxPayout[msg.sender];
        } else {
            return (userMaxPayout[msg.sender] * (timestamp - start)) / duration;
        }
    }

    function _calcDiscount() internal view returns (int256 output) {
        uint256 _amplitude = amplitude; // gas savings
        uint256 _currentDebt = currentDebt; // gas savings
        uint256 _maxDebt = maxDebt; // gas savings
        int256 _verticalShift = verticalShift; // gas savings
        output = int256((_amplitude)
            * uint256(Trigonometry.cos(
            uint256(FixedPoint.fraction(TWO_PI, _maxDebt * 2).decode()) * _currentDebt))
            + uint256(_verticalShift));
    }

    function getPriceOfAsset(uint256 amount) external view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(nativeOracle);
            (,int256 price,,,) = priceFeed.latestRoundData();
            uint256 nativePrice =  uint256(price / 1e8) * amount; // chainlink decimals
        if (isReserveAsset[bondAsset] == true) {
            if (useNativeOracle[bondAsset] == true) {
                IDynamicOracle(oracle).update(bondAsset, native);
                uint256 bondAssetInNative = IDynamicOracle(oracle).consult(bondAsset, amount, native);
                return bondAssetInNative * nativePrice;
            } else {
                AggregatorV3Interface priceFeed = AggregatorV3Interface(oracle);
                (,int256 price,,,) = priceFeed.latestRoundData();
                return uint256(price / 1e8) * amount; // chainlink decimals
            }
        } else if (isLiquidityToken[bondAsset] == true) {
            address tokenA = IPair(bondAsset).token0();
            address tokenB = IPair(bondAsset).token1();
            (uint256 tokenAAmount, uint256 tokenBAmount)
                = Math.getLiquidityValue(pairFactory, tokenA, tokenB, amount);
            IDynamicOracle(oracle).update(tokenA, native);
            IDynamicOracle(oracle).update(tokenB, native);
            uint256 tokenAinNative = IDynamicOracle(oracle).consult(tokenA, amount, native);
            uint256 tokenBinNative = IDynamicOracle(oracle).consult(tokenB, amount, native);
            return (tokenAinNative + tokenBinNative) * nativePrice;
        }
    }

    function getPriceOfBNDT() external view returns (uint256) {
        IDynamicOracle(oracle).update(BNDT, native);
        uint256 BNDTinNative = IDynamicOracle(oracle).consult(BNDT, 1e18, native);
        AggregatorV3Interface priceFeed = AggregatorV3Interface(nativeOracle);
        (,int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price / 1e8) * BNDTinNative; // chainlink decimals
    }

    function getPayout(uint256 amount) internal view returns (uint112 payout) {
        uint256 discount = _calcDiscount();
        uint256 priceOfAsset = this.getPriceOfAsset(amount);
        payout = FixedPoint.fraction(priceOfAsset, this.getPriceOfBNDT()
                - (this.getPriceOfBNDT().percentMul(discount)).decode());
    }

    function depositInTreasury(uint256 amount) internal {
        IERC20(bondAsset).safeIncreaseAllowance(treasury, amount);
        ITreasury(treasury).deposit(bondAsset, amount, isLiquidityToken[bondAsset]);
    }
}