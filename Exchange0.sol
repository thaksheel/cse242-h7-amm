// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.2 <=0.8.19;

import "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";

contract Exchange {
    IERC20 public token; // ERC-20 token this exchange pairs with Ether

    mapping(address => uint256) public liquidityPositions;
    uint256 public totalLiquidityPositions;
    uint256 public k; // constant product

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

    constructor(address _tokenAddress) {
        token = IERC20(_tokenAddress);
    }

    // --- Liquidity Functions ---

    function provideLiquidity(
        uint _amountERC20Token
    ) external payable returns (uint) {
        require(_amountERC20Token > 0 && msg.value > 0, "Invalid amounts");

        uint ethBalance = address(this).balance - msg.value;
        uint tokenBalance = token.balanceOf(address(this));

        if (totalLiquidityPositions == 0) {
            // First provider
            liquidityPositions[msg.sender] = 100;
            totalLiquidityPositions = 100;
        } else {
            // Enforce ratio
            require(
                ethBalance * _amountERC20Token == tokenBalance * msg.value,
                "Ratio mismatch"
            );
            uint lp = (totalLiquidityPositions * _amountERC20Token) /
                tokenBalance;
            liquidityPositions[msg.sender] += lp;
            totalLiquidityPositions += lp;
        }

        // Transfer tokens in
        require(
            token.transferFrom(msg.sender, address(this), _amountERC20Token),
            "Token transfer failed"
        );

        // Update k
        k = address(this).balance * token.balanceOf(address(this));

        emit LiquidityProvided(
            _amountERC20Token,
            msg.value,
            liquidityPositions[msg.sender]
        );
        return liquidityPositions[msg.sender];
    }

    function withdrawLiquidity(
        uint _lpToBurn
    ) external returns (uint amountERC20, uint amountEth) {
        require(
            _lpToBurn > 0 && _lpToBurn < liquidityPositions[msg.sender],
            "Invalid LP burn"
        );

        uint ethBalance = address(this).balance;
        uint tokenBalance = token.balanceOf(address(this));

        amountEth = (ethBalance * _lpToBurn) / totalLiquidityPositions;
        amountERC20 = (tokenBalance * _lpToBurn) / totalLiquidityPositions;

        liquidityPositions[msg.sender] -= _lpToBurn;
        totalLiquidityPositions -= _lpToBurn;

        // Transfer out
        payable(msg.sender).transfer(amountEth);
        require(
            token.transfer(msg.sender, amountERC20),
            "Token transfer failed"
        );

        // Update k
        k = address(this).balance * token.balanceOf(address(this));

        emit LiquidityWithdrew(amountERC20, amountEth, _lpToBurn);
    }

    function getMyLiquidityPositions() external view returns (uint) {
        return liquidityPositions[msg.sender];
    }

    // --- Estimation Helpers ---

    function estimateEthToProvide(
        uint _amountERC20Token
    ) external view returns (uint) {
        uint ethBalance = address(this).balance;
        uint tokenBalance = token.balanceOf(address(this));
        return (ethBalance * _amountERC20Token) / tokenBalance;
    }

    function estimateERC20TokenToProvide(
        uint _amountEth
    ) external view returns (uint) {
        uint ethBalance = address(this).balance;
        uint tokenBalance = token.balanceOf(address(this));
        return (tokenBalance * _amountEth) / ethBalance;
    }

    // --- Swap Functions ---

    function swapForEth(uint _amountERC20Token) external returns (uint ethOut) {
        require(_amountERC20Token > 0, "Invalid amount");

        uint ethBalance = address(this).balance;
        uint tokenBalance = token.balanceOf(address(this));

        uint newTokenBalance = tokenBalance + _amountERC20Token;
        uint newEthBalance = k / newTokenBalance;
        ethOut = ethBalance - newEthBalance;

        require(
            token.transferFrom(msg.sender, address(this), _amountERC20Token),
            "Token transfer failed"
        );
        payable(msg.sender).transfer(ethOut);

        k = address(this).balance * token.balanceOf(address(this));
        emit SwapForEth(_amountERC20Token, ethOut);
    }

    function estimateSwapForEth(
        uint _amountERC20Token
    ) external view returns (uint ethOut) {
        uint ethBalance = address(this).balance;
        uint tokenBalance = token.balanceOf(address(this));
        uint newTokenBalance = tokenBalance + _amountERC20Token;
        uint newEthBalance = k / newTokenBalance;
        ethOut = ethBalance - newEthBalance;
    }

    function swapForERC20Token() external payable returns (uint tokenOut) {
        require(msg.value > 0, "Invalid ETH");

        uint ethBalance = address(this).balance - msg.value;
        uint tokenBalance = token.balanceOf(address(this));

        uint newEthBalance = ethBalance + msg.value;
        uint newTokenBalance = k / newEthBalance;
        tokenOut = tokenBalance - newTokenBalance;

        require(token.transfer(msg.sender, tokenOut), "Token transfer failed");

        k = address(this).balance * token.balanceOf(address(this));
        emit SwapForERC20Token(tokenOut, msg.value);
    }

    function estimateSwapForERC20Token(
        uint _amountEth
    ) external view returns (uint tokenOut) {
        uint ethBalance = address(this).balance;
        uint tokenBalance = token.balanceOf(address(this));
        uint newEthBalance = ethBalance + _amountEth;
        uint newTokenBalance = k / newEthBalance;
        tokenOut = tokenBalance - newTokenBalance;
    }
}
