// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

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
}

interface ILPStaking {
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. STGs to distribute per block.
        uint256 lastRewardBlock; // Last block number that STGs distribution occurs.
        uint256 accStargatePerShare; // Accumulated STGs per share, times 1e12. See below.
    }
    function stargatePerBlock() external view returns (uint256);
    function poolInfo(uint256 _index) external view returns (PoolInfo memory);
    function totalAllocPoint() external view returns (uint256);
    function getMultiplier(uint256 _from, uint256 _to) external view returns (uint256);
}

interface ILPToken {
    function totalLiquidity() external view returns (uint256);
}

contract StrategyAprOracle is UniswapV2Swapper{
    string public name;
    uint256 constant blockPerYear = 15768000; // based on 2s block on Polygon
    IStrategy public immutable strategy;
    ILPStaking public immutable lpStaking;
    ILPToken public immutable lpToken;
    uint256 stakingID;

    constructor(address _strategy, string memory _name) {
        name = _name;
        strategy = IStrategy(_strategy);
        lpStaking = ILPStaking(strategy.lpStaker());
        lpToken = ILPToken(strategy.lpToken());
        router = strategy.router(); 
        base = strategy.base();
        stakingID = strategy.stakingID();
    }

    function apr() public view returns (uint256){
        uint256 poolShareBps = (lpStaking.poolInfo(stakingID).allocPoint * 1e4 / lpStaking.totalAllocPoint());
        uint256 poolRewardsPerBlock = lpStaking.stargatePerBlock()  * poolShareBps / 10_000;
        uint256 yearlyRewardsInAsset = _getAmountOut(strategy.reward(), strategy.asset(), poolRewardsPerBlock) * blockPerYear;
        return yearlyRewardsInAsset * 1e18 / lpToken.totalLiquidity();
    }
}