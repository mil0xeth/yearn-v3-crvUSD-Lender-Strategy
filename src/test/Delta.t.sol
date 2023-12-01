// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import { Setup } from "./utils/Setup.sol";
import { Test, console2 } from "forge-std/Test.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { StargateStaker, ERC20 } from "src/StargateStaker.sol";
import { IStargateRouter } from "src/interfaces/Stargate/IStargateRouter.sol";
import { ILPStaking } from "src/interfaces/Stargate/ILPStaking.sol";
import { IPool } from "src/interfaces/Stargate/IPool.sol";

contract DeltaTest is Setup {
	using SafeERC20 for ERC20;

	function setUp() public override {
		super.setUp();
	}

	function test_increase_delta_credit() public {
		console2.log("Testing for", strategy.asset());
		console2.log(
			"Block #",
			block.number,
			"Initial deltaCredit =",
			IPool(address((strategy.pool()))).deltaCredit()
		);

		deal(address(asset), address(whale), type(uint256).max);

		// set-up fees and delta params
		vm.startPrank(router_owner);
		IStargateRouter(address(_stargateRouter)).setFees(strategy.poolId(), 2);
		IStargateRouter(address(_stargateRouter)).setDeltaParam(
			strategy.poolId(),
			true,
			500, // 5%
			500, // 5%
			true, // non-default
			true // non-default
		);
		vm.stopPrank();

		// add liq
		vm.startPrank(whale);
		ERC20(asset).safeApprove(address(_stargateRouter), type(uint256).max);

		// add small amount + call delta
		IStargateRouter(address(_stargateRouter)).addLiquidity(
			strategy.poolId(),
			1e23,
			address(whale)
		);
		IStargateRouter(address(_stargateRouter)).callDelta(
			strategy.poolId(),
			true
		);
		vm.roll(block.number + 1);
		console2.log(
			"Block #",
			block.number,
			"deltaCredit =",
			IPool(address((strategy.pool()))).deltaCredit()
		);

		// add big amount + call delta
		IStargateRouter(address(_stargateRouter)).addLiquidity(
			strategy.poolId(),
			1e30,
			address(whale)
		);
		IStargateRouter(address(_stargateRouter)).callDelta(
			strategy.poolId(),
			true
		);
		vm.roll(block.number + 1);
		console2.log(
			"Block #",
			block.number,
			"deltaCredit =",
			IPool(address((strategy.pool()))).deltaCredit()
		);

		vm.stopPrank();
	}

	// forge test -vv --fork-url https://polygon-mainnet.g.alchemy.com/v2/9IkbN4uukvrtpYON0mT57re8LikV4m0Q --match-contract OperationTest
	function test_DeltaCredit_AvailableWithdrawLimit(uint256 amount) public {
		IPool pool = strategy.pool();

		// this is in SD decimals
		uint256 deltaCredit = pool.deltaCredit();

		// scaler for sd-ld
		uint256 convertRate = pool.convertRate();

		// now delta credit is in LD decimals (local decimals, underlying token decimals)
		deltaCredit = deltaCredit * convertRate;

		address tapir = address(69);

		if (strategy.availableWithdrawLimit(tapir) < amount) {
			assertTrue(
				amount > deltaCredit,
				"What's available in underlying in pool is lesser than requested"
			);
		}
	}

	function test_DeltaCredit_AvailableWithdrawLimit_StrategySide(
		uint256 amountStrategyTokens
	) public {
		IPool pool = strategy.pool();

		address tapir = address(69);

		// this is in SD decimals
		uint256 deltaCredit = pool.deltaCredit();

		// scaler for sd-ld
		uint256 convertRate = pool.convertRate();

		// now delta credit is in LD decimals (local decimals, underlying token decimals)
		deltaCredit = deltaCredit * convertRate;

		// since this is first deposit the amount of underlying tokens are also the share tokens.
		// strategy tokens are in same decimals with the underlying token so 1M * asset decimals
		// +1 for rounding
		vm.assume(
			amountStrategyTokens > deltaCredit + 1 &&
				amountStrategyTokens < 1_000_000 * 10 ** asset.decimals()
		);

		// give tapir some strategy shares that we know is more than deltaCredit in LD
		deal(address(strategy), tapir, amountStrategyTokens);
		assertEq(strategy.balanceOf(tapir), amountStrategyTokens);

		// should fail because delta credit is higher then the requested withdrawal
		// contrary to stargate our strategy fails if requested funds are higher than whats withdrawn (availableWithdrawLimit is overriden thats why)
		vm.startPrank(tapir);
		vm.expectRevert("ERC4626: withdraw more than max");
		strategy.withdraw(amountStrategyTokens, tapir, tapir);
	}

	function test_DeltaCredit_Withdrawal_StargateSide(uint256 amountLP) public {
		IPool pool = strategy.pool();

		address tapir = address(69);

		// this is in SD decimals
		uint256 deltaCredit = pool.deltaCredit();
		uint256 ts = pool.totalSupply();
		uint256 tl = pool.totalLiquidity();

		// scaler for sd-ld
		uint256 convertRate = pool.convertRate();

		// afaik all stargate tokens are 6 decimals so thats why 1M * 1e6.
		// deltaCredit is in SD and LP tokens are in SD so  *ts/tl will give you the LP tokens in correct decimals
		// +1 is for roundings
		vm.assume(
			amountLP > ((deltaCredit * ts) / tl) + 1 && amountLP < 1_000_000 * 1e6
		);

		// give tapir some strategy shares
		deal(address(pool), tapir, amountLP);
		assertEq(pool.balanceOf(tapir), amountLP);

		// stargate doesnt revert when the amount is higher, it just takes the maximum it can give.
		vm.startPrank(tapir);
		ERC20(address(pool)).approve(_stargateRouter, type(uint256).max);
		IStargateRouter(_stargateRouter).instantRedeemLocal(
			strategy.poolId(),
			amountLP,
			tapir
		);

		// the amount of LP's in SD are higher than the deltaCredit
		assertTrue((amountLP * tl) / ts > deltaCredit);

		// stargate minimum value for dc is 1
		assertEq(pool.deltaCredit(), 1);

		// some LP's are idle in the wallet, stargate didnt take them
		assertTrue(ERC20(address(pool)).balanceOf(tapir) != 0);
	}
}
