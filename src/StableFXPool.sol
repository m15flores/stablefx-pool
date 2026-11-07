// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @notice  Constant-product (x*y=k) pool for a single, fixed pair of tokens. Designes for EUR/USD stablecoin pyments (USDC/EURC)
 * @dev The pool works in raw token units, so it doesn't depend on the tokens' decimals. It does not sort the tokens : `token0` and `token1` are the order
 *      the deployer chose. The pool custodies the reserves so it inherits the risks of the tokens.
 */
contract StableFXPool is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint256 public reserve0;
    uint256 public reserve1;

    uint256 public constant MINIMUM_LIQUIDITY = 1_000;
    uint256 public constant FEE_BPS = 5;
    uint256 public constant BPS = 10_000;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    /**
     * @dev Emmited when liquidity is added
     */
    event LiquidityAdded(
        address indexed sender, address indexed to, uint256 amount0, uint256 amount1, uint256 liquidity
    );

    /**
     * @dev Emmited when liquidity is removed
     */
    event LiquidityRemoved(
        address indexed sender, address indexed to, uint256 amount0, uint256 amount1, uint256 liquidity
    );

    /**
     * @dev Emitted when a swap is executed
     */
    event SwapTokens(address indexed sender, address indexed to, address tokenIn, uint256 amountIn, uint256 amountOut);

    /**
     * @dev Thrown when a token address is the zero address
     */
    error ZeroAddress();

    /**
     * @dev Thrown when both token addresses are the same
     */
    error IdenticalTokens();

    /**
     * @dev Thrown when a token address has no contract code
     */
    error NotAContract();

    /**
     * @dev Thrown when the transaction is minted after the caller's deadline
     */
    error Expired();

    /**
     * @dev Thrown when the liquidity recipient is the zero address or the pool itself
     */
    error InvalidRecipient();

    /**
     * @dev Thrown when one of the elements to deposit is zero
     */
    error ZeroAmount();

    /**
     * @dev Thrown when the amount the pool would take of q token is below the caller's minimum
     * @param got Amount the pool would actually take, given the current reserve ratio
     * @param min Minimum amount the caller require
     */
    error InsufficientAmount(uint256 got, uint256 min);

    /**
     * @dev Thrown when a deposit would mint no LP tokens to the recipient
     */
    error InsufficientLiquidityMinted();

    /**
     * @dev Thrown when a deposit would burn no LP tokens to the recipient
     */
    error InsufficientLiquidityBurned();

    /**
     * @dev Thrown when the token is not one of the 2 tokens of the pool
     */
    error InvalidToken();

    /**
     * @dev Thrown when the pool has no reserves to swap against
     */
    error InsufficientLiquidity();

    /**
     * @dev Thrown when a swap would output zero tokens
     */
    error InsufficientOutputAmount();

    error ExcessiveInputAmount(uint256 required, uint256 max);

    /**
     * @notice Creates a pool for the pair (`token0`, `token1`) and its LP token
     * @param token0_ address of the first token of the pair
     * @param token1_ address of the second token of the pair
     */
    constructor(address token0_, address token1_) ERC20("StableFX LP", "SFX-LP") {
        if (token0_ == address(0) || token1_ == address(0)) revert ZeroAddress();
        if (token0_.code.length == 0 || token1_.code.length == 0) revert NotAContract();
        if (token0_ == token1_) revert IdenticalTokens();

        token0 = IERC20(token0_);
        token1 = IERC20(token1_);
    }

    function addLiquidity(
        uint256 amount0Desired_,
        uint256 amount1Desired_,
        uint256 amount0Min_,
        uint256 amount1Min_,
        address to_,
        uint256 deadline_
    ) external nonReentrant returns (uint256 amount0_, uint256 amount1_, uint256 liquidity_) {
        // forge-lint: disable-next-line(block-timestamp)
        if (deadline_ < block.timestamp) revert Expired();
        if (to_ == address(0) || to_ == address(this)) revert InvalidRecipient();
        if (amount0Desired_ == 0 || amount1Desired_ == 0) revert ZeroAmount();

        if (totalSupply() == 0) {
            amount0_ = amount0Desired_;
            amount1_ = amount1Desired_;

            uint256 root_ = Math.sqrt(amount0_ * amount1_);
            if (root_ <= MINIMUM_LIQUIDITY) revert InsufficientLiquidityMinted();

            liquidity_ = root_ - MINIMUM_LIQUIDITY;
            _mint(DEAD, MINIMUM_LIQUIDITY);
        } else {
            (amount0_, amount1_) = _computeAmounts(amount0Desired_, amount1Desired_, amount0Min_, amount1Min_);
            liquidity_ = Math.min(amount0_ * totalSupply() / reserve0, amount1_ * totalSupply() / reserve1);
            if (liquidity_ == 0) revert InsufficientLiquidityMinted();
        }

        reserve0 += amount0_;
        reserve1 += amount1_;
        _mint(to_, liquidity_);

        token0.safeTransferFrom(msg.sender, address(this), amount0_);
        token1.safeTransferFrom(msg.sender, address(this), amount1_);

        emit LiquidityAdded(msg.sender, to_, amount0_, amount1_, liquidity_);
    }

    function removeLiquidity(
        uint256 liquidity_,
        uint256 amount0Min_,
        uint256 amount1Min_,
        address to_,
        uint256 deadline_
    ) external nonReentrant returns (uint256 amount0_, uint256 amount1_) {
        // forge-lint: disable-next-line(block-timestamp)
        if (deadline_ < block.timestamp) revert Expired();
        if (to_ == address(0) || to_ == address(this)) revert InvalidRecipient();
        if (liquidity_ == 0) revert ZeroAmount();

        amount0_ = liquidity_ * reserve0 / totalSupply();
        amount1_ = liquidity_ * reserve1 / totalSupply();

        if (amount0_ == 0 || amount1_ == 0) revert InsufficientLiquidityBurned();
        if (amount0_ < amount0Min_) revert InsufficientAmount(amount0_, amount0Min_);
        if (amount1_ < amount1Min_) revert InsufficientAmount(amount1_, amount1Min_);

        _burn(msg.sender, liquidity_);
        reserve0 -= amount0_;
        reserve1 -= amount1_;

        token0.safeTransfer(to_, amount0_);
        token1.safeTransfer(to_, amount1_);

        emit LiquidityRemoved(msg.sender, to_, amount0_, amount1_, liquidity_);
    }

    function getAmountOut(address tokenIn_, uint256 amountIn_) external view returns (uint256 amountOut_) {
        (amountOut_,) = _quote(tokenIn_, amountIn_);
    }

    function swapExactInput(address tokenIn_, uint256 amountIn_, uint256 amountOutMin_, address to_, uint256 deadline_)
        external
        nonReentrant
        returns (uint256 amountOut_)
    {
        // forge-lint: disable-next-line(block-timestamp)
        if (deadline_ < block.timestamp) revert Expired();
        if (to_ == address(0) || to_ == address(this)) revert InvalidRecipient();
        bool zeroForOne_;
        (amountOut_, zeroForOne_) = _quote(tokenIn_, amountIn_);
        if (amountOut_ < amountOutMin_) revert InsufficientAmount(amountOut_, amountOutMin_);

        if (zeroForOne_) {
            reserve0 += amountIn_;
            reserve1 -= amountOut_;
        } else {
            reserve0 -= amountOut_;
            reserve1 += amountIn_;
        }
        (IERC20 tokenIn, IERC20 tokenOut) = zeroForOne_ ? (token0, token1) : (token1, token0);
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn_);
        tokenOut.safeTransfer(to_, amountOut_);

        emit SwapTokens(msg.sender, to_, tokenIn_, amountIn_, amountOut_);
    }

    function getAmountIn(address tokenOut_, uint256 amountOut_) external view returns (uint256 amountIn_) {
        (amountIn_,) = _quoteIn(tokenOut_, amountOut_);
    }

    function swapExactOutput(
        address tokenOut_,
        uint256 amountOut_,
        uint256 amountInMax_,
        address to_,
        uint256 deadline_
    ) external nonReentrant returns (uint256 amountIn_) {}

    function getReserves() public view returns (uint256, uint256) {
        return (reserve0, reserve1);
    }

    function _computeAmounts(uint256 amount0Desired_, uint256 amount1Desired_, uint256 amount0Min_, uint256 amount1Min_)
        private
        view
        returns (uint256 amount0_, uint256 amount1_)
    {
        uint256 amount1Optimal_ = amount0Desired_ * reserve1 / reserve0;
        if (amount1Optimal_ <= amount1Desired_) {
            if (amount1Optimal_ < amount1Min_) revert InsufficientAmount(amount1Optimal_, amount1Min_);
            return (amount0Desired_, amount1Optimal_);
        }

        uint256 amount0Optimal_ = amount1Desired_ * reserve0 / reserve1;
        if (amount0Optimal_ < amount0Min_) revert InsufficientAmount(amount0Optimal_, amount0Min_);
        return (amount0Optimal_, amount1Desired_);
    }

    function _getAmountOut(uint256 amountIn_, uint256 reserveIn_, uint256 reserveOut_)
        private
        pure
        returns (uint256 amountOut_)
    {
        uint256 amountInWithFee_ = amountIn_ * (BPS - FEE_BPS);
        amountOut_ = amountInWithFee_ * reserveOut_ / (reserveIn_ * BPS + amountInWithFee_);
        if (amountOut_ == 0) revert InsufficientOutputAmount();
    }

    function _quote(address tokenIn_, uint256 amountIn_) private view returns (uint256 amountOut_, bool zeroForOne_) {
        if (amountIn_ == 0) revert ZeroAmount();

        uint256 reserveIn_;
        uint256 reserveOut_;

        if (tokenIn_ == address(token0)) {
            (reserveIn_, reserveOut_) = (reserve0, reserve1);
        } else if (tokenIn_ == address(token1)) {
            (reserveIn_, reserveOut_) = (reserve1, reserve0);
        } else {
            revert InvalidToken();
        }

        if (reserveIn_ == 0 || reserveOut_ == 0) revert InsufficientLiquidity();

        amountOut_ = _getAmountOut(amountIn_, reserveIn_, reserveOut_);
        zeroForOne_ = tokenIn_ == address(token0);
    }

    function _getAmountIn(uint256 amountOut_, uint256 reserveIn_, uint256 reserveOut_)
        private
        pure
        returns (uint256 amountIn_)
    {
        amountIn_ = reserveIn_ * amountOut_ * BPS / ((reserveOut_ - amountOut_) * (BPS - FEE_BPS)) + 1;
    }

    function _quoteIn(address tokenOut_, uint256 amountOut_)
        private
        view
        returns (uint256 amountIn_, bool zeroForOne_)
    {
        if (amountOut_ == 0) revert ZeroAmount();

        uint256 reserveIn_;
        uint256 reserveOut_;

        if (tokenOut_ == address(token0)) {
            (reserveIn_, reserveOut_) = (reserve1, reserve0);
        } else if (tokenOut_ == address(token1)) {
            (reserveIn_, reserveOut_) = (reserve0, reserve1);
        } else {
            revert InvalidToken();
        }

        if (reserveIn_ == 0 || reserveOut_ == 0 || amountOut_ >= reserveOut_) revert InsufficientLiquidity();

        amountIn_ = _getAmountIn(amountOut_, reserveIn_, reserveOut_);
        zeroForOne_ = tokenOut_ == address(token1);
    }
}
