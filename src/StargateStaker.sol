// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ILPStaking} from "./interfaces/Stargate/ILPStaking.sol";
import {IPool} from "./interfaces/Stargate/IPool.sol";
import {IStargateRouter} from "./interfaces/Stargate/IStargateRouter.sol";

/**
 * @title StargateStaker
 * @author 0xValJohn
 * @notice A Yearn V3 strategy that stakes LP tokens in the Stargate protocol.
 */

contract StargateStaker is BaseStrategy, UniswapV3Swapper {
    using SafeERC20 for ERC20;

    ILPStaking public immutable lpStaker;
    IStargateRouter public immutable stargateRouter;
    IPool public immutable pool;
    uint256 public immutable stakingID; // @dev Pool ID for LPStaking
    ERC20 public immutable reward;
    ERC20 public immutable lpToken;
    uint256 public immutable convertRate;
    address internal constant _router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    event MinToSellUpdated(uint256 newMinAmountToSell);

    constructor(
        address _asset,
        string memory _name,
        address _lpStaker,
        address _stargateRouter,
        uint16 _stakingID,
        address _base
    ) BaseStrategy(_asset, _name) {
        lpStaker = ILPStaking(_lpStaker);
        stargateRouter = IStargateRouter(_stargateRouter);
        stakingID = _stakingID;
        lpToken = lpStaker.poolInfo(_stakingID).lpToken;
        require(address(lpToken) != address(0), "Invalid lpToken");
        pool = IPool(address(lpToken));
        require(pool.token() == _asset, "Invalid asset");
        lpToken.safeApprove(address(lpStaker), type(uint256).max);
        ERC20(_asset).safeApprove(address(stargateRouter), type(uint256).max);
        reward = ERC20(lpStaker.stargate());
        base = _base;
        convertRate = pool.convertRate();
    }

    function _deployFunds(uint256 _amount) internal override {
        stargateRouter.addLiquidity(pool.poolId(), _amount, address(this));
        _stakeLP(lpToken.balanceOf(address(this)));
    }

    function _freeFunds(uint256 _amount) internal override {
        uint256 _lpAmount = _ldToLp(_amount);
        lpStaker.withdraw(stakingID, _lpAmount); // @dev Unstake
        stargateRouter.instantRedeemLocal(uint16(pool.poolId()), _lpAmount, address(this)); // @dev Withdraw
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        if (!TokenizedStrategy.isShutdown()) {
            _claimAndSellRewards();
            uint256 looseAsset = ERC20(asset).balanceOf(address(this));
            if (looseAsset > 0) {
                _deployFunds(looseAsset);
            }
        }

        _totalAssets = valueOfLPTokens() + ERC20(asset).balanceOf(address(this));
    }

    function _claimAndSellRewards() internal {
        _stakeLP(0); // @dev Claim rewards
        uint256 _rewardBalance = reward.balanceOf(address(this));
        _swapFrom(address(reward), address(asset), _rewardBalance, 0);
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        _freeFunds(Math.min(_ldToLp(_amount), pool.deltaCredit()));
    }

    function _ldToLp(uint256 _amountLD) internal view returns (uint256) {
        return _amountLD * pool.totalSupply() / pool.totalLiquidity() / convertRate;
    }

    function _stakeLP(uint256 _amountToStake) internal {
        lpStaker.deposit(stakingID, _amountToStake);
    }

    function availableWithdrawLimit(address _owner) public view override returns (uint256) {
        return pool.deltaCredit() + TokenizedStrategy.totalIdle();
    }

    function valueOfLPTokens() public view returns (uint256) {
        uint256 _totalLPTokenBalance =
            lpToken.balanceOf(address(this)) + lpStaker.userInfo(stakingID, address(this)).amount;
        return _totalLPTokenBalance * pool.totalLiquidity() * convertRate / pool.totalSupply();
    }

    function setUniFees(address _token0, address _token1, uint24 _fee) external onlyManagement {
        _setUniFees(_token0, _token1, _fee);
    }

    function setMinAmountToSell(uint256 _minAmountToSell) external onlyManagement {
        minAmountToSell = _minAmountToSell;
        emit MinToSellUpdated(_minAmountToSell);
    }
}
