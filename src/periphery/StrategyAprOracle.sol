// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {AprOracleBase} from "@periphery/AprOracle/AprOracleBase.sol";
import {UniswapV2Swapper} from "@periphery/swappers/UniswapV2Swapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStrategy {
    function router() external view returns (address);
    function base() external view returns (address);
    function stakingID() external view returns (uint256);
    function asset() external view returns (address);
    function reward() external view returns (address);
    function lpStaker() external view returns (address);
    function lpToken() external view returns (address);
    function decimals() external view returns (uint256);
}

interface ILPStaking {
    struct PoolInfo {
        IERC20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accStargatePerShare;
    }
    function eTokenPerSecond() external view returns (uint256);
    function poolInfo(uint256 _index) external view returns (PoolInfo memory);
    function totalAllocPoint() external view returns (uint256);
    function getMultiplier(uint256 _from, uint256 _to) external view returns (uint256);
    function lpBalances(uint256) external view returns (uint256);
}

interface ILPToken {
    function totalLiquidity() external view returns (uint256);
}

contract StrategyAprOracle is AprOracleBase, UniswapV2Swapper {

    constructor() AprOracleBase("Stargate Staker Oracle", msg.sender) {
        router = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506; // default to sushiswap v2
        base = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
    }

    /**
     * @notice Will return the expected Apr of a strategy post a debt change.
     * @dev _delta is a signed integer so that it can also represent a debt
     * decrease.
     *
     * This should return the annual expected return at the current timestamp
     * represented as 1e18.
     *
     *      ie. 10% == 1e17
     *
     * _delta will be == 0 to get the current apr.
     *
     * This will potentially be called during non-view functions so gas
     * efficiency should be taken into account.
     *
     * @param _strategy The token to get the apr for.
     * @param _delta The difference in debt.
     * @return . The expected apr for the strategy represented as 1e18.
     */
    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view override returns (uint256) {
        IStrategy strategy = IStrategy(_strategy);
        ILPStaking lpStaking = ILPStaking(strategy.lpStaker());
        uint256 stakingID = strategy.stakingID();
        uint256 poolShareBps = (lpStaking.poolInfo(stakingID).allocPoint * 1e4 / lpStaking.totalAllocPoint());
        uint256 poolRewardsPerSecond = lpStaking.eTokenPerSecond()  * poolShareBps / 10_000;
        uint256 yearlyRewardsInAsset = _getAmountOut(strategy.reward(), strategy.asset(), poolRewardsPerSecond) * 31_536_000;
        uint256 multiplier = (strategy.decimals() == 6) ? 1e18 : 1e6;
        
        if (_delta < 0) {
            return yearlyRewardsInAsset * multiplier / (lpStaking.lpBalances(strategy.stakingID()) - uint256(-_delta));
        }

        return yearlyRewardsInAsset * multiplier / (lpStaking.lpBalances(strategy.stakingID()) + uint256(_delta));
    }
}
