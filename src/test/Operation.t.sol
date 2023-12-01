// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import { Setup } from "./utils/Setup.sol";
import { Test, console2 } from "forge-std/Test.sol"; //@todo: remove
import { IPool } from "src/interfaces/Stargate/IPool.sol";

contract OperationTest is Setup {
	function setUp() public override {
		super.setUp();
	}

	function testSetupStrategyOK() public {
		console.log("address of strategy", address(strategy));
		assertTrue(address(0) != address(strategy));
		assertEq(strategy.asset(), address(asset));
		assertEq(strategy.management(), management);
		assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
		assertEq(strategy.keeper(), keeper);
	}

	function test_operation(uint256 _amount) public {
		IPool pool = strategy.pool();

		// convert delta credit to LD
		uint256 deltaCredit = pool.deltaCredit();
		deltaCredit = deltaCredit * pool.convertRate();

		vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

		// Deposit into strategy
		mintAndDepositIntoStrategy(strategy, user, _amount);

		// Implement logic so totalDebt is _amount and totalIdle = 0.
		checkStrategyTotals(strategy, _amount, _amount, 0);

		// Earn rewards
		vm.roll(block.number + 100);

		// Report profit
		vm.prank(keeper);
		(uint256 profit, uint256 loss) = strategy.report();

		// Check return Values
		assertGe(profit, 0, "!profit");
		assertEq(loss, 0, "!loss");

		skip(strategy.profitMaxUnlockTime());

		uint256 balanceBefore = asset.balanceOf(user);

		// Withdraw all funds
		vm.prank(user);
		strategy.redeem(_amount, user, user);

		assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
	}

	function test_profitableReport(uint256 _amount, uint16 _profitFactor) public {
		IPool pool = strategy.pool();
		// delta credit is in SD, amount is in LD
		uint256 deltaCredit = pool.deltaCredit();
		deltaCredit = deltaCredit * pool.convertRate();

		vm.assume(
			_amount > minFuzzAmount &&
				_amount < maxFuzzAmount &&
		);
		_profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

		// Deposit into strategy
		mintAndDepositIntoStrategy(strategy, user, _amount);

		// TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
		checkStrategyTotals(strategy, _amount, _amount, 0);

		// Earn Interest
		skip(1 days);
		_mockRewards(_amount);

		// TODO: implement logic to simulate earning interest.
		uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
		airdrop(asset, address(strategy), toAirdrop);

		// Report profit
		vm.prank(keeper);
		(uint256 profit, uint256 loss) = strategy.report();

		// Check return Values
		assertGe(profit, toAirdrop, "!profit");
		assertEq(loss, 0, "!loss");

		skip(strategy.profitMaxUnlockTime());

		uint256 balanceBefore = asset.balanceOf(user);

		// Withdraw all funds
		vm.prank(user);
		strategy.redeem(_amount, user, user);

		assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
	}

	function test_profitableReport_withFees(
		uint256 _amount,
		uint16 _profitFactor
	) public {
		IPool pool = strategy.pool();
		uint256 deltaCredit = pool.deltaCredit();
		deltaCredit = deltaCredit * pool.convertRate();
		vm.assume(
			_amount > minFuzzAmount &&
				_amount < maxFuzzAmount &&
		);
		_profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

		// Set protocol fee to 0 and perf fee to 10%
		setFees(0, 1_000);

		// Deposit into strategy
		mintAndDepositIntoStrategy(strategy, user, _amount);

		// TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
		checkStrategyTotals(strategy, _amount, _amount, 0);

		// Earn Interest
		skip(1 days);
		_mockRewards(_amount);

		// TODO: implement logic to simulate earning interest.
		uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
		airdrop(asset, address(strategy), toAirdrop);

		// Report profit
		vm.prank(keeper);
		(uint256 profit, uint256 loss) = strategy.report();

		// Check return Values
		assertGe(profit, toAirdrop, "!profit");
		assertEq(loss, 0, "!loss");

		skip(strategy.profitMaxUnlockTime());

		// Get the expected fee
		uint256 expectedShares = (profit * 1_000) / MAX_BPS;

		assertEq(strategy.balanceOf(performanceFeeRecipient), expectedShares);

		uint256 balanceBefore = asset.balanceOf(user);

		// Withdraw all funds
		vm.prank(user);
		strategy.redeem(_amount, user, user);

		assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");

		vm.prank(performanceFeeRecipient);
		strategy.redeem(
			expectedShares,
			performanceFeeRecipient,
			performanceFeeRecipient
		);

		checkStrategyTotals(strategy, 0, 0, 0);

		assertGe(
			asset.balanceOf(performanceFeeRecipient),
			expectedShares,
			"!perf fee out"
		);
	}

	function test_tendTrigger(uint256 _amount) public {
		IPool pool = strategy.pool();
		uint256 deltaCredit = pool.deltaCredit();
		deltaCredit = deltaCredit * pool.convertRate();
		vm.assume(
			_amount > minFuzzAmount &&
				_amount < maxFuzzAmount &&
				_amount > deltaCredit + 1
		);

		(bool trigger, ) = strategy.tendTrigger();
		assertTrue(!trigger);

		// Deposit into strategy
		mintAndDepositIntoStrategy(strategy, user, _amount);

		(trigger, ) = strategy.tendTrigger();
		assertTrue(!trigger);

		// Skip some time
		skip(1 days);
		_mockRewards(_amount);

		(trigger, ) = strategy.tendTrigger();
		assertTrue(!trigger);

		vm.prank(keeper);
		strategy.report();

		(trigger, ) = strategy.tendTrigger();
		assertTrue(!trigger);

		// Unlock Profits
		skip(strategy.profitMaxUnlockTime());

		(trigger, ) = strategy.tendTrigger();
		assertTrue(!trigger);

		vm.prank(user);
		strategy.redeem(_amount, user, user);

		(trigger, ) = strategy.tendTrigger();
		assertTrue(!trigger);
	}
}
