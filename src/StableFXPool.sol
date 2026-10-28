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
     * @notice Creates q pool for the pair (`token0`, `token1`) and its LP token
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
}
