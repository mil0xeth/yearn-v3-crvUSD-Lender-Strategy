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

    /**
     * @notice Deploy a new Stargate Staker.
     * @dev This will set the msg.sender to all of the permisioned roles.
     * @param _asset The underlying asset for the lender to use.
     * @param _name The name for the lender to use.
     * @param _lpStaker The address of the LPStaker contract.
     * @param _stargateRouter The address of the StargateRouter contract.
     * @param _stakingID The ID of the pool to stake in.
     * @param _base The address of the base token.
     * @return . The address of the new lender.
     */
    function newStargateStaker(
        address _asset,
        string memory _name,
        address _lpStaker,
        address _stargateRouter,
        uint16 _stakingID,
        address _base
    ) external returns (address) {
        // We need to use the custom interface with the
        // tokenized strategies available setters.
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
