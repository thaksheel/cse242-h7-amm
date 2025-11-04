// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19; 

contract CPAMM{
    IERC20 public immutable token0; 
    IERC20 public immutable token1; 

    uint256 public reserve0; 
    uint256 public reserve1; 

    uint256 public totalSupply; 
    mapping (address => uint256) public balanceOf; 

    constructor (address _token0, address _token1) {
        token0 = IERC20(_token0); 
        token1 = IERC20(_token1); 
    }

    function _mint(address _to, uint256 _amount) private {
        balanceOf[_to] += _amount; 
        totalSupply += _amount; 

    }

    function _burn (address _from, uint256 _amount) private { 
        balanceOf[_from] -= _amount; 
        totalSupply -= _amount; 

    }

    function swap(address _tokenIn, uint256 _amountIn) external returns (uni256 amountOut) {

    }
}