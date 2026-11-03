// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "../src/StableFXPool.sol";
import "./mocks/MockERC20.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract StableFXPoolTest is Test {
    StableFXPool stablePool;
    MockERC20 token0;
    MockERC20 token1;
    address user;

    uint256 public constant INITIAL_MINT_TOKEN = 1_000_000e6;

    function setUp() public {
        user = makeAddr("user");
        token0 = new MockERC20("Mock USDC", "USDC", 6);
        token1 = new MockERC20("Mock EURC", "EURC", 6);
        stablePool = new StableFXPool(address(token0), address(token1));
        token0.mint(user, INITIAL_MINT_TOKEN);
        token1.mint(user, INITIAL_MINT_TOKEN);

        vm.startPrank(user);
        token0.approve(address(stablePool), INITIAL_MINT_TOKEN);
        token1.approve(address(stablePool), INITIAL_MINT_TOKEN);
        vm.stopPrank();
    }

    function test_Constructor_SetsImmutables() public {
        MockERC20 token0_ = new MockERC20("Mock A", "A", 18);
        vm.warp(10);
        MockERC20 token1_ = new MockERC20("Mock B", "B", 18);

        stablePool = new StableFXPool(address(token0_), address(token1_));
        assertEq(address(stablePool.token0()), address(token0_));
        assertEq(address(stablePool.token1()), address(token1_));
    }

    function test_Constructor_AcceptsDifferentDecimals() public {
        MockERC20 token0_ = new MockERC20("Mock USDC", "USDC", 6);
        vm.warp(10);
        MockERC20 token1_ = new MockERC20("Mock DAI", "DAI", 18);

        stablePool = new StableFXPool(address(token0_), address(token1_));
        assertEq(address(stablePool.token0()), address(token0_));
        assertEq(address(stablePool.token1()), address(token1_));
    }

    function test_Constructor_RevertWhen_Token0IsZeroAddress() public {
        MockERC20 token1_ = new MockERC20("Mock DAI", "DAI", 18);

        vm.expectRevert(StableFXPool.ZeroAddress.selector);
        stablePool = new StableFXPool(address(0), address(token1_));
    }

    function test_Constructor_RevertWhen_Token1IsZeroAddress() public {
        MockERC20 token0_ = new MockERC20("Mock USDC", "USDC", 6);

        vm.expectRevert(StableFXPool.ZeroAddress.selector);
        stablePool = new StableFXPool(address(token0_), address(0));
    }

    function test_Constructor_RevertWhen_TokensAreIdentical() public {
        MockERC20 token_ = new MockERC20("Mock USDC", "USDC", 6);

        vm.expectRevert(StableFXPool.IdenticalTokens.selector);
        stablePool = new StableFXPool(address(token_), address(token_));
    }

    function test_Constructor_RevertWhen_Token0IsNotAContract() public {
        MockERC20 token1_ = new MockERC20("Mock DAI", "DAI", 18);
        address token0_ = makeAddr("token0");

        vm.expectRevert(StableFXPool.NotAContract.selector);
        stablePool = new StableFXPool(token0_, address(token1_));
    }

    function test_Constructor_RevertWhen_Token1IsNotAContract() public {
        MockERC20 token0_ = new MockERC20("Mock USDC", "USDC", 6);
        address token1_ = makeAddr("token1");

        vm.expectRevert(StableFXPool.NotAContract.selector);
        stablePool = new StableFXPool(address(token0_), token1_);
    }

    function test_AddLiquidity_FirstDepositLocksMinimum() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        uint256 liquidity_ = _addLiquidity(user, amount0_, amount1_);

        uint256 expectedLiquidityUser = 1_000e6 - 1_000;
        uint256 expectedTotalSupply = 1_000e6;
        (uint256 reserve0_, uint256 reserve1_) = stablePool.getReserves();

        assertEq(liquidity_, expectedLiquidityUser);
        assertEq(stablePool.MINIMUM_LIQUIDITY(), stablePool.balanceOf(stablePool.DEAD()));
        assertEq(stablePool.balanceOf(user), expectedLiquidityUser);
        assertEq(stablePool.totalSupply(), expectedTotalSupply);
        assertEq(reserve0_, 1_000e6);
        assertEq(reserve1_, 1_000e6);
        assertEq(token0.balanceOf(address(stablePool)), 1_000e6);
        assertEq(token1.balanceOf(address(stablePool)), 1_000e6);
    }

    function test_AddLiquidity_FirstDepositMintsSqrtMinusMinimum() public {
        uint256 amount0_ = 4_000e6;
        uint256 amount1_ = 1_000e6;
        uint256 liquidity_ = _addLiquidity(user, amount0_, amount1_);

        uint256 expectedLiquidityUser = 2_000e6 - 1_000;
        uint256 expectedTotalSupply = 2_000e6;
        (uint256 reserve0_, uint256 reserve1_) = stablePool.getReserves();

        assertEq(liquidity_, expectedLiquidityUser);
        assertEq(stablePool.balanceOf(user), expectedLiquidityUser);
        assertEq(token0.balanceOf(address(stablePool)), amount0_);
        assertEq(token1.balanceOf(address(stablePool)), amount1_);
        assertEq(stablePool.totalSupply(), expectedTotalSupply);
        assertEq(reserve0_, 4_000e6);
        assertEq(reserve1_, 1_000e6);
    }

    function test_AddLiquidity_UsesOptimalRatio() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);

        uint256 token0Balance_ = token0.balanceOf(user);
        uint256 token1Balance_ = token1.balanceOf(user);

        uint256 liquidity2_ = _addLiquidity(user, 500e6, 1_000e6);
        (uint256 reserve0_, uint256 reserve1_) = stablePool.getReserves();

        assertEq(token0.balanceOf(user), token0Balance_ - 500e6);
        assertEq(token1.balanceOf(user), token1Balance_ - 500e6);
        assertEq(reserve0_, 1_500e6);
        assertEq(reserve1_, 1_500e6);
        assertEq(liquidity2_, 500e6);
        assertEq(stablePool.totalSupply(), 1_500e6);
        assertEq(token0.balanceOf(address(stablePool)), 1_500e6);
        assertEq(token1.balanceOf(address(stablePool)), 1_500e6);
    }

    function test_AddLiquidity_UsesOptimalRatioWithNonTrivialRatio() public {
        uint256 amount0_ = 4_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);

        uint256 token0Balance_ = token0.balanceOf(user);
        uint256 token1Balance_ = token1.balanceOf(user);

        uint256 liquidity2_ = _addLiquidity(user, 400e6, 1_000e6);
        (uint256 reserve0_, uint256 reserve1_) = stablePool.getReserves();

        assertEq(token0.balanceOf(user), token0Balance_ - 400e6);
        assertEq(token1.balanceOf(user), token1Balance_ - 100e6);
        assertEq(reserve0_, 4_400e6);
        assertEq(reserve1_, 1_100e6);
        assertEq(liquidity2_, 200e6);
        assertEq(stablePool.totalSupply(), 2_200e6);
        assertEq(token0.balanceOf(address(stablePool)), 4_400e6);
        assertEq(token1.balanceOf(address(stablePool)), 1_100e6);
    }

    function test_AddLiquidity_UsesOptimalRatioWhenToken0IsInExcess() public {
        _addLiquidity(user, 4_000e6, 1_000e6);

        uint256 token0Balance_ = token0.balanceOf(user);
        uint256 token1Balance_ = token1.balanceOf(user);

        uint256 liquidity2_ = _addLiquidity(user, 1_000e6, 100e6);
        (uint256 reserve0_, uint256 reserve1_) = stablePool.getReserves();

        assertEq(token0.balanceOf(user), token0Balance_ - 400e6);
        assertEq(token1.balanceOf(user), token1Balance_ - 100e6);
        assertEq(reserve0_, 4_400e6);
        assertEq(reserve1_, 1_100e6);
        assertEq(liquidity2_, 200e6);
        assertEq(stablePool.totalSupply(), 2_200e6);
        assertEq(token0.balanceOf(address(stablePool)), 4_400e6);
        assertEq(token1.balanceOf(address(stablePool)), 1_100e6);
    }

    function test_AddLiquidity_ToDifferentOfSender() public {
        address bob = makeAddr("bob");
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;

        uint256 token0Balance_ = token0.balanceOf(user);
        uint256 token1Balance_ = token1.balanceOf(user);

        vm.prank(user);
        stablePool.addLiquidity(amount0_, amount1_, 0, 0, bob, block.timestamp);

        assertEq(stablePool.balanceOf(bob), 1_000e6 - 1_000);
        assertEq(stablePool.balanceOf(user), 0);
        assertEq(token0.balanceOf(user), token0Balance_ - amount0_);
        assertEq(token1.balanceOf(user), token1Balance_ - amount1_);
    }

    function test_AddLiquidity_FirstDeposit_MintsOneWhenSqrtIs1001() public {
        uint256 amount0_ = 1_001;
        uint256 amount1_ = 1_001;
        uint256 liquidity_ = _addLiquidity(user, amount0_, amount1_);

        assertEq(liquidity_, 1);
        assertEq(stablePool.balanceOf(user), 1);
    }

    function test_AddLiquidity_EmitsLiquidityAdded() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        uint256 expectedLiquidity = 1_000e6 - 1_000;

        vm.expectEmit(true, true, false, true, address(stablePool));
        emit StableFXPool.LiquidityAdded(user, user, amount0_, amount1_, expectedLiquidity);

        _addLiquidity(user, amount0_, amount1_);
    }

    function test_AddLiquidity_RevertWhen_Expired() public {
        vm.warp(1_000);
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        vm.expectRevert(StableFXPool.Expired.selector);
        vm.prank(user);
        stablePool.addLiquidity(amount0_, amount1_, 0, 0, user, block.timestamp - 1);
    }

    function test_AddLiquidity_RevertWhen_BelowMinOnToken0() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);

        vm.expectRevert(abi.encodeWithSelector(StableFXPool.InsufficientAmount.selector, 500e6, 600e6));
        vm.prank(user);
        stablePool.addLiquidity(1_000e6, 500e6, 600e6, 0, user, block.timestamp);
    }

    function test_AddLiquidity_RevertWhen_BelowMinOnToken1() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);

        vm.expectRevert(abi.encodeWithSelector(StableFXPool.InsufficientAmount.selector, 500e6, 600e6));
        vm.prank(user);
        stablePool.addLiquidity(500e6, 1_000e6, 0, 600e6, user, block.timestamp);
    }

    function test_AddLiquidity_RevertWhen_ZeroAmountOnToken0() public {
        uint256 amount1_ = 1_000e6;
        vm.expectRevert(StableFXPool.ZeroAmount.selector);
        vm.prank(user);
        stablePool.addLiquidity(0, amount1_, 0, 0, user, block.timestamp);
    }

    function test_AddLiquidity_RevertWhen_ZeroAmountOnToken1() public {
        uint256 amount0_ = 1_000e6;
        vm.expectRevert(StableFXPool.ZeroAmount.selector);
        vm.prank(user);
        stablePool.addLiquidity(amount0_, 0, 0, 0, user, block.timestamp);
    }

    function test_AddLiquidity_RevertWhen_InvalidRecipientWithZeroAddress() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        vm.expectRevert(StableFXPool.InvalidRecipient.selector);
        vm.prank(user);
        stablePool.addLiquidity(amount0_, amount1_, 0, 0, address(0), block.timestamp);
    }

    function test_AddLiquidity_RevertWhen_InvalidRecipientWithStableFxPoolAddress() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        vm.expectRevert(StableFXPool.InvalidRecipient.selector);
        vm.prank(user);
        stablePool.addLiquidity(amount0_, amount1_, 0, 0, address(stablePool), block.timestamp);
    }

    function test_AddLiquidity_RevertWhen_ZeroLiquid_AmountIs1000() public {
        uint256 amount0_ = 1_000;
        uint256 amount1_ = 1_000;
        vm.expectRevert(StableFXPool.InsufficientLiquidityMinted.selector);
        vm.prank(user);
        stablePool.addLiquidity(amount0_, amount1_, 0, 0, user, block.timestamp);
    }

    function test_AddLiquidity_RevertWhen_ZeroLiquid_AmountIs999() public {
        uint256 amount0_ = 999;
        uint256 amount1_ = 999;
        vm.expectRevert(StableFXPool.InsufficientLiquidityMinted.selector);
        vm.prank(user);
        stablePool.addLiquidity(amount0_, amount1_, 0, 0, user, block.timestamp);
    }

    function test_AddLiquidity_RevertWhen_ZeroLiquidOnLaterDeposit() public {
        uint256 amount0_ = 4_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);

        vm.expectRevert(StableFXPool.InsufficientLiquidityMinted.selector);
        vm.prank(user);
        stablePool.addLiquidity(1, 1_000e6, 0, 0, user, block.timestamp);
    }

    function test_RemoveLiquidity_AllLiquiditytReturnsProportionalAmounts() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        uint256 liquidity_ = _addLiquidity(user, amount0_, amount1_);

        vm.prank(user);
        (uint256 amount0Removed_, uint256 amount1Removed_) =
            stablePool.removeLiquidity(liquidity_, 0, 0, user, block.timestamp);
        (uint256 reserve0_, uint256 reserve1_) = stablePool.getReserves();

        assertEq(amount0Removed_, amount0_ - 1_000);
        assertEq(amount1Removed_, amount1_ - 1_000);
        assertEq(stablePool.balanceOf(user), 0);
        assertEq(stablePool.totalSupply(), stablePool.MINIMUM_LIQUIDITY());
        assertEq(reserve0_, 1_000);
        assertEq(reserve1_, 1_000);
        assertEq(token0.balanceOf(user), INITIAL_MINT_TOKEN - 1_000);
        assertEq(token1.balanceOf(user), INITIAL_MINT_TOKEN - 1_000);
        assertEq(token0.balanceOf(address(stablePool)), 1_000);
        assertEq(token1.balanceOf(address(stablePool)), 1_000);
    }

    function test_RemoveLiquidity_PartialWithNonTrivialRatio() public {
        uint256 amount0_ = 4_000e6;
        uint256 amount1_ = 1_000e6;
        uint256 liquidity_ = _addLiquidity(user, amount0_, amount1_);

        uint256 token0Before_ = token0.balanceOf(user);
        uint256 token1Before_ = token1.balanceOf(user);

        vm.prank(user);
        (uint256 amount0Removed_, uint256 amount1Removed_) =
            stablePool.removeLiquidity(1_000e6, 0, 0, user, block.timestamp);
        (uint256 reserve0_, uint256 reserve1_) = stablePool.getReserves();

        assertEq(amount0Removed_, 2_000e6);
        assertEq(amount1Removed_, 500e6);
        assertEq(stablePool.totalSupply(), 1_000e6);
        assertEq(stablePool.balanceOf(user), liquidity_ - 1_000e6);
        assertEq(reserve0_, 2_000e6);
        assertEq(reserve1_, 500e6);
        assertEq(token0.balanceOf(user), token0Before_ + amount0Removed_);
        assertEq(token1.balanceOf(user), token1Before_ + amount1Removed_);
        assertEq(token0.balanceOf(address(stablePool)), 2_000e6);
        assertEq(token1.balanceOf(address(stablePool)), 500e6);
    }

    function test_RemoveLiquidity_SendsTokensToRecipient() public {
        address bob = makeAddr("bob");
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        uint256 liquidity_ = _addLiquidity(user, amount0_, amount1_);

        uint256 token0Before_ = token0.balanceOf(user);
        uint256 token1Before_ = token1.balanceOf(user);

        vm.prank(user);
        stablePool.removeLiquidity(liquidity_, 0, 0, bob, block.timestamp);

        assertEq(token0.balanceOf(bob), amount0_ - 1_000);
        assertEq(token1.balanceOf(bob), amount1_ - 1_000);
        assertEq(token0.balanceOf(user), token0Before_);
        assertEq(token1.balanceOf(user), token1Before_);
        assertEq(stablePool.balanceOf(user), 0);
        assertEq(stablePool.balanceOf(bob), 0);
    }

    function test_RemoveLiquidity_EmitsLiquidityRemoved() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        uint256 liquidity_ = _addLiquidity(user, amount0_, amount1_);

        vm.expectEmit(true, true, false, true, address(stablePool));
        emit StableFXPool.LiquidityRemoved(user, user, amount0_ - 1_000, amount1_ - 1_000, liquidity_);

        vm.prank(user);
        stablePool.removeLiquidity(liquidity_, 0, 0, user, block.timestamp);
    }

    function test_RemoveLiquidity_RevertWhen_Expired() public {
        vm.warp(1_000);
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        uint256 liquidity_ = _addLiquidity(user, amount0_, amount1_);

        vm.expectRevert(StableFXPool.Expired.selector);
        vm.prank(user);
        stablePool.removeLiquidity(liquidity_, 0, 0, user, block.timestamp - 1);
    }

    function test_RemoveLiquidity_RevertWhen_InvalidRecipientWithZeroAddress() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        uint256 liquidity_ = _addLiquidity(user, amount0_, amount1_);

        vm.expectRevert(StableFXPool.InvalidRecipient.selector);
        vm.prank(user);
        stablePool.removeLiquidity(liquidity_, 0, 0, address(0), block.timestamp);
    }

    function test_RemoveLiquidity_RevertWhen_InvalidRecipientWithStableFxPoolAddress() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        uint256 liquidity_ = _addLiquidity(user, amount0_, amount1_);

        vm.expectRevert(StableFXPool.InvalidRecipient.selector);
        vm.prank(user);
        stablePool.removeLiquidity(liquidity_, 0, 0, address(stablePool), block.timestamp);
    }

    function test_RemoveLiquidity_RevertWhen_ZeroLiquidity() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);

        vm.expectRevert(StableFXPool.ZeroAmount.selector);
        vm.prank(user);
        stablePool.removeLiquidity(0, 0, 0, user, block.timestamp);
    }

    function test_RemoveLiquidity_RevertWhen_BelowMinOnToken0() public {
        uint256 amount0_ = 4_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);

        vm.expectRevert(abi.encodeWithSelector(StableFXPool.InsufficientAmount.selector, 2_000e6, 2_500e6));
        vm.prank(user);
        stablePool.removeLiquidity(1_000e6, 2_500e6, 0, user, block.timestamp);
    }

    function test_RemoveLiquidity_RevertWhen_BelowMinOnToken1() public {
        uint256 amount0_ = 4_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);

        vm.expectRevert(abi.encodeWithSelector(StableFXPool.InsufficientAmount.selector, 500e6, 600e6));
        vm.prank(user);
        stablePool.removeLiquidity(1_000e6, 0, 600e6, user, block.timestamp);
    }

    function test_RemoveLiquidity_RevertWhen_InsufficientLpBalance() public {
        uint256 amount0_ = 4_000e6;
        uint256 amount1_ = 1_000e6;
        uint256 liquidity_ = _addLiquidity(user, amount0_, amount1_);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, user, liquidity_, liquidity_ + 1)
        );
        vm.prank(user);
        stablePool.removeLiquidity(liquidity_ + 1, 0, 0, user, block.timestamp);
    }

    function test_RemoveLiquidity_RevertWhen_AmountsRoundToZero() public {
        uint256 amount0_ = 4_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);

        vm.expectRevert(StableFXPool.InsufficientLiquidityBurned.selector);
        vm.prank(user);
        stablePool.removeLiquidity(1, 0, 0, user, block.timestamp);
    }

    function test_GetAmountOut_MatchesFormula() public {
        uint256 amount0_ = 2_000e6;
        uint256 amount1_ = 2_000e6;
        _addLiquidity(user, amount0_, amount1_);

        uint256 amountIn_ = 1_000e6;
        address tokenIn_ = address(token0);

        uint256 amountOut_ = stablePool.getAmountOut(tokenIn_, amountIn_);
        assertEq(amountOut_, 666_444_407);
    }

    function test_GetAmountOut_NonTrivialRatio() public {
        uint256 amount0_ = 4_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);

        uint256 amountIn_ = 1_000e6;
        address tokenIn_ = address(token0);

        uint256 amountOut_ = stablePool.getAmountOut(tokenIn_, amountIn_);
        assertEq(amountOut_, 199_919_991);
    }

    function test_GetAmountOut_WorksWithDifferentDecimals() public {
        MockERC20 usdc_ = new MockERC20("Mock USDC", "USDC", 6);
        MockERC20 dai_ = new MockERC20("Mock DAI", "DAI", 18);
        StableFXPool pool_ = new StableFXPool(address(usdc_), address(dai_));
        uint256 amountUsdc_ = 1_000e6;
        uint256 amountDai_ = 1_000e18;

        usdc_.mint(user, amountUsdc_);
        dai_.mint(user, amountDai_);

        vm.startPrank(user);

        usdc_.approve(address(pool_), amountUsdc_);
        dai_.approve(address(pool_), amountDai_);
        pool_.addLiquidity(amountUsdc_, amountDai_, 0, 0, user, block.timestamp);

        vm.stopPrank();

        uint256 amountOut_ = pool_.getAmountOut(address(usdc_), 100e6);
        assertEq(amountOut_, 90_867_766_716_668_939_497);
    }

    function test_GetAmountOut_Token1ForToken0() public {
        _addLiquidity(user, 4_000e6, 1_000e6);

        uint256 amountOut_ = stablePool.getAmountOut(address(token1), 100e6);

        assertEq(amountOut_, 363_471_066);
    }

    function test_GetAmountOut_RevertWhen_TokenIsNotPoolToken() public {
        address tokenIn_ = makeAddr("DAI");
        uint256 amountIn_ = 1_000e6;

        vm.expectRevert(StableFXPool.InvalidToken.selector);
        stablePool.getAmountOut(tokenIn_, amountIn_);
    }

    function test_GetAmountOut_RevertWhen_ZeroAmountIn() public {
        uint256 amountIn_ = 0;

        vm.expectRevert(StableFXPool.ZeroAmount.selector);
        stablePool.getAmountOut(address(token1), amountIn_);
    }

    function test_GetAmountOut_RevertWhen_PoolHasNoLiquidity() public {
        uint256 amountIn_ = 1_000e6;

        vm.expectRevert(StableFXPool.InsufficientLiquidity.selector);
        stablePool.getAmountOut(address(token0), amountIn_);
    }

    function test_GetAmountOut_RevertWhen_OutputRoundsToZero() public {
        _addLiquidity(user, 1_000e6, 1_000e6);

        vm.expectRevert(StableFXPool.InsufficientOutputAmount.selector);
        stablePool.getAmountOut(address(token0), 1);
    }

    function test_Swap_Token0ForToken1() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);

        uint256 amountIn_ = 100e6;
        uint256 token0Before_ = token0.balanceOf(user);
        uint256 token1Before_ = token1.balanceOf(user);

        vm.prank(user);
        uint256 amountOut_ = stablePool.swapExactInput(address(token0), amountIn_, 0, user, block.timestamp);
        (uint256 reserve0_, uint256 reserve1_) = stablePool.getReserves();

        assertEq(amountOut_, 90_867_766);
        assertEq(reserve0_, 1_100e6);
        assertEq(reserve1_, 909_132_234);
        assertEq(token0.balanceOf(user), token0Before_ - 100e6);
        assertEq(token1.balanceOf(user), token1Before_ + 90_867_766);
        assertEq(token0.balanceOf(address(stablePool)), 1_100e6);
        assertEq(token1.balanceOf(address(stablePool)), 909_132_234);
    }

    function test_Swap_Token1ForToken0() public {
        uint256 amount0_ = 4_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);

        uint256 amountIn_ = 100e6;
        uint256 token0Before_ = token0.balanceOf(user);
        uint256 token1Before_ = token1.balanceOf(user);

        vm.prank(user);
        uint256 amountOut_ = stablePool.swapExactInput(address(token1), amountIn_, 0, user, block.timestamp);
        (uint256 reserve0_, uint256 reserve1_) = stablePool.getReserves();

        assertEq(amountOut_, 363_471_066);
        assertEq(reserve0_, 3_636_528_934);
        assertEq(reserve1_, 1_100e6);
        assertEq(token0.balanceOf(user), token0Before_ + 363_471_066);
        assertEq(token1.balanceOf(user), token1Before_ - 100e6);
        assertEq(token0.balanceOf(address(stablePool)), 3_636_528_934);
        assertEq(token1.balanceOf(address(stablePool)), 1_100e6);
    }

    function test_Swap_SendsOutputToRecipient() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);

        uint256 amountIn_ = 100e6;
        uint256 token0Before_ = token0.balanceOf(user);
        uint256 token1Before_ = token1.balanceOf(user);
        address bob = makeAddr("bob");

        vm.prank(user);
        uint256 amountOut_ = stablePool.swapExactInput(address(token0), amountIn_, 0, bob, block.timestamp);
        (uint256 reserve0_, uint256 reserve1_) = stablePool.getReserves();

        assertEq(amountOut_, 90_867_766);
        assertEq(reserve0_, 1_100e6);
        assertEq(reserve1_, 909_132_234);
        assertEq(token0.balanceOf(bob), 0);
        assertEq(token1.balanceOf(bob), 90_867_766);
        assertEq(token0.balanceOf(user), token0Before_ - 100e6);
        assertEq(token1.balanceOf(user), token1Before_);
        assertEq(token0.balanceOf(address(stablePool)), 1_100e6);
        assertEq(token1.balanceOf(address(stablePool)), 909_132_234);
    }

    function test_Swap_WorksWithDifferentDecimals() public {
        MockERC20 usdc_ = new MockERC20("Mock USDC", "USDC", 6);
        MockERC20 dai_ = new MockERC20("Mock DAI", "DAI", 18);
        StableFXPool pool_ = new StableFXPool(address(usdc_), address(dai_));
        uint256 amountUsdc_ = 1_100e6;
        uint256 amountDai_ = 1_000e18;

        usdc_.mint(user, amountUsdc_);
        dai_.mint(user, amountDai_);

        vm.startPrank(user);

        usdc_.approve(address(pool_), amountUsdc_);
        dai_.approve(address(pool_), amountDai_);
        uint256 amountIn_ = 100e6;
        pool_.addLiquidity(amountUsdc_ - amountIn_, amountDai_, 0, 0, user, block.timestamp);

        uint256 amountOut_ = pool_.swapExactInput(address(token0), amountIn_, 0, user, block.timestamp);
        assertEq(amountOut_, 90_867_766_716_668_939_497);

        vm.stopPrank();
    }

    function test_Swap_InvariantKIncreases() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);

        uint256 amountIn_ = 100e6;
        (uint256 reserve0Before_, uint256 reserve1Before_) = stablePool.getReserves();
        uint256 kBefore_ = reserve0Before_ * reserve1Before_;

        vm.prank(user);
        uint256 amountOut_ = stablePool.swapExactInput(address(token0), amountIn_, 0, user, block.timestamp);
        (uint256 reserve0After_, uint256 reserve1After_) = stablePool.getReserves();
        uint256 kAfter_ = reserve0After_ * reserve1After_;

        assertEq(amountOut_, 90_867_766);
        assertEq(kBefore_, 1e18);
        assertEq(kAfter_, 1_000_045_457_400_000_000);
        assertGt(kAfter_, kBefore_);
    }

    function test_Swap_EmitsSwapTokens() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);

        uint256 amountIn_ = 100e6;

        vm.expectEmit(true, true, false, true, address(stablePool));
        emit StableFXPool.SwapTokens(user, user, address(0), amountIn_, 90_867_766);

        vm.prank(user);
        stablePool.swapExactInput(address(token0), amountIn_, 0, user, block.timestamp);
    }

    function test_Swap_RevertWhen_Expired() public {
        vm.warp(1_000);
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);
        uint256 amountIn_ = 1_000e6;

        vm.expectRevert(StableFXPool.Expired.selector);
        vm.prank(user);
        stablePool.swapExactInput(address(token0), amountIn_, 0, user, block.timestamp - 1);
    }

    function test_Swap_RevertWhen_InvalidRecipientWithZeroAddress() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);
        uint256 amountIn_ = 1_000e6;

        vm.expectRevert(StableFXPool.InvalidRecipient.selector);
        vm.prank(user);
        stablePool.swapExactInput(address(token0), amountIn_, 0, address(0), block.timestamp);
    }

    function test_Swap_RevertWhen_InvalidRecipientWithStableFxPoolAddress() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);
        uint256 amountIn_ = 1_000e6;

        vm.expectRevert(StableFXPool.InvalidRecipient.selector);
        vm.prank(user);
        stablePool.swapExactInput(address(token0), amountIn_, 0, address(stablePool), block.timestamp);
    }

    function test_Swap_RevertWhen_ZeroAmountIn() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);
        uint256 amountIn_ = 0;

        vm.expectRevert(StableFXPool.ZeroAmount.selector);
        vm.prank(user);
        stablePool.swapExactInput(address(token0), amountIn_, 0, user, block.timestamp);
    }

    function test_Swap_RevertWhen_TokenIsNotPoolToken() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);
        uint256 amountIn_ = 1_000e6;
        address tokenAddress_ = makeAddr("DAI");

        vm.expectRevert(StableFXPool.InvalidToken.selector);
        vm.prank(user);
        stablePool.swapExactInput(tokenAddress_, amountIn_, 0, user, block.timestamp);
    }

    function test_Swap_RevertWhen_BelowAmountOutMin() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);
        uint256 amountIn_ = 100e6;
        uint256 amountOutMin_ = 90_867_767;

        vm.expectRevert(abi.encodeWithSelector(StableFXPool.InsufficientAmount.selector, 90_867_766, 90_867_767));
        vm.prank(user);
        stablePool.swapExactInput(address(token0), amountIn_, amountOutMin_, user, block.timestamp);
    }

    function test_Swap_RevertWhen_OutputRoundsToZero() public {
        uint256 amount0_ = 1_000e6;
        uint256 amount1_ = 1_000e6;
        _addLiquidity(user, amount0_, amount1_);
        uint256 amountIn_ = 1;

        vm.expectRevert(StableFXPool.InsufficientOutputAmount.selector);
        vm.prank(user);
        stablePool.swapExactInput(address(token0), amountIn_, 0, user, block.timestamp);
    }

    function test_Swap_RevertWhen_PoolHasNoLiquidity() public {
        uint256 amountIn_ = 1_000e6;

        vm.expectRevert(StableFXPool.InsufficientLiquidity.selector);
        vm.prank(user);
        stablePool.swapExactInput(address(token0), amountIn_, 0, user, block.timestamp);
    }

    function _addLiquidity(address provider_, uint256 amount0_, uint256 amount1_)
        internal
        returns (uint256 liquidity_)
    {
        vm.prank(provider_);
        (,, liquidity_) = stablePool.addLiquidity(amount0_, amount1_, 0, 0, provider_, block.timestamp);
    }
}
