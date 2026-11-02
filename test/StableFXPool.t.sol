// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "../src/StableFXPool.sol";
import "./mocks/MockERC20.sol";

contract StableFXPoolTest is Test {
    StableFXPool stablePool;
    MockERC20 token0;
    MockERC20 token1;
    address user;

    uint256 public constant INITIAL_MINT_TOKEN = 1_000_000e6;

    event LiquidityAdded(
        address indexed sender, address indexed to, uint256 amount0, uint256 amount1, uint256 liquidity
    );
    event LiquidityRemoved(
        address indexed sender, address indexed to, uint256 amount0, uint256 amount1, uint256 liquidity
    );

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
        emit LiquidityAdded(user, user, amount0_, amount1_, expectedLiquidity);

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

    function _addLiquidity(address provider_, uint256 amount0_, uint256 amount1_)
        internal
        returns (uint256 liquidity_)
    {
        vm.prank(provider_);
        (,, liquidity_) = stablePool.addLiquidity(amount0_, amount1_, 0, 0, provider_, block.timestamp);
    }
}
