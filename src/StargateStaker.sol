// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseHealthCheck, ERC20} from "@periphery/HealthCheck/BaseHealthCheck.sol";
import {UniswapV2Swapper} from "@periphery/swappers/UniswapV2Swapper.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ILPStaking} from "./interfaces/Stargate/ILPStaking.sol";
import {IPool} from "./interfaces/Stargate/IPool.sol";
import {IStargateRouter} from "./interfaces/Stargate/IStargateRouter.sol";

/**
 * @title StargateStaker
 * @author 0xValJohn
 * @notice A Yearn V3 strategy that deposits native asset and stakes LP tokens in the Stargate protocol.
 */

contract StargateStaker is BaseHealthCheck, UniswapV2Swapper {
    using SafeERC20 for ERC20;

    ILPStaking public immutable lpStaker;
    IStargateRouter public immutable stargateRouter;
    IPool public immutable pool;

    uint256 public immutable stakingID; // @dev pool id for staking
    uint256 internal immutable convertRate;
    uint16 public immutable poolId;

    ERC20 public immutable reward;
    ERC20 public immutable lpToken;

    event MinToSellUpdated(uint256 newMinAmountToSell);

    constructor(
        address _asset,
        string memory _name,
        address _lpStaker,
        address _stargateRouter,
        uint16 _stakingID
    ) BaseHealthCheck(_asset, _name) {
        lpStaker = ILPStaking(_lpStaker);
        stargateRouter = IStargateRouter(_stargateRouter);
        stakingID = _stakingID;

        lpToken = lpStaker.poolInfo(_stakingID).lpToken;
        require(address(lpToken) != address(0), "Invalid lpToken");

        pool = IPool(address(lpToken));
        require(pool.token() == _asset, "Invalid asset");

        poolId = uint16(pool.poolId());
        reward = ERC20(lpStaker.stargate());
        convertRate = pool.convertRate();

        lpToken.safeApprove(address(lpStaker), type(uint256).max);
        ERC20(_asset).safeApprove(address(stargateRouter), type(uint256).max);

        _setLossLimitRatio(5);

        // default to sushiswap v2
        router = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;

        // usdc_e
        base = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    }

    function _deployFunds(uint256 _amount) internal override {
        stargateRouter.addLiquidity(poolId, _amount, address(this));
        _stakeLP(lpToken.balanceOf(address(this)));
    }

    function _freeFunds(uint256 _amount) internal override {
        uint256 _lpAmount = _ldToLp(_amount);
        lpStaker.withdraw(stakingID, _lpAmount); // @dev unstake
        stargateRouter.instantRedeemLocal(poolId, _lpAmount, address(this)); // @dev withdraw
    }

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        if (!TokenizedStrategy.isShutdown()) {
            _claimAndSellRewards();
            uint256 looseAsset = ERC20(asset).balanceOf(address(this));
            if (looseAsset > 0) {
                _deployFunds(looseAsset);
            }
        }
        uint256 _totalLPTokenBalance = lpToken.balanceOf(address(this)) +
            lpStaker.userInfo(stakingID, address(this)).amount;
        _totalAssets =
            _lpToLd(_totalLPTokenBalance) +
            ERC20(asset).balanceOf(address(this));
    }

    function _claimAndSellRewards() internal {
        _stakeLP(0); // @dev claim rewards
        uint256 _rewardBalance = reward.balanceOf(address(this));
        _swapFrom(address(reward), address(asset), _rewardBalance, 0);
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        _freeFunds(Math.min(_amount, _sdToLd(pool.deltaCredit())));
    }

    // LD -> Local decimals (underlying tokens decimals USDT-USDC-DAI)
    // SD -> Shared decimals (lp tokens decimals)
    // LP -> LP token, in SD decimals
    // deltaCredit -> Available underlying token to redeem for, in SD decimals

    function _ldToLp(uint256 _amountLd) internal view returns (uint256) {
        uint256 amountSd = _ldToSd(_amountLd);
        return (amountSd * pool.totalSupply()) / pool.totalLiquidity();
    }

    function _lpToLd(uint256 _amountLp) internal view returns (uint256) {
        uint256 amountSd = (_amountLp * pool.totalLiquidity()) /
            pool.totalSupply();
        return _sdToLd(amountSd);
    }

    function _ldToSd(uint256 _amountLd) internal view returns (uint256) {
        return _amountLd / convertRate;
    }

    function _sdToLd(uint256 _amountSd) internal view returns (uint256) {
        return _amountSd * convertRate;
    }

    function _stakeLP(uint256 _amountToStake) internal {
        lpStaker.deposit(stakingID, _amountToStake);
    }

    function availableWithdrawLimit(
        address _owner
    ) public view override returns (uint256) {
        return _sdToLd(pool.deltaCredit()) + TokenizedStrategy.totalIdle();
    }

    function setMinAmountToSell(
        uint256 _minAmountToSell
    ) external onlyManagement {
        minAmountToSell = _minAmountToSell;
        emit MinToSellUpdated(_minAmountToSell);
    }

    function setBase(address _base) external onlyManagement {
        base = _base;
    }
}
