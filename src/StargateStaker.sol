// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TradeFactorySwapper} from "@periphery/swappers/TradeFactorySwapper.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ILPStaking, IPool, IStargateRouter} from "./interfaces/StargateInterfaces.sol";

/**
 * @title StargateStaker
 * @author 0xValJohn
 * @notice A Yearn V3 strategy that deposits native asset and stakes LP tokens in the Stargate protocol.
 * @dev 302 mainnet edition, using trade factory
 */
contract StargateStaker is BaseStrategy, TradeFactorySwapper {
    using SafeERC20 for ERC20;

    ILPStaking public immutable lpStaker;
    IStargateRouter public immutable stargateRouter;
    IPool public immutable pool;
    uint256 public immutable stakingID; // @dev pool id for staking
    uint256 internal immutable convertRate;
    uint16 public immutable poolId;
    ERC20 public immutable reward;
    ERC20 public immutable lpToken;

    constructor(address _asset, string memory _name, address _lpStaker, address _stargateRouter, uint16 _stakingID)
        BaseStrategy(_asset, _name)
    {
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
    }

    function _deployFunds(uint256 _amount) internal override {
        stargateRouter.addLiquidity(poolId, _amount, address(this));
        _stakeLP(lpToken.balanceOf(address(this)));
    }

    function _freeFunds(uint256 _amount) internal override {
        uint256 _lpAmount = (_amount * pool.totalSupply() / convertRate) / pool.totalLiquidity();
        lpStaker.withdraw(stakingID, _lpAmount); // @dev unstake
        stargateRouter.instantRedeemLocal(poolId, _lpAmount, address(this)); // @dev withdraw
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        if (!TokenizedStrategy.isShutdown()) {
            _claimRewards();
            uint256 looseAsset = ERC20(asset).balanceOf(address(this));
            if (looseAsset > 0) {
                _deployFunds(looseAsset);
            }
        }

        uint256 _totalLPTokenBalance =
            lpToken.balanceOf(address(this)) + lpStaker.userInfo(stakingID, address(this)).amount;
        uint256 amountSd = (_totalLPTokenBalance * pool.totalLiquidity()) / pool.totalSupply();
        _totalAssets = (amountSd / convertRate) + ERC20(asset).balanceOf(address(this));
    }

    function _claimRewards() internal override {
        _stakeLP(0); // @dev claim rewards
    }

    function _lpToLd(uint256 _amountLp) internal view returns (uint256) {
        uint256 amountSd = (_amountLp * pool.totalLiquidity()) / pool.totalSupply();
        return _sdToLd(amountSd);
    }

    function availableWithdrawLimit(address /*_owner*/ ) public view override returns (uint256) {
        return _sdToLd(pool.deltaCredit()) + asset.balanceOf(address(this));
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        _freeFunds(Math.min(_amount, _sdToLd(pool.deltaCredit())));
    }

    function _sdToLd(uint256 _amountSd) internal view returns (uint256) {
        return _amountSd * convertRate;
    }

    function _stakeLP(uint256 _amountToStake) internal {
        lpStaker.deposit(stakingID, _amountToStake);
    }

    function setTradeFactory(address _tradeFactory) external onlyManagement {
        _setTradeFactory(_tradeFactory, address(asset));
    }

    function addToken(address _token) external onlyManagement {
        _addToken(_token, address(asset));
    }

    function removeToken(address _token) external onlyManagement {
        _removeToken(_token, address(asset));
    }
}
