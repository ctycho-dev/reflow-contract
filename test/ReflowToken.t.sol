// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ReflowToken} from "../src/ReflowToken.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract ReflowTokenTest is Test {
    ReflowToken token;
    address admin = makeAddr("admin");
    address alice = makeAddr("alice");

    function setUp() public {
        vm.prank(admin);
        token = new ReflowToken(admin);
    }

    function test_AdminCanMint() public {
        vm.prank(admin);
        token.mint(alice, 1000e18);
        assertEq(token.balanceOf(alice), 1000e18);
        assertEq(token.totalSupply(), 1000e18);
    }

    function test_NonMinterCannotMint() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                token.MINTER_ROLE()
            )
        );
        vm.prank(alice);
        token.mint(alice, 1000e18);
    }

    function testFuzz_MintArbitraryAmount(uint256 amount) public {
        vm.prank(admin);
        token.mint(alice, amount);
        assertEq(token.balanceOf(alice), amount);
    }
}