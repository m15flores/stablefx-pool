// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "forge-std/Script.sol";
import "../src/StableFXPool.sol";
import "../test/mocks/MockERC20.sol";

/**
 * @dev Prints what a EUR invoice costs in USDC across pool depths. Simulation only, nothing is broadcast.
 */
contract PriceImpact is Script {
    uint256 internal constant INVOICE = 10_000e6;
    uint256 internal constant SPOT_NUM = 115;
    uint256 internal constant SPOT_DEN = 100;

    function run() external {
        uint256[4] memory depths_ = [uint256(50_000e6), 100_000e6, 1_000_000e6, 10_000_000e6];

        console.log("Invoice: 10,000 EURC | spot: 1.15 USDC per EURC | fee included");
        for (uint256 i; i < depths_.length; ++i) {
            _row(depths_[i]);
        }
    }

    function _row(uint256 eurcReserve_) private {
        uint256 usdcReserve_ = eurcReserve_ * SPOT_NUM / SPOT_DEN;

        MockERC20 usdc_ = new MockERC20("Mock USDC", "USDC", 6);
        MockERC20 eurc_ = new MockERC20("Mock EURC", "EURC", 6);
        StableFXPool pool_ = new StableFXPool(address(usdc_), address(eurc_));
        usdc_.mint(msg.sender, usdcReserve_);
        eurc_.mint(msg.sender, eurcReserve_);

        vm.startPrank(msg.sender);
        usdc_.approve(address(pool_), usdcReserve_);
        eurc_.approve(address(pool_), eurcReserve_);

        pool_.addLiquidity(usdcReserve_, eurcReserve_, 0, 0, msg.sender, block.timestamp);
        uint256 paid_ = pool_.getAmountIn(address(eurc_), INVOICE);

        vm.stopPrank();

        uint256 spotCost_ = INVOICE * SPOT_NUM / SPOT_DEN;
        uint256 extra_ = paid_ - spotCost_;
        uint256 impactBps_ = (extra_ * 10_000 + spotCost_ / 2) / spotCost_;

        console.log(
            string.concat(
                "EURC ",
                _fmt(eurcReserve_),
                " / USDC ",
                _fmt(usdcReserve_),
                " | paid ",
                _fmt(paid_),
                " | impact ",
                _fmtBps(impactBps_),
                " | extra ",
                _fmt(extra_)
            )
        );
    }

    /**
     * @dev Formats a 6-decimal amount as "11621.97" (rounded to 2 decimals).
     */
    function _fmt(uint256 amount_) private pure returns (string memory) {
        uint256 cents_ = (amount_ + 5_000) / 10_000;
        return string.concat(vm.toString(cents_ / 100), ".", _pad2(cents_ % 100));
    }

    /**
     * @dev Formats basis points as "1.06%".
     */
    function _fmtBps(uint256 bps_) private pure returns (string memory) {
        return string.concat(vm.toString(bps_ / 100), ".", _pad2(bps_ % 100), "%");
    }

    /**
     * @dev Left-pads a number below 100 to two digits ("5" becomes "05").
     */
    function _pad2(uint256 n_) private pure returns (string memory) {
        return n_ < 10 ? string.concat("0", vm.toString(n_)) : vm.toString(n_);
    }
}
