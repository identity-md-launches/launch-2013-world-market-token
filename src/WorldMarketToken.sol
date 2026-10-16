// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title World Market Token
/// @notice Fixed-supply ERC-20 with 18 decimals and no administrative privileges.
contract WorldMarketToken is ERC20 {
    /// @notice One billion WORLD, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mints the entire supply once to the immediate deployer.
    /// @dev When deployed by a factory, that factory receives all tokens.
    constructor() ERC20("World Market Token", "WORLD") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
