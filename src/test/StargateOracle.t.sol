pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {StrategyAprOracle} from "../StargateAprOracle.sol";


interface IStragateAprOracle {
    function apr() external view returns (uint256);
}

contract StargateOracleTest {

        address public stargateUSDC = address(0x8BBa7AFd0f9B1b664C161EC31d812a8Ec15f7e1a);
        address public stargateUSDT = address(0x2c5d0c3DB75D2f8A4957c74BE09194a9271Cf28D);


    function testAprUSDT() public {
        // deploy a new APR contract
        IStragateAprOracle _oracle = IStragateAprOracle(
            address(
                new StrategyAprOracle(
                    stargateUSDT,
                    "Stargate APR Oracle"
                )
            )
        );
        console2.log("USDT APR", _oracle.apr());
    }


    function testAprUSDC() public {
        // deploy a new APR contract
        IStragateAprOracle _oracle = IStragateAprOracle(
            address(
                new StrategyAprOracle(
                    stargateUSDC,
                    "Stargate APR Oracle"
                )
            )
        );
        console2.log("USDC APR", _oracle.apr());
    }  
}
