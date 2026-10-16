// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WorldMarketToken} from "../src/WorldMarketToken.sol";

/// @dev Keeps all token movements within four actors so conservation is observable.
contract WorldMarketTokenHandler is Test {
    WorldMarketToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(WorldMarketToken token_) {
        token = token_;
        actors = [makeAddr("alice"), makeAddr("bob"), makeAddr("carol"), makeAddr("dave")];
        expectedBalance[actors[0]] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 senderSeed, uint256 recipientSeed, uint256 amount) external {
        address sender = actors[senderSeed % actors.length];
        address recipient = actors[recipientSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[sender]);

        vm.prank(sender);
        assertTrue(token.transfer(recipient, amount));
        expectedBalance[sender] -= amount;
        expectedBalance[recipient] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = unlimited ? type(uint256).max : amount;

        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];

        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 recipientSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address recipient = actors[recipientSeed % actors.length];
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner];
        if (allowance < available) available = allowance;
        amount = bound(amount, 0, available);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, recipient, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[recipient] += amount;
        if (allowance != type(uint256).max) expectedAllowance[owner][spender] = allowance - amount;
    }

    /// @dev Invalid actions leave the ghost ledger untouched. The invariants then check every
    /// actor and allowance, including accounts unrelated to the rejected transaction.
    function rejectTransferAboveBalance(uint256 senderSeed, uint256 recipientSeed, uint256 amount) external {
        address sender = actors[senderSeed % actors.length];
        address recipient = actors[recipientSeed % actors.length];
        uint256 balance = expectedBalance[sender];
        amount = bound(amount, balance + 1, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, sender, balance, amount));
        vm.prank(sender);
        token.transfer(recipient, amount);
    }

    function rejectTransferFromAboveBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 recipientSeed,
        uint256 amount,
        bool unlimited
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address recipient = actors[recipientSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        // Keep the finite approval below the infinite-allowance sentinel, even at the type boundary.
        amount = bound(amount, balance + 1, type(uint256).max - 1);
        uint256 approved = unlimited ? type(uint256).max : amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, approved));
        expectedAllowance[owner][spender] = approved;

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, recipient, amount);
    }

    function rejectTransferFromAboveAllowance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 recipientSeed,
        uint256 approved,
        uint256 amount
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address recipient = actors[recipientSeed % actors.length];
        approved = bound(approved, 0, type(uint256).max - 1);
        amount = bound(amount, approved + 1, type(uint256).max);
        vm.prank(owner);
        assertTrue(token.approve(spender, approved));
        expectedAllowance[owner][spender] = approved;

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, recipient, amount);
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 available = expectedBalance[owner];
        if (delegated && expectedAllowance[owner][spender] < available) {
            available = expectedAllowance[owner][spender];
        }
        amount = bound(amount, 0, available);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? spender : owner);
        if (delegated) token.transferFrom(owner, address(0), amount);
        else token.transfer(address(0), amount);
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract WorldMarketTokenInvariantTest is StdInvariant, Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    WorldMarketToken internal token;
    WorldMarketTokenHandler internal handler;

    function setUp() public {
        token = new WorldMarketToken();
        handler = new WorldMarketTokenHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = WorldMarketTokenHandler.transfer.selector;
        selectors[1] = WorldMarketTokenHandler.approve.selector;
        selectors[2] = WorldMarketTokenHandler.revoke.selector;
        selectors[3] = WorldMarketTokenHandler.transferFrom.selector;
        selectors[4] = WorldMarketTokenHandler.rejectTransferAboveBalance.selector;
        selectors[5] = WorldMarketTokenHandler.rejectTransferFromAboveBalance.selector;
        selectors[6] = WorldMarketTokenHandler.rejectTransferFromAboveAllowance.selector;
        selectors[7] = WorldMarketTokenHandler.rejectZeroRecipient.selector;
        selectors[8] = WorldMarketTokenHandler.rejectZeroSpender.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyIsFixedAndConserved() public view {
        uint256 balances;
        for (uint256 i; i < 4; ++i) {
            balances += token.balanceOf(handler.actors(i));
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(balances, SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariant_balancesAndAllowancesMatchReferenceModel() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.balanceOf(owner), handler.expectedBalance(owner));
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
