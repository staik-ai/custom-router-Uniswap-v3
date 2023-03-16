// SPDX-License-Identifier: UNLICENSED

// work in progress 16.03.23

pragma solidity ^0.8.0;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

// Import your FEE token contract interface
import "./IFeeToken.sol";

contract CustomRouter is Ownable {
    address public FEE_TOKEN;
    address public USDC_TOKEN;
    address public UNISWAP_ROUTER;
    
    ISwapRouter public swapRouter;

    IFeeToken public feeToken;
    IERC20 public usdcToken;

    constructor(address _feeToken, address _usdcToken, address _uniswapRouter) {
        FEE_TOKEN = _feeToken;
        USDC_TOKEN = _usdcToken;
        UNISWAP_ROUTER = _uniswapRouter;
        
        feeToken = IFeeToken(_feeToken);
        usdcToken = IERC20(_usdcToken);
        swapRouter = ISwapRouter(_uniswapRouter);
    }

    function swapFEEToUSDC(uint256 feeAmount, uint24 feeTier, uint256 minUsdcAmount, address recipient, address pool) external {
        uint256 adjustedMinUsdcAmount = minUsdcAmount * (10 ** 12); // Adjust the USDC amount to FEE token decimals

        feeToken.transferFrom(msg.sender, address(this), feeAmount);

        uint256 buyFee = feeToken.getBuyFee();
        uint256 netFeeAmount = feeAmount - (feeAmount * buyFee) / (10**18);

        feeToken.approve(address(swapRouter), netFeeAmount);

        uint256 deadline = block.timestamp + 300;

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams(
            FEE_TOKEN,
            USDC_TOKEN,
            feeTier,
            pool,
            deadline,
            netFeeAmount,
            adjustedMinUsdcAmount,
            0
        );

        swapRouter.exactInputSingle(params);
        IERC20(USDC_TOKEN).transfer(recipient, IERC20(USDC_TOKEN).balanceOf(address(this)));
    }
    

    function swapUSDCtoFEE(uint256 usdcAmount, uint256 minFeeAmount, address recipient, uint24 feeTier, address pool) external {
        uint256 adjustedMinFeeAmount = minFeeAmount / (10 ** 12); // Adjust the FEE amount to USDC decimals
    
        IERC20(USDC_TOKEN).transferFrom(msg.sender, address(this), usdcAmount);
        IERC20(USDC_TOKEN).approve(address(swapRouter), usdcAmount);

        uint256 deadline = block.timestamp + 300;

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams(
            USDC_TOKEN,
            FEE_TOKEN,
            feeTier,
            pool,
            deadline,
            usdcAmount,
            adjustedMinFeeAmount,
            0
        );

        uint256 feeAmount = swapRouter.exactInputSingle(params);
        uint256 sellFee = feeToken.getSellFee();
        uint256 netFeeAmount = feeAmount - (feeAmount * sellFee) / (10**18);
        feeToken.transfer(recipient, netFeeAmount);
    }



    function calculateFee(uint256 amount, uint256 feePercentage) public pure returns (uint256) {
        return amount * feePercentage / 10000; // Assuming the fee percentage is represented as basis points (e.g., 100 for 1%)
    }
}
