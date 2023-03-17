// SPDX-License-Identifier: UNLICENSED



pragma solidity ^0.8.0;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "./v3-periphery/interfaces/INonfungiblePositionManager.sol";


// Import your FEE token contract interface
import "./IFeeToken.sol";

contract CustomRouter is Ownable {
    // contract address of token
    address public FEE_TOKEN;
    // contract address of USDC (Arbitrum)
    address public USDC_TOKEN;
    // contract address of SwapRouter02 (Arbitrum)
    address public UNISWAP_ROUTER;
    
    ISwapRouter public swapRouter;
    IFeeToken public feeToken;
    IERC20 public usdcToken;
    INonfungiblePositionManager public nonfungiblePositionManager;

    constructor(address _feeToken, address _usdcToken, address _uniswapRouter, address _nonfungiblePositionManager) {
        // set addresses
        FEE_TOKEN = _feeToken;
        USDC_TOKEN = _usdcToken;
        UNISWAP_ROUTER = _uniswapRouter;
         nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
            
        feeToken = IFeeToken(_feeToken);
        usdcToken = IERC20(_usdcToken);
        swapRouter = ISwapRouter(_uniswapRouter);
    }

    // sell the token
    function swapFEEToUSDC(uint256 feeAmount, uint24 feeTier, uint256 minUsdcAmount, address recipient, address pool) external {
        feeToken.transferFrom(msg.sender, address(this), feeAmount);

        uint256 sellFee = feeToken.getSellFee();
        uint256 netFeeAmount = feeAmount - (feeAmount * sellFee) / (10**18);

        feeToken.approve(address(swapRouter), netFeeAmount);

        uint256 deadline = block.timestamp + 300;
        uint256 adjustedMinUsdcAmount = minUsdcAmount / (10 ** 12); // Adjust the USDC amount to FEE token decimals

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

    // buy the token

    function swapUSDCtoFEE(uint256 usdcAmount, uint256 minFeeAmount, address recipient, uint24 feeTier, address pool) external {
        IERC20(USDC_TOKEN).transferFrom(msg.sender, address(this), usdcAmount);
        IERC20(USDC_TOKEN).approve(address(swapRouter), usdcAmount);

        uint256 deadline = block.timestamp + 300;
        uint256 adjustedMinFeeAmount = minFeeAmount * (10 ** 12); // Adjust the FEE amount to USDC decimals

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
        uint256 buyFee = feeToken.getBuyFee();
        uint256 netFeeAmount = feeAmount - (feeAmount * buyFee) / (10**18);
        feeToken.transfer(recipient, netFeeAmount);
    }


    function calculateFee(uint256 amount, uint256 feePercentage) public pure returns (uint256) {
        return amount * feePercentage / 10000; // Assuming the fee percentage is represented as basis points (e.g., 100 for 1%)
    }

    // add to the V3 Pool
    function addLiquidity(
        INonfungiblePositionManager.MintParams calldata params,
        uint256 feeAmount,
        uint256 usdcAmount
    ) external {
        // Transfer FEE and USDC tokens from the user to the contract
        feeToken.transferFrom(msg.sender, address(this), feeAmount);
        IERC20(USDC_TOKEN).transferFrom(msg.sender, address(this), usdcAmount);

        // Approve the NonfungiblePositionManager to spend FEE and USDC tokens
        feeToken.approve(address(nonfungiblePositionManager), feeAmount);
        IERC20(USDC_TOKEN).approve(address(nonfungiblePositionManager), usdcAmount);

        // Call the mint function of the NonfungiblePositionManager to add liquidity
        (, , , uint256 tokenId) = nonfungiblePositionManager.mint(params);

        // Transfer the liquidity position NFT to the user
        nonfungiblePositionManager.transferFrom(address(this), msg.sender, tokenId);
    }

    // Remove from the V3 Pool
    function removeLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams calldata params) external {
        // Call the burn function of the NonfungiblePositionManager to remove liquidity
        nonfungiblePositionManager.decreaseLiquidity(params);

        // Collect the tokens from the pool
        INonfungiblePositionManager.CollectParams memory collectParams =
        INonfungiblePositionManager.CollectParams({tokenId: params.tokenId, recipient: address(this), amount0Max: type(uint128).max, amount1Max: type(uint128).max});
        (uint256 collectedFEE, uint256 collectedUSDC) = nonfungiblePositionManager.collect(collectParams);

        // Transfer the collected FEE and USDC tokens to the user
        feeToken.transfer(msg.sender, collectedFEE);
        IERC20(USDC_TOKEN).transfer(msg.sender, collectedUSDC);

        // Burn the liquidity position NFT if the position is empty
        if (collectedFEE == params.liquidity && collectedUSDC == params.liquidity) {
            nonfungiblePositionManager.burn(params.tokenId);
        }
    }


}
