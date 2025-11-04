// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.2 <=0.8.19;

import "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";

contract Exchange is ERC20 {
    ERC20 public token; // The paired ERC20 token
    uint256 public k; // Constant product (x * y), where x=ETH, y=ERC20

    // Events (as specified)
    event LiquidityProvided(
        uint amountERC20TokenDeposited,
        uint amountEthDeposited,
        uint liquidityPositionsIssued
    );
    event LiquidityWithdrew(
        uint amountERC20TokenWithdrew,
        uint amountEthWithdrew,
        uint liquidityPositionsBurned
    );
    event SwapForEth(uint amountERC20TokenDeposited, uint amountEthWithdrew);
    event SwapForERC20Token(
        uint amountERC20TokenWithdrew,
        uint amountEthDeposited
    );

    constructor(address _tokenAddress) ERC20("LiquidityToken", "LQT") {
        token = ERC20(_tokenAddress);
    }

    // --- Liquidity Functions ---

    // Caller provides ERC20 and ETH at the current pool ratio; receives LP tokens.
    function provideLiquidity(
        uint _amountERC20Token
    ) external payable returns (uint lpIssued) {
        require(_amountERC20Token > 0 && msg.value > 0, "Invalid amounts");

        // Pool balances before this deposit
        uint ethBalanceBefore = address(this).balance - msg.value;
        uint tokenBalanceBefore = token.balanceOf(address(this));

        if (totalSupply() == 0) {
            // First liquidity provider gets 100 LP tokens (scaled to 18 decimals)
            lpIssued = 100 * 1e18;
        } else {
            // Enforce deposit ratio: amountERC20 / tokenBalance == amountETH / ethBalance
            require(
                ethBalanceBefore * _amountERC20Token ==
                    tokenBalanceBefore * msg.value,
                "Ratio mismatch"
            );
            lpIssued = (totalSupply() * _amountERC20Token) / tokenBalanceBefore;
        }

        // Pull ERC20 from user (requires prior approve)
        require(
            token.transferFrom(msg.sender, address(this), _amountERC20Token),
            "Token transfer failed"
        );

        // Mint LP shares
        _mint(msg.sender, lpIssued);

        // Update k = newEthBalance * newTokenBalance
        k = address(this).balance * token.balanceOf(address(this));

        emit LiquidityProvided(_amountERC20Token, msg.value, lpIssued);
        return lpIssued;
    }

    // Caller burns LP tokens to withdraw a pro-rata share of ETH and ERC20
    function withdrawLiquidity(
        uint _lpToBurn
    ) external returns (uint amountERC20, uint amountEth) {
        require(
            _lpToBurn > 0 && _lpToBurn < balanceOf(msg.sender),
            "Invalid LP burn"
        );

        uint totalLP = totalSupply();
        require(totalLP > 0, "Empty pool");

        uint ethBalance = address(this).balance;
        uint tokenBalance = token.balanceOf(address(this));

        amountEth = (ethBalance * _lpToBurn) / totalLP;
        amountERC20 = (tokenBalance * _lpToBurn) / totalLP;

        // Burn LP first (effects), then external transfers (interactions)
        _burn(msg.sender, _lpToBurn);

        // Send ETH
        (bool okEth, ) = payable(msg.sender).call{value: amountEth}("");
        require(okEth, "ETH transfer failed");

        // Send ERC20
        require(
            token.transfer(msg.sender, amountERC20),
            "Token transfer failed"
        );

        // Update k
        k = address(this).balance * token.balanceOf(address(this));

        emit LiquidityWithdrew(amountERC20, amountEth, _lpToBurn);
        return (amountERC20, amountEth);
    }

    // Convenience view for LP balance
    function getMyLiquidityPositions() external view returns (uint) {
        return balanceOf(msg.sender);
    }

    // --- Estimation Helpers ---

    // amountEth = (ethBalance * _amountERC20Token) / tokenBalance
    function estimateEthToProvide(
        uint _amountERC20Token
    ) external view returns (uint) {
        uint ethBalance = address(this).balance;
        uint tokenBalance = token.balanceOf(address(this));
        require(tokenBalance > 0 && ethBalance > 0, "Pool empty");
        return (ethBalance * _amountERC20Token) / tokenBalance;
    }

    // amountERC20 = (tokenBalance * _amountEth) / ethBalance
    function estimateERC20TokenToProvide(
        uint _amountEth
    ) external view returns (uint) {
        uint ethBalance = address(this).balance;
        uint tokenBalance = token.balanceOf(address(this));
        require(tokenBalance > 0 && ethBalance > 0, "Pool empty");
        return (tokenBalance * _amountEth) / ethBalance;
    }

    // --- Swap Functions ---

    // Swap ERC20 for ETH using constant-product pricing.
    // Caller must have approved _amountERC20Token to this contract.
    function swapForEth(uint _amountERC20Token) external returns (uint ethOut) {
        require(_amountERC20Token > 0, "Invalid amount");

        uint ethBalanceBefore = address(this).balance;
        uint tokenBalanceBefore = token.balanceOf(address(this));
        require(ethBalanceBefore > 0 && tokenBalanceBefore > 0, "Pool empty");

        // Compute output using k
        uint newTokenBalance = tokenBalanceBefore + _amountERC20Token;
        uint newEthBalance = k / newTokenBalance;
        require(ethBalanceBefore > newEthBalance, "No ETH output");
        ethOut = ethBalanceBefore - newEthBalance;

        // Pull tokens in
        require(
            token.transferFrom(msg.sender, address(this), _amountERC20Token),
            "Token transfer failed"
        );

        // Send ETH out
        (bool okEth, ) = payable(msg.sender).call{value: ethOut}("");
        require(okEth, "ETH transfer failed");

        // Update k after state changes
        k = address(this).balance * token.balanceOf(address(this));

        emit SwapForEth(_amountERC20Token, ethOut);
        return ethOut;
    }

    // Estimate ETH out for a given ERC20 input (no state change)
    function estimateSwapForEth(
        uint _amountERC20Token
    ) external view returns (uint ethOut) {
        uint ethBalance = address(this).balance;
        uint tokenBalance = token.balanceOf(address(this));
        require(ethBalance > 0 && tokenBalance > 0, "Pool empty");
        uint newTokenBalance = tokenBalance + _amountERC20Token;
        uint newEthBalance = k / newTokenBalance;
        require(ethBalance > newEthBalance, "No ETH output");
        return ethBalance - newEthBalance;
    }

    // Swap ETH for ERC20 using constant-product pricing.
    function swapForERC20Token() external payable returns (uint tokenOut) {
        require(msg.value > 0, "Invalid ETH");

        uint ethBalanceBefore = address(this).balance - msg.value;
        uint tokenBalanceBefore = token.balanceOf(address(this));
        require(ethBalanceBefore > 0 && tokenBalanceBefore > 0, "Pool empty");

        uint newEthBalance = ethBalanceBefore + msg.value;
        uint newTokenBalance = k / newEthBalance;
        require(tokenBalanceBefore > newTokenBalance, "No token output");
        tokenOut = tokenBalanceBefore - newTokenBalance;

        // Send ERC20 to caller
        require(token.transfer(msg.sender, tokenOut), "Token transfer failed");

        // Update k after state changes
        k = address(this).balance * token.balanceOf(address(this));

        emit SwapForERC20Token(tokenOut, msg.value);
        return tokenOut;
    }

    // Estimate ERC20 out for a given ETH input (no state change)
    function estimateSwapForERC20Token(
        uint _amountEth
    ) external view returns (uint tokenOut) {
        uint ethBalance = address(this).balance;
        uint tokenBalance = token.balanceOf(address(this));
        require(ethBalance > 0 && tokenBalance > 0, "Pool empty");
        uint newEthBalance = ethBalance + _amountEth;
        uint newTokenBalance = k / newEthBalance;
        require(tokenBalance > newTokenBalance, "No token output");
        return tokenBalance - newTokenBalance;
    }
}
