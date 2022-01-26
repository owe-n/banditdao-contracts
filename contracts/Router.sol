// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Library} from "./libraries/Library.sol";

import {IPairFactory} from "./interfaces/IPairFactory.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import {INative} from "./interfaces/INative.sol";

contract Router is IRouter {
    using SafeERC20 for IERC20;

    address public immutable override factory;
    address public immutable override native;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "Expired");
        _;
    }

    constructor(address _factory, address _native) public {
        factory = _factory;
        native = _native;
    }

    receive() external payable {
        assert(msg.sender == native); // only accept native chain token via fallback
    }

    // helper function for transferring native token (eg: AVAX, ETH, FTM)
    function safeTransferNative(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        require(success, "Native transfer failed");
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        if (IFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IFactory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = Library.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "Insufficient 'B' amount");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, "Insufficient 'A' amount");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = Library.pairFor(factory, tokenA, tokenB);
        IERC20(tokenA).safeTransferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, pair, amountB);
        liquidity = IPair(pair).mint(to);
    }

    function addLiquidityNative(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountNativeMin,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (
            uint256 amountToken,
            uint256 amountNative,
            uint256 liquidity
        )
    {
        (amountToken, amountNative) = _addLiquidity(
            token,
            native,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountNativeMin
        );
        address pair = Library.pairFor(factory, token, native);
        IERC20(token).safeTransferFrom(msg.sender, pair, amountToken);
        INative(native).deposit{value: amountNative}();
        assert(INative(native).transfer(pair, amountNative));
        liquidity = IPair(pair).mint(to);
        // refund dust, if any
        if (msg.value > amountNative) {
            safeTransferNative(msg.sender, msg.value - amountNative);
        }
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = Library.pairFor(factory, tokenA, tokenB);
        IERC20(pair).safeTransferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = IPair(pair).burn(to);
        (address token0, ) = Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "Insufficient 'A' amount");
        require(amountB >= amountBMin, "Insufficient 'B' amount");
    }

    function removeLiquidityNative(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountNativeMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountToken, uint256 amountNative) {
        (amountToken, amountNative) = removeLiquidity(
            token,
            native,
            liquidity,
            amountTokenMin,
            amountNativeMin,
            address(this),
            deadline
        );
        IERC20(token).safeTransfer(to, amountToken);
        INative(native).withdraw(amountNative);
        safeTransferNative(to, amountNative);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountA, uint256 amountB) {
        address pair = Library.pairFor(factory, tokenA, tokenB);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        IPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(
            tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    function removeLiquidityNativeWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountNativeMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountToken, uint256 amountNative) {
        address pair = Library.pairFor(factory, token, native);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        IPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountNative) = removeLiquidityNative(
            token, liquidity, amountTokenMin, amountNativeMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityNativeSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountNativeMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountNative) {
        (,amountNative) = removeLiquidity(
            token,
            native,
            liquidity,
            amountTokenMin,
            amountNativeMin,
            address(this),
            deadline
        );
        IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));
        INative(native).withdraw(amountNative);
        safeTransferNative(to, amountNative);
    }

    function removeLiquidityNativeWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountNativeMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountNative) {
        address pair = Library.pairFor(factory, token, native);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountNative = removeLiquidityNativeSupportingFeeOnTransferTokens(
            token,
            liquidity,
            amountTokenMin,
            amountNativeMin,
            to,
            deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(
        uint256[] memory amounts,
        address[] memory path,
        address _to
    ) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < path.length - 2 ? Library.pairFor(factory, output, path[i + 2]) : _to;
            IPair(Library.pairFor(factory, input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "Insufficient output amount");
        IERC20(path[0]).safeTransferFrom(msg.sender, Library.pairFor(
            factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "Excessive input amount");
        IERC20(path[0]).safeTransferFrom(msg.sender, Library.pairFor(
            factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

    function swapExactNativeForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == native, "Invalid path");
        amounts = Library.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "Insufficient output amount");
        INative(native).deposit{value: amounts[0]}();
        assert(INative(native).transfer(Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    function swapTokensForExactNative(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == native, "Invalid path");
        amounts = Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "Excessive input amount");
        IERC20(path[0]).safeTransferFrom(msg.sender, Library.pairFor(
            factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        INative(native).withdraw(amounts[amounts.length - 1]);
        safeTransferNative(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForNative(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == native, "Invalid path");
        amounts = Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "Insufficient output amount");
        IERC20(path[0]).safeTransferFrom(msg.sender, Library.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        INative(native).withdraw(amounts[amounts.length - 1]);
        safeTransferNative(to, amounts[amounts.length - 1]);
    }

    function swapNativeForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == native, "Invalid path");
        amounts = Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, "Excessive input amount");
        INative(native).deposit{value: amounts[0]}();
        assert(INative(native).transfer(Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust, if any
        if (msg.value > amounts[0]) {
            safeTransferNative(msg.sender, msg.value - amounts[0]);
        }
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = Library.sortTokens(input, output);
            IPair pair = IPair(Library.pairFor(factory, input, output));
            uint256 amountInput;
            uint256 amountOutput;
            {
                // scope to avoid stack too deep errors
                (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) = input == token0
                    ? (reserve0, reserve1)
                    : (reserve1, reserve0);
                amountInput = (IERC20(input).balanceOf(address(pair))).sub(reserveInput);
                amountOutput = Library.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOutput)
                : (amountOutput, uint256(0));
            address to = i < path.length - 2 ? Library.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        IERC20(path[0]).safeTransferFrom(
            msg.sender, Library.pairFor(factory, path[0], path[1]), amountIn);
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            "Insufficient output amount"
        );
    }

    function swapExactNativeForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) {
        require(path[0] == native, "Invalid path");
        uint256 amountIn = msg.value;
        INative(native).deposit{value: amountIn}();
        assert(INative(native).transfer(Library.pairFor(factory, path[0], path[1]), amountIn));
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            (IERC20(path[path.length - 1]).balanceOf(to)).sub(balanceBefore) >= amountOutMin,
            "Insufficient output amount"
        );
    }

    function swapExactTokensForNativeSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        require(path[path.length - 1] == native, "Invalid path");
        IERC20(path[0]).safeTransferFrom(
            msg.sender, Library.pairFor(factory, path[0], path[1]), amountIn);
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = IERC20(native).balanceOf(address(this));
        require(amountOut >= amountOutMin, "Insufficient output amount");
        INative(native).withdraw(amountOut);
        safeTransferNative(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) public pure virtual override returns (uint256 amountB) {
        return Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual override returns (uint256 amountOut) {
        return Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual override returns (uint256 amountIn) {
        return Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return Library.getAmountsIn(factory, amountOut, path);
    }
}