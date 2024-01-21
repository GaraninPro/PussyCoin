//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StableCoin} from "../../src/StableCoin.sol";

contract StableCoinTest is Test {
    StableCoin psCoin;

    function setUp() public {
        psCoin = new StableCoin();
    }

    function testMustRevertIfMintZero() public {
        vm.prank(psCoin.owner());
        vm.expectRevert();
        psCoin.mint(address(this), 0);
    }

    function testMustRevertIfBurnZero() public {
        vm.startPrank(psCoin.owner());
        psCoin.mint(address(this), 100);
        vm.expectRevert();
        psCoin.burn(0);
        vm.stopPrank();
    }

    function testCanNotBurnMoreThanYouHave() public {
        vm.startPrank(psCoin.owner());
        psCoin.mint(address(this), 100);
        vm.expectRevert();
        psCoin.burn(108);
        vm.stopPrank();
    }

    function testCanNotMintToZeroAddress() public {
        vm.prank(psCoin.owner());
        vm.expectRevert();
        psCoin.mint(address(0), 1780);
    }
}
