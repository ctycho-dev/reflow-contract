// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RewardDistributor is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    IERC20 public immutable TOKEN;

    mapping(uint256 campaignId => bytes32 root) public merkleRoots;
    mapping(uint256 campaignId => mapping(address account => bool)) public claimed;

    event MerkleRootSet(uint256 indexed campaignId, bytes32 root);
    event Claimed(uint256 indexed campaignId, address indexed account, uint256 amount);

    error RootAlreadySet();
    error RootNotSet();
    error AlreadyClaimed();
    error InvalidProof();

    constructor(address admin, IERC20 _token) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
        TOKEN = _token;
    }

    function setMerkleRoot(uint256 campaignId, bytes32 root) external onlyRole(OPERATOR_ROLE) {
        if (merkleRoots[campaignId] != bytes32(0)) revert RootAlreadySet();
        merkleRoots[campaignId] = root;
        emit MerkleRootSet(campaignId, root);
    }

    function claim(uint256 campaignId, address account, uint256 amount, bytes32[] calldata proof) external {
        bytes32 root = merkleRoots[campaignId];
        if (root == bytes32(0)) revert RootNotSet();
        if (claimed[campaignId][account]) revert AlreadyClaimed();

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(account, amount))));
        if (!MerkleProof.verify(proof, root, leaf)) revert InvalidProof();

        claimed[campaignId][account] = true;
        emit Claimed(campaignId, account, amount);

        TOKEN.safeTransfer(account, amount);
    }
}