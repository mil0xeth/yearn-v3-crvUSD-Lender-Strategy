// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    function lpStaker() external returns(address);
    function setFees(uint24, uint24) external;
    //TODO: Add your specific implementation interface in here.
}
