// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockEURC is ERC20 {
    constructor () ERC20("Mock EURC", "EURC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to_, uint256 amount_) external {
        _mint(to_, amount_);
    }
}