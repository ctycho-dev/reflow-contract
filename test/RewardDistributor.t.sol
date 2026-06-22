// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RewardDistributor} from "../src/RewardDistributor.sol";
import {ReflowToken} from "../src/ReflowToken.sol";
import {Merkle} from "murky/Merkle.sol";

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

    function test_Murky_EightLeaves() public {
        Merkle m = new Merkle();

        // 8 winners
        address[8] memory accounts = [
            alice, bob, makeAddr("c"), makeAddr("d"),
            makeAddr("e"), makeAddr("f"), makeAddr("g"), makeAddr("h")
        ];
        uint256[8] memory amounts = [
            uint256(100e18), 50e18, 75e18, 30e18, 90e18, 60e18, 40e18, 20e18
        ];

        // build leaf array using OUR leaf formula
        bytes32[] memory leaves = new bytes32[](8);
        for (uint256 i = 0; i < 8; i++) {
            leaves[i] = _leaf(accounts[i], amounts[i]);
        }

        bytes32 root = m.getRoot(leaves);
        vm.prank(admin);
        dist.setMerkleRoot(CAMPAIGN, root);

        // claim for leaf index 4 (account "e", 90 tokens)
        uint256 idx = 4;
        bytes32[] memory proof = m.getProof(leaves, idx);
        dist.claim(CAMPAIGN, accounts[idx], amounts[idx], proof);

        assertEq(token.balanceOf(accounts[idx]), amounts[idx]);
        assertTrue(dist.claimed(CAMPAIGN, accounts[idx]));
    }

    function testFuzz_AnyLeafCanClaim(uint8 idxRaw) public {
        Merkle m = new Merkle();

        address[8] memory accounts = [
            alice, bob, makeAddr("c"), makeAddr("d"),
            makeAddr("e"), makeAddr("f"), makeAddr("g"), makeAddr("h")
        ];
        uint256[8] memory amounts = [
            uint256(100e18), 50e18, 75e18, 30e18, 90e18, 60e18, 40e18, 20e18
        ];

        bytes32[] memory leaves = new bytes32[](8);
        for (uint256 i = 0; i < 8; i++) {
            leaves[i] = _leaf(accounts[i], amounts[i]);
        }

        bytes32 root = m.getRoot(leaves);
        vm.prank(admin);
        dist.setMerkleRoot(CAMPAIGN, root);

        uint256 idx = idxRaw % 8; // map random byte into 0..7

        bytes32[] memory proof = m.getProof(leaves, idx);
        dist.claim(CAMPAIGN, accounts[idx], amounts[idx], proof);

        assertEq(token.balanceOf(accounts[idx]), amounts[idx]);
        assertTrue(dist.claimed(CAMPAIGN, accounts[idx]));
    }

    function test_ReentrancyBlocked() public {
        ReentrantToken evil = new ReentrantToken();
        RewardDistributor evilDist = new RewardDistributor(admin, IERC20(address(evil)));

        // 2-leaf tree with this distributor
        bytes32 leafA = _leaf(alice, ALICE_AMOUNT);
        bytes32 leafB = _leaf(bob, BOB_AMOUNT);
        bytes32 root = _hashPair(leafA, leafB);

        vm.prank(admin);
        evilDist.setMerkleRoot(CAMPAIGN, root);

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leafB;

        // arm the malicious token to re-enter on transfer
        evil.arm(evilDist, CAMPAIGN, alice, ALICE_AMOUNT, proof);

        // the re-entrant claim inside transfer must revert AlreadyClaimed,
        // which bubbles up and reverts the whole thing
        vm.expectRevert(RewardDistributor.AlreadyClaimed.selector);
        evilDist.claim(CAMPAIGN, alice, ALICE_AMOUNT, proof);
    }
}


contract ReentrantToken {
    RewardDistributor public dist;
    uint256 public campaign;
    address public victim;
    uint256 public amount;
    bytes32[] public proof;
    bool public attacked;

    mapping(address => uint256) public balanceOf;

    function arm(
        RewardDistributor _dist,
        uint256 _campaign,
        address _victim,
        uint256 _amount,
        bytes32[] memory _proof
    ) external {
        dist = _dist;
        campaign = _campaign;
        victim = _victim;
        amount = _amount;
        proof = _proof;
    }

    // the distributor calls this during claim; we re-enter
    function transfer(address to, uint256 value) external returns (bool) {
        balanceOf[to] += value;
        if (!attacked) {
            attacked = true;
            // try to claim again mid-transfer
            dist.claim(campaign, victim, amount, proof);
        }
        return true;
    }
}