// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Decentralized Exchange (DEX) - Simplified
 * @dev A simplified DEX implementing automated market maker (AMM) functionality
 * @author DEX Development Team
 */

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract Project {
    
    // Events for transparency and tracking
    event LiquidityAdded(address indexed provider, uint256 tokenAmount, uint256 ethAmount, uint256 liquidity);
    event LiquidityRemoved(address indexed provider, uint256 tokenAmount, uint256 ethAmount, uint256 liquidity);
    event TokenSwapped(address indexed user, uint256 ethIn, uint256 tokenOut);
    event EthSwapped(address indexed user, uint256 tokenIn, uint256 ethOut);

    // State variables
    IERC20 public token;
    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidity;
    
    // Fee configuration (0.3% = 3/1000)
    uint256 public constant FEE_RATE = 3;
    uint256 public constant FEE_DENOMINATOR = 1000;
    
    // Minimum liquidity to prevent division by zero
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    /**
     * @dev Constructor sets the token address for the trading pair
     * @param _token Address of the ERC20 token to trade against ETH
     */
    constructor(address _token) {
        require(_token != address(0), "Invalid token address");
        token = IERC20(_token);
    }

    /**
     * @dev Get current reserves of the pool
     * @return ethReserve Current ETH balance
     * @return tokenReserve Current token balance
     */
    function getReserves() public view returns (uint256 ethReserve, uint256 tokenReserve) {
        return (address(this).balance, token.balanceOf(address(this)));
    }

    /**
     * @dev Calculate price based on current reserves
     * @param inputAmount Amount of input token
     * @param inputReserve Reserve of input token
     * @param outputReserve Reserve of output token
     * @return outputAmount Amount of output token
     */
    function getPrice(uint256 inputAmount, uint256 inputReserve, uint256 outputReserve) 
        public 
        pure 
        returns (uint256 outputAmount) 
    {
        require(inputReserve > 0 && outputReserve > 0, "Invalid reserves");
        
        // Apply fee (inputAmount * (1000 - 3) / 1000)
        uint256 inputAmountWithFee = inputAmount * (FEE_DENOMINATOR - FEE_RATE);
        uint256 numerator = inputAmountWithFee * outputReserve;
        uint256 denominator = (inputReserve * FEE_DENOMINATOR) + inputAmountWithFee;
        
        return numerator / denominator;
    }

    /**
     * @dev CORE FUNCTION 1: Add liquidity to the pool
     * @param tokenAmount Amount of tokens to add
     * @return liquidityMinted Amount of liquidity tokens minted
     */
    function addLiquidity(uint256 tokenAmount) 
        external 
        payable 
        returns (uint256 liquidityMinted) 
    {
        require(msg.value > 0 && tokenAmount > 0, "Invalid amounts");
        
        (uint256 ethReserve, uint256 tokenReserve) = getReserves();
        
        // Transfer tokens from user
        require(token.transferFrom(msg.sender, address(this), tokenAmount), "Token transfer failed");
        
        if (totalLiquidity == 0) {
            // First liquidity provision
            liquidityMinted = msg.value;
            require(liquidityMinted > MINIMUM_LIQUIDITY, "Insufficient liquidity");
        } else {
            // Calculate proportional liquidity
            uint256 ethLiquidity = (msg.value * totalLiquidity) / ethReserve;
            uint256 tokenLiquidity = (tokenAmount * totalLiquidity) / tokenReserve;
            liquidityMinted = ethLiquidity < tokenLiquidity ? ethLiquidity : tokenLiquidity;
        }
        
        require(liquidityMinted > 0, "Insufficient liquidity minted");
        
        liquidity[msg.sender] += liquidityMinted;
        totalLiquidity += liquidityMinted;
        
        emit LiquidityAdded(msg.sender, tokenAmount, msg.value, liquidityMinted);
        return liquidityMinted;
    }

    /**
     * @dev CORE FUNCTION 2: Remove liquidity from the pool
     * @param liquidityAmount Amount of liquidity tokens to burn
     * @return ethAmount Amount of ETH returned
     * @return tokenAmount Amount of tokens returned
     */
    function removeLiquidity(uint256 liquidityAmount) 
        external 
        returns (uint256 ethAmount, uint256 tokenAmount) 
    {
        require(liquidityAmount > 0, "Invalid liquidity amount");
        require(liquidity[msg.sender] >= liquidityAmount, "Insufficient liquidity");
        
        (uint256 ethReserve, uint256 tokenReserve) = getReserves();
        
        ethAmount = (liquidityAmount * ethReserve) / totalLiquidity;
        tokenAmount = (liquidityAmount * tokenReserve) / totalLiquidity;
        
        require(ethAmount > 0 && tokenAmount > 0, "Insufficient output amounts");
        
        liquidity[msg.sender] -= liquidityAmount;
        totalLiquidity -= liquidityAmount;
        
        // Transfer tokens and ETH back to user
        require(token.transfer(msg.sender, tokenAmount), "Token transfer failed");
        payable(msg.sender).transfer(ethAmount);
        
        emit LiquidityRemoved(msg.sender, tokenAmount, ethAmount, liquidityAmount);
        return (ethAmount, tokenAmount);
    }

    /**
     * @dev CORE FUNCTION 3: Swap ETH for tokens
     * @param minTokens Minimum tokens expected (slippage protection)
     * @return tokenAmount Amount of tokens received
     */
    function swapETHForTokens(uint256 minTokens) 
        external 
        payable 
        returns (uint256 tokenAmount) 
    {
        require(msg.value > 0, "Invalid ETH amount");
        
        (uint256 ethReserve, uint256 tokenReserve) = getReserves();
        
        // Calculate tokens to receive (subtract current transaction ETH)
        tokenAmount = getPrice(msg.value, ethReserve - msg.value, tokenReserve);
        require(tokenAmount >= minTokens, "Insufficient output amount");
        require(tokenAmount <= tokenReserve, "Insufficient token liquidity");
        
        // Transfer tokens to user
        require(token.transfer(msg.sender, tokenAmount), "Token transfer failed");
        
        emit TokenSwapped(msg.sender, msg.value, tokenAmount);
        return tokenAmount;
    }

    /**
     * @dev Swap tokens for ETH
     * @param tokenAmount Amount of tokens to swap
     * @param minETH Minimum ETH expected (slippage protection)
     * @return ethAmount Amount of ETH received
     */
    function swapTokensForETH(uint256 tokenAmount, uint256 minETH) 
        external 
        returns (uint256 ethAmount) 
    {
        require(tokenAmount > 0, "Invalid token amount");
        
        (uint256 ethReserve, uint256 tokenReserve) = getReserves();
        
        // Transfer tokens from user first
        require(token.transferFrom(msg.sender, address(this), tokenAmount), "Token transfer failed");
        
        // Calculate ETH to receive
        ethAmount = getPrice(tokenAmount, tokenReserve + tokenAmount, ethReserve);
        require(ethAmount >= minETH, "Insufficient output amount");
        require(ethAmount <= ethReserve, "Insufficient ETH liquidity");
        
        // Transfer ETH to user
        payable(msg.sender).transfer(ethAmount);
        
        emit EthSwapped(msg.sender, tokenAmount, ethAmount);
        return ethAmount;
    }

    // View functions for frontend integration

    /**
     * @dev Get quote for ETH to token swap
     * @param ethAmount Amount of ETH to swap
     * @return tokenAmount Expected token amount
     */
    function getETHToTokenPrice(uint256 ethAmount) external view returns (uint256 tokenAmount) {
        require(ethAmount > 0, "Invalid ETH amount");
        (uint256 ethReserve, uint256 tokenReserve) = getReserves();
        return getPrice(ethAmount, ethReserve, tokenReserve);
    }

    /**
     * @dev Get quote for token to ETH swap
     * @param tokenAmount Amount of tokens to swap
     * @return ethAmount Expected ETH amount
     */
    function getTokenToETHPrice(uint256 tokenAmount) external view returns (uint256 ethAmount) {
        require(tokenAmount > 0, "Invalid token amount");
        (uint256 ethReserve, uint256 tokenReserve) = getReserves();
        return getPrice(tokenAmount, tokenReserve, ethReserve);
    }

    /**
     * @dev Get user's liquidity balance
     * @param user Address to check
     * @return liquidityBalance User's liquidity tokens
     */
    function getUserLiquidity(address user) external view returns (uint256 liquidityBalance) {
        return liquidity[user];
    }

    /**
     * @dev Get pool information
     * @return ethBalance Current ETH in pool
     * @return tokenBalance Current tokens in pool
     * @return totalLiq Total liquidity tokens
     */
    function getPoolInfo() external view returns (uint256 ethBalance, uint256 tokenBalance, uint256 totalLiq) {
        (uint256 ethReserve, uint256 tokenReserve) = getReserves();
        return (ethReserve, tokenReserve, totalLiquidity);
    }

    /**
     * @dev Calculate share of pool owned by user
     * @param user Address to check
     * @return sharePercentage Percentage of pool owned (multiplied by 10000 for precision)
     */
    function getUserPoolShare(address user) external view returns (uint256 sharePercentage) {
        if (totalLiquidity == 0) return 0;
        return (liquidity[user] * 10000) / totalLiquidity;
    }

    /**
     * @dev Emergency function to withdraw stuck tokens (only for tokens not in trading pair)
     * @param tokenAddress Address of token to withdraw
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address tokenAddress, uint256 amount) external {
        require(tokenAddress != address(token), "Cannot withdraw trading pair token");
        IERC20(tokenAddress).transfer(msg.sender, amount);
    }
}
