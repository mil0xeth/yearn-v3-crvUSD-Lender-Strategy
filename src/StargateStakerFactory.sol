// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {StargateStaker} from "./StargateStaker.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

contract StargateStakerFactory {
    event NewStargateStaker(address indexed strategy, address indexed asset);

    address public management;
    address public perfomanceFeeRecipient;
    address public keeper;

    constructor(
        address _management,
        address _peformanceFeeRecipient,
        address _keeper
    ) {
        management = _management;
        perfomanceFeeRecipient = _peformanceFeeRecipient;
        keeper = _keeper;
    }

    function newStargateStaker(
        address _asset,
        string memory _name,
        address _lpStaker,
        address _stargateRouter,
        uint16 _stakingID,
        address _base
    ) external returns (address) {
        IStrategy newStrategy = IStrategy(
            address(new StargateStaker(_asset, _name, _lpStaker, _stargateRouter, _stakingID, _base))
        );

        newStrategy.setPerformanceFeeRecipient(perfomanceFeeRecipient);
        newStrategy.setKeeper(keeper);
        newStrategy.setPendingManagement(management);

        emit NewStargateStaker(address(newStrategy), _asset);
        return address(newStrategy);
    }
    
    function setAddresses(
        address _management,
        address _perfomanceFeeRecipient,
        address _keeper
    ) external {
        require(msg.sender == management, "!management");
        management = _management;
        perfomanceFeeRecipient = _perfomanceFeeRecipient;
        keeper = _keeper;
    }
}
