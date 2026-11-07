// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStableFXPool {
    /**
     * @dev Adds liquidity to the pool and mints LP tokens to `to_`.
     *      Only the amounts that match the current reserve ratio are pulled from the caller,
     *      so the actual amounts can be lower than the desired ones.
     *      The first deposit sets the initial price and locks `MINIMUM_LIQUIDITY` LP tokens forever.
     *      The minimums are not enforced on the first deposit, which sets the price.
     * @param amount0Desired_ Amount of token0 the caller wants to deposit
     * @param amount1Desired_ Amount of token1 the caller wants to deposit
     * @param amount0Min_ Minimum amount of token0 to deposit, protects against price movement
     * @param amount1Min_ Minimum amount of token1 to deposit, protects against price movement
     * @param to_ Recipient of the LP tokens
     * @param deadline_ Timestamp after which the transaction reverts
     * @return amount0_ Amount of token0 actually deposited
     * @return amount1_ Amount of token1 actually deposited
     * @return liquidity_ Amount of LP tokens minted
     */
    function addLiquidity(
        uint256 amount0Desired_,
        uint256 amount1Desired_,
        uint256 amount0Min_,
        uint256 amount1Min_,
        address to_,
        uint256 deadline_
    ) external returns (uint256 amount0_, uint256 amount1_, uint256 liquidity_);

    /**
     * @dev Burns `liquidity_` LP tokens from the caller and sends the proportional share
     *      of both reserves to `to_`.
     * @param liquidity_ Amount of LP tokens to burn
     * @param amount0Min_ Minimum amount of token0 to receive
     * @param amount1Min_ Minimum amount of token1 to receive
     * @param to_ Recipient of the withdrawn tokens
     * @param deadline_ Timestamp after which the transaction reverts
     * @return amount0_ Amount of token0 sent to `to_`
     * @return amount1_ Amount of token1 sent to `to_`
     */
    function removeLiquidity(
        uint256 liquidity_,
        uint256 amount0Min_,
        uint256 amount1Min_,
        address to_,
        uint256 deadline_
    ) external returns (uint256 amount0_, uint256 amount1_);

    /**
     * @dev Quotes how much of the other token a swap of exactly `amountIn_` of `tokenIn_` would return,
     *      after the 0.05% fee. Rounds down, in favour of the pool.
     * @param tokenIn_ Token the caller would pay
     * @param amountIn_ Exact amount of `tokenIn_` to pay
     * @return amountOut_ Amount of the other token the caller would receive
     */
    function getAmountOut(address tokenIn_, uint256 amountIn_) external view returns (uint256 amountOut_);

    /**
     * @dev Swaps exactly `amountIn_` of `tokenIn_` for as much of the other token as the reserves allow.
     *      Reverts with `InsufficientAmount` if the output is below `amountOutMin_`.
     *      The caller must have approved the pool to spend `amountIn_` of `tokenIn_`.
     * @param tokenIn_ Token the caller pays
     * @param amountIn_ Exact amount of `tokenIn_` to pay
     * @param amountOutMin_ Minimum amount of the other token to receive, protects against slippage
     * @param to_ Recipient of the output tokens
     * @param deadline_ Timestamp after which the transaction reverts
     * @return amountOut_ Amount of the other token sent to `to_`
     */
    function swapExactInput(address tokenIn_, uint256 amountIn_, uint256 amountOutMin_, address to_, uint256 deadline_)
        external
        returns (uint256 amountOut_);

    /**
     * @dev Quotes how much of the other token is needed to receive exactly `amountOut_` of `tokenOut_`,
     *      after the 0.05% fee. Rounds up, in favour of the pool.
     * @param tokenOut_ Token the caller would receive
     * @param amountOut_ Exact amount of `tokenOut_` to receive
     * @return amountIn_ Amount of the other token the caller would have to pay
     */
    function getAmountIn(address tokenOut_, uint256 amountOut_) external view returns (uint256 amountIn_);

    /**
     * @dev Swaps as little input as needed to receive exactly `amountOut_` of `tokenOut_`.
     *      Reverts with `ExcessiveInputAmount` if the required input exceeds `amountInMax_`.
     *      The caller must have approved the pool to spend the input token.
     * @param tokenOut_ Token the caller receives
     * @param amountOut_ Exact amount of `tokenOut_` to receive
     * @param amountInMax_ Maximum amount of the input token the caller is willing to pay
     * @param to_ Recipient of the output tokens
     * @param deadline_ Timestamp after which the transaction reverts
     * @return amountIn_ Amount of the input token pulled from the caller
     */
    function swapExactOutput(
        address tokenOut_,
        uint256 amountOut_,
        uint256 amountInMax_,
        address to_,
        uint256 deadline_
    ) external returns (uint256 amountIn_);

    /**
     * @dev Returns the internal reserve accounting, which is what prices swaps.
     *      It can differ from the token balances of the pool if tokens are donated directly.
     * @return reserve0_ Reserve of token0
     * @return reserve1_ Reserve of token1
     */
    function getReserves() external view returns (uint256 reserve0_, uint256 reserve1_);

    /**
     * @dev First token of the pair
     */
    function token0() external view returns (IERC20);

    /**
     * @dev Second token of the pair
     */
    function token1() external view returns (IERC20);
}
