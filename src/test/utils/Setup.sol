// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "forge-std/console2.sol";
import {ExtendedTest} from "./ExtendedTest.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {StargateStaker, ERC20} from "../../StargateStaker.sol";
import {IStargateRouter} from "../../interfaces/Stargate/IStargateRouter.sol";
import {ILPStaking} from "src/interfaces/Stargate/ILPStaking.sol";
import {IPool} from "src/interfaces/Stargate/IPool.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

contract Setup is ExtendedTest, IEvents {
    using SafeERC20 for ERC20;

    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;

    mapping(string => address) public tokenAddrs;
    mapping(string => uint16) public stakingId;
    mapping(string => uint24) public rewardToBaseFee;
    mapping(string => uint24) public baseToAssetFee;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public whale = address(0x65bb797c2B9830d891D87288F029ed8dACc19705);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);
    address public router_owner =
        address(0x47290DE56E71DC6f46C26e50776fe86cc8b21656);

    // Address of the real deployed Factory
    address public factory;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $100 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 1e30;
    uint256 public minFuzzAmount;

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    // Constructor specific params
    address _lpStaker = 0x8731d54E9D02c286767d56ac03e8037C07e01e98;
    address _stargateRouter = 0x45A01E4e04F14f7A4a6702c74187c5F6222033cd;
    address _base = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270; // WMATIC
    address _stg = 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590;

    // Selector for testing
    string public token = "DAI";

    function setUp() public virtual {
        _setTokenAddrs();
        _setStakingId();
        _setRewardToBaseFee();
        _setBaseToAssetFee();

        // Set asset
        asset = ERC20(tokenAddrs[token]);

        // Set decimals
        decimals = asset.decimals();
        minFuzzAmount = 1e2 * 10 ** decimals;

        // Deploy strategy and set variables
        strategy = IStrategyInterface(setUpStrategy());

        factory = strategy.FACTORY();

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
    }

    function setUpStrategy() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            address(
                new StargateStaker(
                    address(asset),
                    "Tokenized Strategy",
                    _lpStaker,
                    _stargateRouter,
                    stakingId[token],
                    _base
                )
            )
        );

        // set keeper
        _strategy.setKeeper(keeper);
        // set treasury
        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        // set management of the strategy
        _strategy.setPendingManagement(management);

        vm.startPrank(management);
        _strategy.acceptManagement();

        // set swapper fees
        _strategy.setUniFees(_stg, _base, rewardToBaseFee[token]);
        _strategy.setUniFees(_base, address(asset), baseToAssetFee[token]);
        vm.stopPrank();
        return address(_strategy);
    }

    function depositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        assertEq(_strategy.totalAssets(), _totalAssets, "!totalAssets");
        assertEq(_strategy.totalDebt(), _totalDebt, "!totalDebt");
        assertEq(_strategy.totalIdle(), _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = IFactory(factory).governance();

        // Need to make sure there is a protocol fee recipient to set the fee.
        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    function _setTokenAddrs() internal {
        tokenAddrs["DAI"] = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
        tokenAddrs["USDT"] = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
        tokenAddrs["USDC"] = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    }

    function _setStakingId() internal {
        stakingId["DAI"] = 2;
        stakingId["USDT"] = 1;
        stakingId["USDC"] = 0;
    }

    function _setRewardToBaseFee() internal {
        rewardToBaseFee["DAI"] = 3000;
        rewardToBaseFee["USDT"] = 3000;
        rewardToBaseFee["USDC"] = 3000;
    }

    function _setBaseToAssetFee() internal {
        baseToAssetFee["DAI"] = 500;
        baseToAssetFee["USDT"] = 500;
        baseToAssetFee["USDC"] = 500;
    }

    function _mockRewards(uint256 _amount) internal {
        deal(address(_stg), address(strategy), (_amount * 1e18) / 200);
    }

    function _mockDeltaCredits() internal {
        console2.log(
            "credit before",
            IPool(address((strategy.pool()))).deltaCredit()
        );
        deal(address(asset), address(whale), type(uint256).max);

        // @dev this is not working in foundry, lp token is exotic token
        deal(
            address(strategy.lpToken()),
            address(_stargateRouter),
            type(uint256).max
        );
        deal(
            address(strategy.lpToken()),
            address(strategy.pool()),
            type(uint256).max
        );

        vm.startPrank(whale);
        ERC20(asset).safeApprove(address(_stargateRouter), type(uint256).max);
        IStargateRouter(address(_stargateRouter)).addLiquidity(
            strategy.poolId(),
            1e24,
            address(whale)
        );
        vm.stopPrank();

        skip(5 days);
        // vm.roll(block.number + 5);

        IStargateRouter(address(_stargateRouter)).callDelta(
            strategy.poolId(),
            true
        );

        console2.log(
            "credit after",
            IPool(address((strategy.pool()))).deltaCredit()
        );
        vm.roll(block.number + 5);
        console2.log(
            "credit after roll",
            IPool(address((strategy.pool()))).deltaCredit()
        );
    }
}
