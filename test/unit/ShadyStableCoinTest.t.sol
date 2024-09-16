//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeploySsc} from "../../script/DeploySsc.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ShadyStableCoin} from "../../src/ShadyStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";

contract ShadyStableCoinTest is Test {
    ShadyStableCoin public ssc;
    DeploySsc public deployer;

    uint256 public constant MINT_AMOUNT = 10000;

    address public mike = address(this);
    address public kuu = makeAddr("KUU");
    address public tim = makeAddr("TIM");

    function setUp() external {
        ssc = new ShadyStableCoin();
    }

    // CONSTRUCTOR TESTS
    function testConstructor() public view {
        assertEq(ssc.name(), "ShadyStableCoin");
        assertEq(ssc.symbol(), "SSC");
        assertEq(ssc.owner(), mike);
    }

    // MINT TESTS
    function testMintAsOwner() public {
        vm.startPrank(mike);
        ssc.mint(mike, MINT_AMOUNT);
        vm.stopPrank();
        assertEq(ssc.balanceOf(mike), MINT_AMOUNT);
    }

    function testMintFailsForNonOwner() public {
        vm.startPrank(kuu);
        vm.expectRevert();
        ssc.mint(kuu, MINT_AMOUNT);
        vm.stopPrank();
    }

    function testMintFailsForZeroAddress() public {
        vm.expectRevert(ShadyStableCoin.ShadyStableCoin__NotZeroAddress.selector);
        ssc.mint(address(0), MINT_AMOUNT);
    }

    function testMintFailsForZeroAmount() public {
        vm.expectRevert(ShadyStableCoin.ShadyStableCoin__MustBeMoreThanZero.selector);
        ssc.mint(mike, 0);
    }

    // BURN TESTS
    function testBurnAsOwner() public {
        vm.startPrank(mike);
        ssc.mint(mike, MINT_AMOUNT);
        ssc.burn(MINT_AMOUNT);
        vm.stopPrank();
        assertEq(ssc.balanceOf(mike), 0);
    }

    function testBurnFailsForNonOwner() public {
        vm.prank(mike);
        ssc.mint(kuu, MINT_AMOUNT);

        vm.expectRevert();
        vm.prank(kuu);
        ssc.burn(MINT_AMOUNT);
    }

    function testBurnFailsForZeroAmount() public {
        vm.expectRevert(ShadyStableCoin.ShadyStableCoin__MustBeMoreThanZero.selector);
        ssc.burn(0);
    }

    function testBurnFailsForInsufficientBalance() public {
        vm.startPrank(mike);
        ssc.mint(tim, 500);
        vm.expectRevert(ShadyStableCoin.ShadyStableCoin__BurnAmountExceedsBalance.selector);
        ssc.burn(1000);
    }

    // ADDITIONAL TESTS
    function testMintMaxUint256() public {
        vm.prank(mike);
        ssc.mint(kuu, type(uint256).max);
        assertEq(ssc.balanceOf(kuu), type(uint256).max);
    }

    function testBurnEntireBalance() public {
        vm.startPrank(mike);
        ssc.mint(mike, MINT_AMOUNT);
        ssc.burn(MINT_AMOUNT);
        vm.stopPrank();
        assertEq(ssc.balanceOf(mike), 0);
    }

    function testMultipleMintAndBurn() public {
        vm.startPrank(mike);
        ssc.mint(mike, MINT_AMOUNT);
        ssc.mint(mike, MINT_AMOUNT);
        assertEq(ssc.balanceOf(mike), 20000);

        ssc.burn(7000);
        assertEq(ssc.balanceOf(mike), 13000);

        ssc.mint(tim, MINT_AMOUNT);
        assertEq(ssc.balanceOf(tim), MINT_AMOUNT);
        vm.stopPrank();
    }

}