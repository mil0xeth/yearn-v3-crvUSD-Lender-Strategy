pragma solidity ^0.8.18;

import "forge-std/console.sol";
import "./utils/Setup.sol";
import {IPool} from "src/interfaces/Stargate/IPool.sol";

contract ShutdownTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_shutdownCanWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

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

        assertEq(
            asset.balanceOf(address(strategy)),
            0,
            "no asset leftover in strategy"
        );
        assertApproxEqAbs(
            asset.balanceOf(user) + leftStrategyShares,
            balanceBefore + _amount,
            (_amount * 10) / 10_000, // 0.01% loss in rounding max.. crazy huh
            "!final balance"
        );
    }

    // TODO: Add tests for any emergency function added.
}
