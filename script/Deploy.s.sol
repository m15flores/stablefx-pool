// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/StableFXPool.sol";
import "./mocks/MockEURC.sol";

contract Deploy is Script {
    address internal constant USDC = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
    uint256 internal constant USDC_SEED = 15e6;
    uint256 internal constant EURC_SEED = USDC_SEED * 100 / 115;

    function run() external {
        require(IERC20(USDC).balanceOf(msg.sender) >= USDC_SEED, "Not enough USDC.");
        address deployer_ = msg.sender;

        vm.startBroadcast();

        MockEURC eurc_ = new MockEURC();
        StableFXPool pool_ = new StableFXPool(USDC, address(eurc_));
        eurc_.mint(deployer_, EURC_SEED);

        eurc_.approve(address(pool_), EURC_SEED);
        IERC20(USDC).approve(address(pool_), USDC_SEED);
        pool_.addLiquidity(USDC_SEED, EURC_SEED, 0, 0, deployer_, block.timestamp + 1 hours);

        vm.stopBroadcast();

        console.log("USDC Address: ", USDC);
        console.log("EURC Address: ", address(eurc_));
        console.log("Pool Address: ", address(pool_));
        (uint256 reserveUsdc_, uint256 reserveEurc_) = pool_.getReserves();
        console.log("USDC Reserves: ", reserveUsdc_);
        console.log("EURC Reserves: ", reserveEurc_);
    }
}
