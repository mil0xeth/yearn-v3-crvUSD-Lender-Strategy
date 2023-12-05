// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IPool} from "src/interfaces/Stargate/IPool.sol";

interface IStrategyInterface is IStrategy {
    function setUniFees(address _token0, address _token1, uint24 _fee) external;
    function poolId() external returns (uint16);
    function pool() external view returns (IPool);
    function lpToken() external view returns (address);
}
