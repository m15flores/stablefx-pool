// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "../src/StableFXPool.sol";
import "./mocks/MockERC20.sol";

contract StableFXPoolTest is Test {
    StableFXPool stablePool;

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
}
