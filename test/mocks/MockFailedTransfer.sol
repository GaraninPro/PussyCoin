// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockFailedTransfer is ERC20Burnable, Ownable {
    error StableCoin_MustbeMoreThanZero();
    error StableCoin_BurnAmountMoreThanBalance();
    error StableCoin_NotZeroAddress();

    constructor() ERC20("PadreStableCoin", "PS") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (_amount <= 0) {
            revert StableCoin_MustbeMoreThanZero();
        }

        if (balance < _amount) {
            revert StableCoin_BurnAmountMoreThanBalance();
        }

        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert StableCoin_NotZeroAddress();
        }

        if (_amount <= 0) {
            revert StableCoin_MustbeMoreThanZero();
        }

        _mint(_to, _amount);
        return true;
    }

    function transfer(address, /*to*/ uint256 /*amount*/ ) public pure override returns (bool) {
        return false;
    }
}
