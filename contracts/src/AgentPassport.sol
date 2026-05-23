// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {IIdentityRegistry} from "./interfaces/IIdentityRegistry.sol";

/// @title AgentPassport — ERC-8004 Identity Registry
/// @author VAIA team
/// @notice Cross-venue agent identity as an ERC-721. Each agent is a token whose `tokenId`
///         is its `agentId` (uint256, auto-incremented from 1; 0 is reserved as the
///         "unregistered" sentinel). `tokenURI(agentId)` points to the off-chain Agent Card
///         JSON (name, capabilities, endpoints, payment address). Registration is
///         permissionless; owner-gated mutators let the holder evolve URI/metadata, and
///         ERC-721 transfer hands over the identity (custodian change).
/// @dev Implements {IIdentityRegistry} (ERC-8004 Identity Registry surface) on top of OZ
///      ERC-721 + URIStorage. Reputation Registry → R010, Validation Registry → R004.
///      Reference: https://eips.ethereum.org/EIPS/eip-8004
contract AgentPassport is ERC721URIStorage, IIdentityRegistry {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Next agentId to assign. Starts at 1 so that 0 stays an unambiguous
    ///      "unregistered" sentinel for downstream consumers (R003/R004/SDKs).
    uint256 private _nextAgentId = 1;

    /// @dev agentId => keccak256(key) => raw value. Key hashed for storage; the plaintext
    ///      key is preserved in the {MetadataSet} event for off-chain reconstruction.
    mapping(uint256 => mapping(bytes32 => bytes)) private _metadata;

    /// @dev agentId => agent wallet (payment/operator address, distinct from the NFT owner).
    mapping(uint256 => address) private _agentWallet;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a non-owner calls an owner-gated mutator.
    error NotAgentOwner(uint256 agentId, address caller);

    constructor() ERC721("Agent Passport", "AGENT") {}

    /*//////////////////////////////////////////////////////////////
                              REGISTRATION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IIdentityRegistry
    function register(string calldata agentURI, MetadataEntry[] calldata metadata) external returns (uint256 agentId) {
        agentId = _mintAgent(agentURI);
        for (uint256 i; i < metadata.length; ++i) {
            _writeMetadata(agentId, metadata[i].key, metadata[i].value);
        }
    }

    /// @inheritdoc IIdentityRegistry
    function register(string calldata agentURI) external returns (uint256 agentId) {
        return _mintAgent(agentURI);
    }

    /// @inheritdoc IIdentityRegistry
    function register() external returns (uint256 agentId) {
        return _mintAgent("");
    }

    /*//////////////////////////////////////////////////////////////
                            OWNER-GATED MUTATORS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IIdentityRegistry
    function setAgentURI(uint256 agentId, string calldata newURI) external {
        _requireOwner(agentId);
        _setTokenURI(agentId, newURI);
        emit URIUpdated(agentId, newURI, msg.sender);
    }

    /// @inheritdoc IIdentityRegistry
    function setMetadata(uint256 agentId, string calldata key, bytes calldata value) external {
        _requireOwner(agentId);
        _writeMetadata(agentId, key, value);
    }

    /// @inheritdoc IIdentityRegistry
    /// @dev R002 deviation: owner-gated only. `deadline` and `signature` are accepted for
    ///      ABI compatibility with the EIP-8004 signature-delegation path but are NOT verified
    ///      here — that path (a new wallet proving control via EIP-712) is a documented
    ///      follow-up. See SPEC-R002 "Out of Scope / Deviations".
    function setAgentWallet(uint256 agentId, address newWallet, uint256, bytes calldata) external {
        _requireOwner(agentId);
        _agentWallet[agentId] = newWallet;
    }

    /// @inheritdoc IIdentityRegistry
    function unsetAgentWallet(uint256 agentId) external {
        _requireOwner(agentId);
        delete _agentWallet[agentId];
    }

    /*//////////////////////////////////////////////////////////////
                                 READS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IIdentityRegistry
    function getMetadata(uint256 agentId, string calldata key) external view returns (bytes memory) {
        return _metadata[agentId][keccak256(bytes(key))];
    }

    /// @inheritdoc IIdentityRegistry
    function getAgentWallet(uint256 agentId) external view returns (address) {
        return _agentWallet[agentId];
    }

    /// @inheritdoc ERC721URIStorage
    function supportsInterface(bytes4 interfaceId) public view override(ERC721URIStorage) returns (bool) {
        return interfaceId == type(IIdentityRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @dev Mint a fresh agent NFT to the caller, set its URI, emit {Registered}.
    function _mintAgent(string memory agentURI) private returns (uint256 agentId) {
        agentId = _nextAgentId++;
        _safeMint(msg.sender, agentId);
        _setTokenURI(agentId, agentURI);
        emit Registered(agentId, agentURI, msg.sender);
    }

    /// @dev Persist a metadata entry (key hashed) and emit {MetadataSet} with the plaintext key.
    function _writeMetadata(uint256 agentId, string calldata key, bytes calldata value) private {
        _metadata[agentId][keccak256(bytes(key))] = value;
        emit MetadataSet(agentId, key, key, value);
    }

    /// @dev Revert unless the caller owns `agentId`. `ownerOf` reverts for unregistered ids.
    function _requireOwner(uint256 agentId) private view {
        address owner = ownerOf(agentId);
        if (owner != msg.sender) revert NotAgentOwner(agentId, msg.sender);
    }
}
