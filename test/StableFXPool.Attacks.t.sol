// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "../src/StableFXPool.sol";
import "./mocks/MockERC20.sol";

contract StableFXPoolAttackTest is Test {
    StableFXPool stablePool;
    MockERC20 token0;
    MockERC20 token1;
    address user;
    address attacker;

    uint256 public constant INITIAL_MINT_TOKEN = 1_000_000e6;

    function setUp() public {
        user = makeAddr("user");
        attacker = makeAddr("attacker");
        token0 = new MockERC20("Mock USDC", "USDC", 6);
        token1 = new MockERC20("Mock EURC", "EURC", 6);
        stablePool = new StableFXPool(address(token0), address(token1));
        _fund(user);
        _fund(attacker);
    }

    function test_Attack_FirstDepositorInflationIsUnprofitable() public {
        uint256 donation_ = 1_000e6;
        uint256 victimDeposit_ = 1_000e6;
        uint256 attacker0Before_ = token0.balanceOf(attacker);
        uint256 attacker1Before_ = token1.balanceOf(attacker);

        // 1. The attacker makes the smallest possible first deposit
        vm.prank(attacker);
        (,, uint256 attackerLp_) = stablePool.addLiquidity(1_001, 1_001, 0, 0, attacker, block.timestamp);
        assertEq(attackerLp_, 1);

        // 2. Then donates straight to the pool, bypassing addLiquidity
        vm.startPrank(attacker);
        assertTrue(token0.transfer(address(stablePool), donation_));
        assertTrue(token1.transfer(address(stablePool), donation_));
        vm.stopPrank();

        (uint256 reserve0_, uint256 reserve1_) = stablePool.getReserves();
        assertEq(reserve0_, 1_001);
        assertEq(reserve1_, 1_001);
        assertEq(token0.balanceOf(address(stablePool)), donation_ + 1_001);
        assertEq(token1.balanceOf(address(stablePool)), donation_ + 1_001);

        // 3. The victim deposits and gets a fair share
        vm.prank(user);
        (,, uint256 victimLp_) = stablePool.addLiquidity(victimDeposit_, victimDeposit_, 0, 0, user, block.timestamp);
        assertEq(victimLp_, victimDeposit_);

        // 4. The victim withdraws everything back
        vm.prank(user);
        (uint256 victim0_, uint256 victim1_) = stablePool.removeLiquidity(victimLp_, 0, 0, user, block.timestamp);
        assertEq(victim0_, victimDeposit_);
        assertEq(victim1_, victimDeposit_);

        // 5. The attacker exits with 1 wei of each token
        vm.prank(attacker);
        (uint256 attacker0_, uint256 attacker1_) =
            stablePool.removeLiquidity(attackerLp_, 0, 0, attacker, block.timestamp);
        assertEq(attacker0_, 1);
        assertEq(attacker1_, 1);

        // 6. The attack lost money: donation plus the locked minimum
        assertEq(token0.balanceOf(attacker), attacker0Before_ - donation_ - 1_000);
        assertEq(token1.balanceOf(attacker), attacker1Before_ - donation_ - 1_000);

        // 7. The donation stays locked in the pool
        (reserve0_, reserve1_) = stablePool.getReserves();
        assertEq(reserve0_, 1_000);
        assertEq(reserve1_, 1_000);
        assertEq(token0.balanceOf(address(stablePool)), donation_ + 1_000);
        assertEq(token1.balanceOf(address(stablePool)), donation_ + 1_000);
    }

    function test_Attack_DirectDonationDoesNotMovePrice() public {
        uint256 donation_ = 500e6;

        vm.prank(user);
        stablePool.addLiquidity(1_000e6, 1_000e6, 0, 0, user, block.timestamp);
        uint256 quoteBefore_ = stablePool.getAmountOut(address(token0), 100e6);
        assertEq(quoteBefore_, 90_867_766);

        // The attacker donates token0 straight to the pool, bypassing addLiquidity
        vm.prank(attacker);
        assertTrue(token0.transfer(address(stablePool), donation_));

        // Reserves and quote ignore the donation; only the real balance grows
        (uint256 reserve0_, uint256 reserve1_) = stablePool.getReserves();
        assertEq(reserve0_, 1_000e6);
        assertEq(reserve1_, 1_000e6);
        assertEq(token0.balanceOf(address(stablePool)), 1_000e6 + donation_);
        assertEq(stablePool.getAmountOut(address(token0), 100e6), quoteBefore_);

        // A swap pays the same as before the donation
        vm.prank(user);
        uint256 amountOut_ = stablePool.swapExactInput(address(token0), 100e6, 0, user, block.timestamp);
        assertEq(amountOut_, 90_867_766);

        (reserve0_, reserve1_) = stablePool.getReserves();
        assertEq(reserve0_, 1_100e6);
        assertEq(reserve1_, 909_132_234);
        assertEq(token0.balanceOf(address(stablePool)), 1_600e6);
    }

    function _fund(address account_) internal {
        token0.mint(account_, INITIAL_MINT_TOKEN);
        token1.mint(account_, INITIAL_MINT_TOKEN);
        vm.startPrank(account_);
        token0.approve(address(stablePool), INITIAL_MINT_TOKEN);
        token1.approve(address(stablePool), INITIAL_MINT_TOKEN);
        vm.stopPrank();
    }
}
