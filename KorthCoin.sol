// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.2 <=0.8.19.0;
import "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";

/// @notice Token with faucet for grading purposes only
contract KorthCoin is ERC20 {
    constructor() ERC20("KorthCoin", "KOR") {
        _mint(msg.sender, 99999 * 1e18);
    }
    /// @notice In case anyone runs out of tokens.
    /// @dev Normally never do this, but it is fine for a class project.
    function mintMe(uint256 amount) external {
        _mint(msg.sender, amount * 1e18);
    }
}
