// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice  Constant-product (x*y=k) pool for a single, fixed pair of tokens. Designes for EUR/USD stablecoin pyments (USDC/EURC)
 * @dev The pool works in raw token units, so it doesn't depend on the tokens' decimals. It does not sort the tokens : `token0` and `token1` are the order
 *      the deployer chose. The pool custodies the reserves so it inherits the risks of the tokens.
 */
contract StableFXPool is ERC20 {
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint256 public reserve0;
    uint256 public reserve1;

    uint256 public constant MINIMUM_LIQUIDITY = 1_000;
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
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) external returns (uint256 amount0, uint256 amount1, uint256 liquidity) {}

    function removeLiquidity(uint256 liquidity, uint256 amount0Min, uint256 amount1Min, address to, uint256 deadline)
        external
        returns (uint256 amount0, uint256 amount1)
    {}

    function getReserves() public view returns (uint256, uint256) {
        return (reserve0, reserve1);
    }
}
