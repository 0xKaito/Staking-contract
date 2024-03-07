// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * This smart contract
 */

contract DefiToken is ERC20, Ownable {


    constructor(uint256 _totalSupply) ERC20("DEFI", "DEFI") Ownable(msg.sender) {
        _mint(msg.sender, _totalSupply);
    }

    function faucetToken(uint256 _amount) external onlyOwner {
        _mint(msg.sender, _amount);
    }
}