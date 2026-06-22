// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {RewardDistributor} from "../src/RewardDistributor.sol";
import {ReflowToken} from "../src/ReflowToken.sol";

contract RewardDistributorTest is Test {
    RewardDistributor dist;
    ReflowToken token;

    address admin = makeAddr("admin");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant ALICE_AMOUNT = 100e18;
    uint256 constant BOB_AMOUNT = 50e18;
    uint256 constant CAMPAIGN = 1;

    function setUp() public {
        vm.startPrank(admin);
        token = new ReflowToken(admin);
        dist = new RewardDistributor(admin, token);
        token.mint(address(dist), 1000e18); // fund the distributor
        vm.stopPrank();
    }

    // --- helpers: build the 2-leaf tree by hand ---

    function _leaf(address account, uint256 amount) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(account, amount))));
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b
            ? keccak256(bytes.concat(a, b))
            : keccak256(bytes.concat(b, a));
    }

    function _buildRoot() internal view returns (bytes32) {
        bytes32 leafA = _leaf(alice, ALICE_AMOUNT);
        bytes32 leafB = _leaf(bob, BOB_AMOUNT);
        return _hashPair(leafA, leafB);
    }

    // --- tests ---

    function test_AliceCanClaim() public {
        bytes32 root = _buildRoot();
        vm.prank(admin);
        dist.setMerkleRoot(CAMPAIGN, root);

        // Alice's proof = her one sibling, leafB
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = _leaf(bob, BOB_AMOUNT);

        dist.claim(CAMPAIGN, alice, ALICE_AMOUNT, proof);

        assertEq(token.balanceOf(alice), ALICE_AMOUNT);
        assertTrue(dist.claimed(CAMPAIGN, alice));
    }

    function test_SecondClaimReverts() public {
        bytes32 root = _buildRoot();
        vm.prank(admin);
        dist.setMerkleRoot(CAMPAIGN, root);

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = _leaf(bob, BOB_AMOUNT);

        dist.claim(CAMPAIGN, alice, ALICE_AMOUNT, proof);

        // replay the identical call
        vm.expectRevert(RewardDistributor.AlreadyClaimed.selector);
        dist.claim(CAMPAIGN, alice, ALICE_AMOUNT, proof);
    }

    function test_WrongAmountReverts() public {
        bytes32 root = _buildRoot();
        vm.prank(admin);
        dist.setMerkleRoot(CAMPAIGN, root);

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = _leaf(bob, BOB_AMOUNT);

        // Alice claims 999 instead of her real 100 — leaf won't match
        vm.expectRevert(RewardDistributor.InvalidProof.selector);
        dist.claim(CAMPAIGN, alice, 999e18, proof);
    }

    function test_NonOperatorCannotSetRoot() public {
        bytes32 root = _buildRoot();
        vm.prank(alice); // alice has no role
        vm.expectRevert();
        dist.setMerkleRoot(CAMPAIGN, root);
    }
}