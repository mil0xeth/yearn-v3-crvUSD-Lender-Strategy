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
    uint256 public maxFuzzAmount;
    uint256 public minFuzzAmount;

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    // Constructor specific params
    address _lpStaker = 0x8731d54E9D02c286767d56ac03e8037C07e01e98;
    address _stargateRouter = 0x45A01E4e04F14f7A4a6702c74187c5F6222033cd;
    address _base = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270; // WMATIC
    address _stg = 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590;

    // Selector for testing
    string public token = "USDC";

    function setUp() public virtual {
        _setTokenAddrs();
        _setStakingId();

        // Set asset
        asset = ERC20(tokenAddrs[token]);

        // Set decimals
        decimals = asset.decimals();
        minFuzzAmount = 1e2 * 10 ** decimals;
        maxFuzzAmount = 1e5 * 10 ** decimals;

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
                    stakingId[token]
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
        assertApproxEqAbs(
            _strategy.totalAssets(),
            _totalAssets,
            ((_strategy.totalAssets() * 10) / 10_000) + 1,
            "!totalAssets"
        );
        assertApproxEqAbs(
            _strategy.totalDebt(),
            _totalDebt,
            ((_strategy.totalDebt() * 10) / 10_000) + 1,
            "!totalDebt"
        );
        assertApproxEqAbs(
            _strategy.totalIdle(),
            _totalIdle,
            ((_strategy.totalIdle() * 10) / 10_000) + 1,
            "!totalIdle"
        );
        assertApproxEqAbs(
            _totalAssets,
            _totalDebt + _totalIdle,
            ((_totalAssets * 10) / 10_000) + 1,
            "!Added"
        );
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
        deal(address(_stg), address(strategy), _amount / 200);
    }
}
