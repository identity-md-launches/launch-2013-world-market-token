// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WorldMarketToken} from "src/WorldMarketToken.sol";

/// @dev Complements the deployment and ordinary ERC-20 tests with aliasing, boundary values,
/// failed-operation rollback, and properties comparing different sequences of public calls.
/// forge-config: default.fuzz.runs = 1024
contract WorldMarketTokenEdgeTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;

    WorldMarketToken private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new WorldMarketToken();
        alice = makeAddr("edge-alice");
        bob = makeAddr("edge-bob");
        spender = makeAddr("edge-spender");
    }

    function test_oneWeiCanBeTransferredAndSpentExactlyOnce() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        _assertBalances(SUPPLY - 1, 0, 1, 0);
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        token.transfer(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(alice);
        token.transfer(alice, 2);
        _assertBalances(SUPPLY - 1, 1, 0, 0);
    }

    function test_delegatedSelfTransferConsumesAllowanceWithoutMovingBalance() public {
        token.transfer(alice, 10);
        vm.prank(alice);
        token.approve(spender, 7);

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, alice, 7);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, 7));
        assertEq(token.allowance(alice, spender), 0);
        _assertBalances(SUPPLY - 10, 10, 0, 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, alice, 1);
        _assertBalances(SUPPLY - 10, 10, 0, 0);
    }

    function test_holderNeedsSelfApprovalToUseTransferFrom() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);

        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        _assertBalances(SUPPLY - 1, 1, 0, 0);
    }

    function test_spenderCanReceiveTokensWithoutConsumingAnotherSpendersAllowance() public {
        token.transfer(alice, 10);
        vm.startPrank(alice);
        token.approve(spender, 3);
        token.approve(bob, 9);
        vm.stopPrank();

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, spender, 3));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(alice, bob), 9);
        assertEq(token.allowance(spender, alice), 0);
        _assertBalances(SUPPLY - 10, 7, 0, 3);
    }

    function test_largestFiniteAllowanceIsNotTreatedAsInfinite() public {
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 1 - SUPPLY);
        _assertBalances(0, SUPPLY, 0, 0);
    }

    function test_infiniteAllowanceCanBeReplacedWithFiniteThenRevoked() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        token.approve(spender, 3);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 2));
        assertEq(token.allowance(address(this), spender), 1);

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(SUPPLY - 3, 1, 2, 0);
    }

    function test_maximumDirectTransferRevertsWithBalanceError() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function test_maximumDelegatedTransferCannotUnderflowAllowanceOrBalance() public {
        token.approve(spender, type(uint256).max - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, type(uint256).max - 1, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max - 1);
        _assertBalances(SUPPLY, 0, 0, 0);

        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function test_zeroTransferFromEmitsTransferAndPreservesFiniteAllowance() public {
        token.approve(spender, 5);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 0));
        assertEq(token.allowance(address(this), spender), 5);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function test_zeroTransferFromToZeroRevertsEvenWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function test_transferFromZeroAddressCannotMint() public {
        // Either validation order must reject an invalid source, including for a zero amount.
        vm.expectRevert();
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 1);
        assertEq(token.allowance(address(0), spender), 0);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function test_zeroApprovalToZeroSpenderCannotChangeAnExistingApproval() public {
        token.approve(spender, 3);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), spender), 3);
        assertEq(token.allowance(address(this), address(0)), 0);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function test_refundingHolderDoesNotRestoreSpentAllowance() public {
        token.transfer(alice, 100);
        vm.prank(alice);
        token.approve(spender, 100);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 100));
        vm.prank(bob);
        assertTrue(token.transfer(alice, 100));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 0);
        _assertBalances(SUPPLY - 100, 100, 0, 0);
    }

    function test_approvedSpenderCannotDelegateAnOwnersAllowance() public {
        token.approve(spender, SUPPLY);
        vm.prank(spender);
        token.approve(bob, SUPPLY);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), alice, 1);

        // Bob's approval applies only to the spender's own tokens, once it actually holds any.
        token.transfer(spender, 1);
        vm.prank(bob);
        assertTrue(token.transferFrom(spender, alice, 1));
        assertEq(token.allowance(address(this), spender), SUPPLY);
        assertEq(token.allowance(address(this), bob), 0);
        assertEq(token.allowance(spender, bob), SUPPLY - 1);
        _assertBalances(SUPPLY - 1, 1, 0, 0);
    }

    function testFuzz_approvalOverwriteIsReplacementAndIdempotent(uint256 previous, uint256 replacement) public {
        assertTrue(token.approve(spender, previous));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, replacement);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function testFuzz_sufficientBalanceCannotBypassInsufficientAllowance(uint256 approved, uint256 requested) public {
        approved = bound(approved, 0, SUPPLY - 1);
        requested = bound(requested, approved + 1, SUPPLY);
        token.approve(spender, approved);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, requested)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, requested);
        assertEq(token.allowance(address(this), spender), approved);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function testFuzz_balanceFailureRollsBackFullWidthFiniteAllowance(uint256 held, uint256 approved, uint256 requested)
        public
    {
        held = bound(held, 0, SUPPLY);
        approved = bound(approved, held + 1, type(uint256).max - 1);
        requested = bound(requested, held + 1, approved);
        token.transfer(alice, held);
        vm.prank(alice);
        token.approve(spender, approved);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, requested));
        vm.prank(spender);
        token.transferFrom(alice, bob, requested);
        assertEq(token.allowance(alice, spender), approved);
        _assertBalances(SUPPLY - held, held, 0, 0);
    }

    function testFuzz_repeatedRoundTripsRestoreBalancesAndPreserveApprovals(uint256 amount, uint256 cycles) public {
        amount = bound(amount, 0, SUPPLY);
        cycles = bound(cycles, 1, 8);
        token.approve(spender, 17);
        vm.prank(alice);
        token.approve(spender, 23);

        for (uint256 i; i < cycles; ++i) {
            assertTrue(token.transfer(alice, amount));
            _assertBalances(SUPPLY - amount, amount, 0, 0);
            vm.prank(alice);
            assertTrue(token.transfer(address(this), amount));
            _assertBalances(SUPPLY, 0, 0, 0);
            assertEq(token.allowance(address(this), spender), 17);
            assertEq(token.allowance(alice, spender), 23);
        }
    }

    function testFuzz_splittingDelegatedSpendMatchesSingleSpend(uint256 approved, uint256 amount, uint256 first)
        public
    {
        // A separate instance provides an oracle based on composing calls, without reading storage
        // slots or duplicating the token's internal transfer/allowance implementation.
        WorldMarketToken singleSpend = new WorldMarketToken();
        approved = bound(approved, 0, type(uint256).max - 1);
        amount = bound(amount, 0, approved < SUPPLY ? approved : SUPPLY);
        first = bound(first, 0, amount);
        token.approve(spender, approved);
        singleSpend.approve(spender, approved);

        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertTrue(token.transferFrom(address(this), alice, amount - first));
        assertTrue(singleSpend.transferFrom(address(this), alice, amount));
        vm.stopPrank();

        assertEq(token.balanceOf(alice), singleSpend.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), singleSpend.balanceOf(address(this)));
        assertEq(token.allowance(address(this), spender), singleSpend.allowance(address(this), spender));
        assertEq(token.allowance(address(this), spender), approved - amount);
        assertEq(singleSpend.totalSupply(), SUPPLY);
        _assertBalances(SUPPLY - amount, amount, 0, 0);
    }

    function _assertBalances(uint256 deployerBalance, uint256 aliceBalance, uint256 bobBalance, uint256 spenderBalance)
        private
        view
    {
        assertEq(token.balanceOf(address(this)), deployerBalance);
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(bob), bobBalance);
        assertEq(token.balanceOf(spender), spenderBalance);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(
            token.balanceOf(address(this)) + token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(spender),
            SUPPLY
        );
    }
}
