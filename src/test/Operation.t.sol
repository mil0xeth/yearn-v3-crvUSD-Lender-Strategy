// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";
import {Test, console2} from "forge-std/Test.sol"; //@todo: remove
import {IPool} from "src/interfaces/Stargate/IPool.sol";

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
        // this happens when we add big add liquidity, deltaCredit is replenished
        // very interesting design and thanks to fuzzing we are able to catch this edge case!
        uint256 leftStrategyShares;
        uint256 actualAmountWithdrawn;
        if (strategy.availableWithdrawLimit(user) < _amount) {
            actualAmountWithdrawn = strategy.availableWithdrawLimit(user);
            leftStrategyShares = strategy.convertToAssets(
                strategy.balanceOf(user) -
                    strategy.convertToShares(actualAmountWithdrawn)
            );

            if (leftStrategyShares == strategy.balanceOf(user)) {
                actualAmountWithdrawn = type(uint256).max;
            }
        } else {
            actualAmountWithdrawn = _amount;
        }

        if (actualAmountWithdrawn != type(uint256).max) {
            vm.prank(user);
            strategy.redeem(actualAmountWithdrawn, user, user);
        }

        assertApproxEqAbs(
            asset.balanceOf(user) + leftStrategyShares,
            balanceBefore + _amount,
            (_amount * 10) / 10_000, // 0.01% loss in rounding max.. crazy huh
            "!final balance"
        );
    }

    function test_profitableReport(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        IPool pool = strategy.pool();

        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        // skip(1 days);
        // _mockRewards(_amount);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;

        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertApproxEqAbs(
            profit,
            toAirdrop,
            (toAirdrop * 10) / 10_000,
            "!profit"
        );
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        // this happens when we add big add liquidity, deltaCredit is replenished
        // very interesting design and thanks to fuzzing we are able to catch this edge case!
        uint256 leftStrategyShares;
        uint256 actualAmountWithdrawn;
        if (strategy.availableWithdrawLimit(user) < _amount) {
            actualAmountWithdrawn = strategy.availableWithdrawLimit(user);
            leftStrategyShares = strategy.convertToAssets(
                strategy.balanceOf(user) -
                    strategy.convertToShares(actualAmountWithdrawn)
            );

            if (strategy.convertToShares(actualAmountWithdrawn) == 0) {
                actualAmountWithdrawn = type(uint256).max;
            }
        } else {
            actualAmountWithdrawn = _amount;
        }

        if (actualAmountWithdrawn != type(uint256).max) {
            vm.startPrank(user);
            strategy.redeem(
                strategy.convertToShares(actualAmountWithdrawn),
                user,
                user
            );
            vm.stopPrank();
        }

        assertGe(
            asset.balanceOf(user) +
                leftStrategyShares +
                (_amount * 10) /
                10_000,
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_profitableReport_withFees(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        IPool pool = strategy.pool();
        uint256 deltaCredit = pool.deltaCredit();
        deltaCredit = deltaCredit * pool.convertRate();
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

        // Set protocol fee to 0 and perf fee to 10%
        setFees(0, 1_000);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // // Earn Interest
        // skip(1 days);
        // _mockRewards(_amount);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertApproxEqAbs(
            profit,
            toAirdrop,
            (toAirdrop * 10) / 10_000,
            "!profit"
        );
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Get the expected fee
        uint256 expectedShares = (profit * 1_000) / MAX_BPS;

        assertEq(strategy.balanceOf(performanceFeeRecipient), expectedShares);

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        // Withdraw all funds
        // this happens when we add big add liquidity, deltaCredit is replenished
        // very interesting design and thanks to fuzzing we are able to catch this edge case!
        uint256 leftStrategyShares;
        uint256 actualAmountWithdrawn;
        if (strategy.availableWithdrawLimit(user) < _amount) {
            actualAmountWithdrawn = strategy.availableWithdrawLimit(user);
            leftStrategyShares = strategy.convertToAssets(
                strategy.balanceOf(user) -
                    strategy.convertToShares(actualAmountWithdrawn)
            );

            if (strategy.convertToShares(actualAmountWithdrawn) == 0) {
                actualAmountWithdrawn = type(uint256).max;
            }
        } else {
            actualAmountWithdrawn = _amount;
        }

        if (actualAmountWithdrawn != type(uint256).max) {
            vm.startPrank(user);
            strategy.redeem(
                strategy.convertToShares(actualAmountWithdrawn),
                user,
                user
            );
            vm.stopPrank();
        }

        assertGe(
            asset.balanceOf(user) +
                leftStrategyShares +
                (_amount * 10) /
                10_000,
            balanceBefore + _amount,
            "!final balance"
        );

        assertEq(
            strategy.balanceOf(performanceFeeRecipient),
            expectedShares,
            "!expected shares"
        );
    }

    function test_tendTrigger(uint256 _amount) public {
        IPool pool = strategy.pool();
        uint256 deltaCredit = pool.deltaCredit();
        deltaCredit = deltaCredit * pool.convertRate();
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        (bool trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Skip some time
        skip(1 days);

        // respect the sushiswap liquidity
        uint256 _rewardsAmount = _amount;
        if (_rewardsAmount < 1e18) _rewardsAmount = 1e18;
        else if (_rewardsAmount > 100_000 * 1e18)
            _rewardsAmount = 100_000 * 1e18;
        _mockRewards(_rewardsAmount);

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
