// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/Hop/ISwap.sol";
import "./interfaces/Hop/IStakingRewards.sol";

import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";

// quickswap v3 (for HOP -> WETH)
interface ISwapRouter {
    struct ExactInputSingleParams {
            address tokenIn;
            address tokenOut;
            address recipient;
            uint256 deadline;
            uint256 amountIn;
            uint256 amountOutMinimum;
            uint160 limitSqrtPrice;
        }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract Strategy is BaseStrategy, UniswapV3Swapper {
    using SafeERC20 for ERC20;

    QuickSwapRouter public constant quickSwapRouter = ISwapRouter(0xf5b509bB0909a69B1c207E495f687a596C168E12);
    address internal constant weth = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address internal constant hop = 0xc5102fE9359FD9a28f877a67E36B0F050d81a3CC;

    uint256 public maxSlippage;
    uint256 public maxSingleDeposit;
    uint256 public maxHopToSell;
    uint256 internal constant MAX_BIPS = 10_000;

    constructor(
        address _asset,
        string memory _name,,
        uint256 _maxSingleDeposit,
        address _lpContract,
        address _lpStaker
    ) BaseStrategy(_asset, _name) {
        maxSlippage = _maxSlippage;
        maxSingleDeposit = _maxSingleDeposit;
        lpContract = ISwap(_lpContract);
        lpStaker = IStakingRewards(_lpStaker);
        lpToken = IERC20(lpContract.swapStorage().lpToken);
        require(address(lpContract.getToken(0)) == address(asser), "!asset");
        
        IERC20(_asset).safeApprove(address(lpContract), max);
        IERC20(hop).safeApprove(address(quickSwapRouter), max);
        IERC20(lpToken).safeApprove(address(lpContract), max);
        IERC20(lpToken).safeApprove(address(lpStaker), max);

        maxHopToSell = 20_000 * 1e18;
        maxSlippage = 500;
    }

    /// ----------------- SETTERS -----------------

    function setStrategyParams(
        uint256 _maxSlippage,
        uint256 _maxSingleDepositm
        uint256 _maxHopToSell
    ) external onlyManagement {
        maxSlippage = _maxSlippage;
        maxSingleDepositm = _maxSingleDepositm;
        maxHopToSell = _maxHopToSell;
    }

    function setFees(
        uint24 _rewardToEthFee,
        uint24 _ethToBaseFee,
        uint24 _ethToAssetFee
    ) external onlyManagement {
        _setFees(_rewardToEthFee, _ethToBaseFee, _ethToAssetFee);
    }

    function _setFees(
        uint24 _rewardToEthFee,
        uint24 _ethToBaseFee,
        uint24 _ethToAssetFee
    ) internal {
        address _weth = base;
        _setUniFees(rewardToken, _weth, _rewardToEthFee);
        _setUniFees(baseToken, _weth, _ethToBaseFee);
        _setUniFees(address(asset), _weth, _ethToAssetFee);
    }

    function _deployFunds(uint256 _amount) internal override {
        uint256 _amountToInvest = Math.min(maxSingleDeposit, _amount);
        uint256[] memory _amountsToAdd = new uint256[](2);
        _amountsToAdd[0] = _amount; // @note native token is always index 0
        uint256 _minLpToMint = (_assetToLp(_amount) * (MAX_BIPS - maxSlippage) / MAX_BIPS);
        lpContract.addLiquidity(_amountsToAdd, _minLpToMint, max);
        uint256 _balanceOfUnstakedLPToken = balanceOfUnstakedLPToken();
        if (_balanceOfUnstakedLPToken > 0) {
            _stake(_balanceOfUnstakedLPToken);
        }
    }

    function _freeFunds(uint256 _amount) internal override {
        _removeLiquidity(_assetToLp(_amountNeeded));
    }

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        _claimRewards();

        // sell HOP -> WETH via QuickSwap V3
        uint256 _wethFromHopRewards = _swapHopToWeth(uint256 _amountIn);

        // sell WETH -> asset via Uniswap V3
        _swapFrom(
            weth,
            address(asset),
            _wethFromHopRewards,
            _getAmountOut(_wethFromHopRewards, weth, address(asset))
        );

        _totalAssets = asset.balanceOf(address(this)) + _lpToAsset(_balanceOfStakedLPToken()); //@todo: need to account for LP
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Optional function for strategist to override that can
     *  be called in between reports.
     *
     * If '_tend' is used tendTrigger() will also need to be overridden.
     *
     * This call can only be called by a permissioned role so may be
     * through protected relays.
     *
     * This can be used to harvest and compound rewards, deposit idle funds,
     * perform needed position maintenance or anything else that doesn't need
     * a full report for.
     *
     *   EX: A strategy that can not deposit funds without getting
     *       sandwiched can use the tend when a certain threshold
     *       of idle to totalAssets has been reached.
     *
     * The TokenizedStrategy contract will do all needed debt and idle updates
     * after this has finished and will have no effect on PPS of the strategy
     * till report() is called.
     *
     * @param _totalIdle The current amount of idle funds that are available to deploy.
     *
    function _tend(uint256 _totalIdle) internal override {}
    */

    /**
     * @dev Optional trigger to override if tend() will be used by the strategy.
     * This must be implemented if the strategy hopes to invoke _tend().
     *
     * @return . Should return true if tend() should be called by keeper or false if not.
     *
    function _tendTrigger() internal view override returns (bool) {}
    */





    function _emergencyWithdraw(uint256 _amount) internal override {
        if (_amount > 0) {




            depositor.withdraw(
                Math.min(_amount, depositor.accruedCometBalance())
            );
        }
        // Repay everything we can.
        _repayTokenDebt();

        // Withdraw all that makes sense.
        _withdraw(address(asset), _maxWithdrawal());
    }



    function _assetToLp(uint256 _amount) public view returns (uint256) {
        // @note decimals: _amount (6 or 18), getVirtualPrice (18), return Lp amount (18))
        return (_amount * 10 ** asset.decimals()) / lpContract.getVirtualPrice();
    }

    function _lpToAsset(uint256 _lpAmount) public view returns (uint256) {
        // @note decimals: _lpAmount (18), getVirtualPrice (18), return asset amount (6 or 18)
        return (_lpAmount * lpContract.getVirtualPrice()) / (10 ** asset.decimals());
    }

    function _balanceOfStakedLPToken() public view returns (uint256) {
        return lpStaker.balanceOf(address(this));
    }

    // @todo: check if we want to limit the amount swapped here to prevent sandwitch
    function _swapHopToWeth(uint256 _amountIn) internal returns (uint256 _amountOut) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
                    .ExactInputSingleParams(
                        hop, // tokenIn
                        weth, // tokenOut
                        address(this), // recipient
                        block.timestamp, // deadline
                        _amountIn, // amountIn
                        0, // amountOut
                        0 // sqrtPriceLimitX96
                    );
        _amountOut = ISwapRouter(router).exactInputSingle(params);
    }

}
