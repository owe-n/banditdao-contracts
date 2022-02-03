// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.11;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {FixedPoint} from "./libraries/FixedPoint.sol";
import {PercentageMath} from "./libraries/PercentageMath.sol";

import {IAaveAllocator} from "./allocators/interfaces/IAaveAllocator.sol";
import {IBandit} from "./tokens/interfaces/IBandit.sol";
import {IBondDepository} from "./interfaces/IBondDepository.sol";
import {IRouter} from "./interfaces/IRouter.sol";

contract Treasury is AccessControl, ReentrancyGuard {
    using FixedPoint for *;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant DEPOSITOR = keccak256("DEPOSITOR");
    bytes32 public constant GOVERNOR = keccak256("GOVERNOR");

    address public immutable BNDT;
    address public immutable sBNDT;
    address public immutable native; // wrapped version of the chain's native asset

    address public immutable allocator;
    address public immutable bondFactory;
    address public immutable dev; // used for dev payments
    address public immutable distributor;
    address public immutable router;
    
    address[] public reserveAssets;
    address[] public liquidityTokens;
    address[] public stablecoins;

    mapping(address => address) public bondDepo; // maps a token to its bond depository
    mapping(address => address) public aTokenToToken; // maps an aToken to the underlying
    mapping(address => bool) public isLentOutOnAave;

    constructor(
        address _BNDT,
        address _sBNDT,
        address _native,
        address _allocator,
        address _bondFactory,
        address _dev,
        address _distributor,
        address _router,
        address governor,
        address presale) {
        BNDT = _BNDT;
        sBNDT = _sBNDT;
        native = _native;
        allocator = _allocator;
        bondFactory = _bondFactory;
        dev = _dev;
        distributor = _distributor;
        router = _router;
        _grantRole(DEPOSITOR, _bondFactory);
        _grantRole(DEPOSITOR, presale);
        _grantRole(GOVERNOR, governor);
    }

    function deposit(
        address _bondDepo,
        address token,
        uint256 amount,
        bool isLiquidityToken,
        bool isStablecoin,
        bool _isLentOutOnAave
    ) external onlyRole(DEPOSITOR) {
        address _bondFactory = bondFactory; // gas savings
        if (msg.sender == _bondFactory) {
            bondDepo[token] = _bondDepo;
        }
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        if (isLiquidityToken == true) {
            liquidityTokens.push(token);
        } else if (isStablecoin == true) {
            stablecoins.push(token);
        } else {
            reserveAssets.push(token);
        }
        if (_isLentOutOnAave == true) {
            isLentOutOnAave[token] = true;
            aTokenToToken[token] = IBondDepository(_bondDepo).bondAsset();
        }
    }

    function claim(uint256 amountToBurn, address assetToReceive) public nonReentrant {
        uint256 BNDTprice = IBondDepository(bondDepo[native]).getPriceOfBNDT();
        uint256 burnValue = BNDTprice * amountToBurn;
        uint256 assetValue = this.getValueOfToken(assetToReceive);
        require(BNDTprice < this.getBackingPerBNDT(), "Price is above backing");
        require(assetValue >= burnValue, "Treasury balance too low");
        uint256 amountToReceive = uint256(FixedPoint.fraction(burnValue, assetValue).decode());
        IERC20(BNDT).safeTransferFrom(msg.sender, address(this), amountToBurn);
        IBandit(BNDT).burn(address(this), IERC20(BNDT).balanceOf(address(this)));
        IERC20(assetToReceive).safeTransfer(msg.sender, amountToReceive);
        uint256 currentMaxDebt = IBondDepository(bondDepo[assetToReceive]).maxDebt();
        IBondDepository(bondDepo[assetToReceive]).updateMaxDebt(currentMaxDebt + amountToBurn);
    }

    function getBackingPerBNDT() external view returns (uint256) {
        address _BNDT = BNDT; // gas savings
        (uint256 total,) = this.getTreasuryValue();
        return uint256(FixedPoint.fraction(total, IERC20(_BNDT).balanceOf(address(this))).decode());
    }

    function getTreasuryValue() external view returns (uint256 total, uint256 rfv) {
        uint256 sum;
        for (uint256 i = 0; i < reserveAssets.length; i++) {
            if (isLentOutOnAave[reserveAssets[i]] == true) {
                uint256 price = this.getValueOfToken(aTokenToToken[reserveAssets[i]]);
                sum += price;
            } else {
                uint256 price = this.getValueOfToken(reserveAssets[i]);
                sum += price;
            }
        }
        for (uint256 j = 0; j < liquidityTokens.length; j++) {
            uint256 price = this.getValueOfToken(liquidityTokens[j]);
            sum += price;
        }
        for (uint256 k = 0; k < stablecoins.length; k++) {
            uint256 price = this.getValueOfToken(stablecoins[k]);
            sum += price;
            rfv = price;
        }
        total = sum;

    }

    // token has to a bondable asset
    function getValueOfToken(address token) external view returns (uint256) {
        return IBondDepository(bondDepo[token]).getPriceOfAsset(IERC20(token).balanceOf(address(this)));
    }

    function getRFV() external view returns (uint256 rfv) {
        (,rfv) = this.getTreasuryValue();
    }

    function redeemFromAave(address asset) public nonReentrant {
        (uint256 amount, uint256 rewards) = IAaveAllocator(allocator).redeemFromAave(asset, 0);
        // amount
        // 90% amount used to buy back BNDT
        address[] memory path;
        path = new address[](3);
        path[0] = asset;
        path[1] = native;
        path[2] = BNDT;
        IERC20(asset).safeIncreaseAllowance(router, amount.percentMul(9000)); // 90%
        IRouter(router).swapExactTokensForTokens(
            amount.percentMul(9000),
            0,
            path,
            address(this),
            block.timestamp + 30 minutes
        );
        // rewards
        // 45% rewards used to buy back BNDT + 45% rewards left in treasury
        address[] memory rewardsPath;
        rewardsPath = new address[](2);
        rewardsPath[0] = native;
        rewardsPath[1] = BNDT;
        IERC20(native).safeIncreaseAllowance(router, rewards.percentMul(4500)); // 45%;
        IRouter(router).swapExactTokensForTokens(
            rewards.percentMul(4500),
            0,
            rewardsPath,
            address(this),
            block.timestamp + 30 minutes
        );
        // BNDT distribution: 50% burned, 50% sent to distributor
        IERC20(BNDT).safeTransfer(distributor, IERC20(BNDT).balanceOf(address(this)).percentMul(5000)); // 50%
        IBandit(BNDT).burn(address(this), IERC20(BNDT).balanceOf(address(this)));
        // dev payment of 10% amount + rewards
        IERC20(asset).safeTransfer(dev, amount.percentMul(1000)); // 10%
        IERC20(native).safeTransfer(dev, rewards.percentMul(1000)); // 10%
    }

    function redeemAmountFromAave(address asset, uint256 amount) external onlyRole(GOVERNOR) {
        IAaveAllocator(allocator).redeemFromAave(asset, amount);
    }
}