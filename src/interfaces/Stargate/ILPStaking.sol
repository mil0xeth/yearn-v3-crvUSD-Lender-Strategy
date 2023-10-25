// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface ILPStaking {
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    struct PoolInfo {
        ERC20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accStargatePerShare;
    }

    function poolInfo(uint256 _index) external view returns (PoolInfo memory);
    function userInfo(uint256 _pid, address _user) external view returns (UserInfo memory);
    function stargate() external view returns (address);
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function massUpdatePools() external;
    function updatePool(uint256 _pid) external;
    function pendingStargate(uint256 _pid, address _user) external view returns (uint256);

}
