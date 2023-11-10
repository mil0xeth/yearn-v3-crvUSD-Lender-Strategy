// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";
import {Test, console2} from "forge-std/Test.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StargateStaker, ERC20} from "src/StargateStaker.sol"; 
import {IStargateRouter} from "src/interfaces/Stargate/IStargateRouter.sol";
import {ILPStaking} from "src/interfaces/Stargate/ILPStaking.sol";
import {IPool} from "src/interfaces/Stargate/IPool.sol";

contract DeltaTest is Setup {
    using SafeERC20 for ERC20;

    function test_increase_delta_credit() public {
        console2.log("Testing for", strategy.asset());
        console2.log("Block #", block.number, "Initial deltaCredit =", IPool(address((strategy.pool()))).deltaCredit());

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
        IStargateRouter(address(_stargateRouter)).addLiquidity(strategy.poolId(), 1e23, address(whale));
        IStargateRouter(address(_stargateRouter)).callDelta(strategy.poolId(), true);
        vm.roll(block.number + 1);
        console2.log("Block #", block.number, "deltaCredit =", IPool(address((strategy.pool()))).deltaCredit());
        
        // add big amount + call delta
        IStargateRouter(address(_stargateRouter)).addLiquidity(strategy.poolId(), 1e30, address(whale));
        IStargateRouter(address(_stargateRouter)).callDelta(strategy.poolId(), true);
        vm.roll(block.number + 1);
        console2.log("Block #", block.number, "deltaCredit =", IPool(address((strategy.pool()))).deltaCredit());
        
        vm.stopPrank();
    }

}
