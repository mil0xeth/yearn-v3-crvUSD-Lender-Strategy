// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "./SingleSidedHop.sol";

import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

contract SingleSidedHopFactory {
    address public immutable managment;
    address public immutable rewards;
    address public immutable keeper;

    event Deployed(address indexed strategy, address indexed asset);

    constructor(address _managment, address _rewards, address _keeper) {
        managment = _managment;
        rewards = _rewards;
        keeper = _keeper;
    }

    function name() external pure returns (string memory) {
        return "Yearnv3-TokeinzedSingleSidedHopFactory";
    }

    function newSingleSidedHop(
        address _asset,
        uint256 _maxSingleDeposit,
        address _lpContract,
        address _lpStaker
    ) external returns (address) {
        IStrategyInterface strategy = IStrategyInterface(
            address(
                new Strategy(
                    _asset,
                    string(abi.encodePacked("SingleSidedHop-", IERC20Metadata(address(want)).symbol())),
                    _maxSingleDeposit,
                    _lpContract,
                    _lpStaker
                )
            )
        );

        strategy.setPerformanceFeeRecipient(rewards);
        strategy.setKeeper(keeper);
        strategy.setPendingManagement(managment);

        emit Deployed(address(newStrategy), _asset);
        return address(newStrategy);
    }
}
