// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "../src/StableFXPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFiatToken {
    function blacklister() external view returns (address);
    function blacklist(address account_) external;
    function isBlacklisted(address account_) external view returns (bool);
}

contract StableFXPoolForkTest is Test {
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant EURC = 0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c;

    StableFXPool internal pool;
    address internal user;
    bool internal forkEnabled;

    function setUp() public {
        string memory rpc_ = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc_).length == 0) return;

        uint256 forkBlock_ = vm.envOr("MAINNET_FORK_BLOCK", uint256(0));
        if (forkBlock_ == 0) {
            vm.createSelectFork(rpc_);
        } else {
            vm.createSelectFork(rpc_, forkBlock_);
        }
        forkEnabled = true;

        user = makeAddr("user");
        pool = new StableFXPool(USDC, EURC);

        deal(USDC, user, 5_000_000e6);
        deal(EURC, user, 5_000_000e6);

        vm.startPrank(user);
        IERC20(USDC).approve(address(pool), type(uint256).max);
        IERC20(EURC).approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    function test_Fork_PayInvoiceWithExactOutput() public {
        vm.skip(!forkEnabled);
        _seed(1_150_000e6, 1_000_000e6);

        uint256 invoice_ = 10_000e6;
        uint256 usdcBefore_ = IERC20(USDC).balanceOf(user);
        uint256 eurcBefore_ = IERC20(EURC).balanceOf(user);
        uint256 quoted_ = pool.getAmountIn(EURC, invoice_);

        vm.prank(user);
        uint256 paid_ = pool.swapExactOutput(EURC, invoice_, type(uint256).max, user, block.timestamp);
        (uint256 reserve0_, uint256 reserve1_) = pool.getReserves();

        assertEq(paid_, quoted_);
        assertApproxEqAbs(paid_, 11_621_970_000, 5_000);
        assertEq(IERC20(EURC).balanceOf(user), eurcBefore_ + invoice_);
        assertEq(IERC20(USDC).balanceOf(user), usdcBefore_ - paid_);
        assertEq(reserve0_, IERC20(USDC).balanceOf(address(pool)));
        assertEq(reserve1_, IERC20(EURC).balanceOf(address(pool)));
    }

    function test_Fork_RoundTripNeverProfits() public {
        vm.skip(!forkEnabled);
        _seed(1_150_000e6, 1_000_000e6);

        uint256 usdcBefore_ = IERC20(USDC).balanceOf(user);

        vm.startPrank(user);
        uint256 eurcOut_ = pool.swapExactInput(USDC, 10_000e6, 0, user, block.timestamp);
        pool.swapExactInput(EURC, eurcOut_, 0, user, block.timestamp);
        vm.stopPrank();

        assertLt(IERC20(USDC).balanceOf(user), usdcBefore_);
    }

    function test_Fork_BlacklistedPoolBlocksSwapsAndWithdrawals() public {
        vm.skip(!forkEnabled);
        _seed(1_150_000e6, 1_000_000e6);

        // Control: the swap works before the pool is blacklisted.
        vm.prank(user);
        pool.swapExactInput(USDC, 1_000e6, 0, user, block.timestamp);

        address blacklister_ = IFiatToken(USDC).blacklister();
        vm.prank(blacklister_);
        IFiatToken(USDC).blacklist(address(pool));
        assertTrue(IFiatToken(USDC).isBlacklisted(address(pool)));

        // The token reverts, so swaps that move USDC fail.
        vm.expectRevert();
        vm.prank(user);
        pool.swapExactInput(USDC, 1_000e6, 0, user, block.timestamp);

        // And the liquidity providers cannot withdraw: the reserves are stuck.
        uint256 liquidity_ = pool.balanceOf(user);
        vm.expectRevert();
        vm.prank(user);
        pool.removeLiquidity(liquidity_, 0, 0, user, block.timestamp);
    }

    function _seed(uint256 usdc_, uint256 eurc_) internal {
        vm.prank(user);
        pool.addLiquidity(usdc_, eurc_, 0, 0, user, block.timestamp);
    }
}
