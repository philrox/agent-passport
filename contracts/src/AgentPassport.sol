// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IIdentityRegistry} from "./interfaces/IIdentityRegistry.sol";

/// @title AgentPassport — ERC-8004 Identity Registry
/// @author VAIA team
/// @notice Cross-venue agent identity as an ERC-721. Each agent is a token whose `tokenId`
///         is its `agentId` (uint256, auto-incremented from 1; 0 is reserved as the
///         "unregistered" sentinel). `tokenURI(agentId)` points to the off-chain Agent Card
///         JSON (name, capabilities, endpoints). Registration is permissionless; owner-gated
///         mutators evolve URI/metadata, and ERC-721 transfer hands over the identity.
/// @dev Implements {IIdentityRegistry} (ERC-8004 Identity Registry surface) on top of OZ
///      ERC-721 + URIStorage. The agent wallet is set with a signature from the wallet itself
///      (EIP-712 for EOAs, ERC-1271 for smart-contract wallets), matching the canonical
///      erc-8004/erc-8004-contracts implementation. Reputation Registry → R010, Validation
///      Registry → R004. Reference: https://eips.ethereum.org/EIPS/eip-8004
contract AgentPassport is ERC721URIStorage, EIP712, IIdentityRegistry {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev EIP-712 type hash for an agent-wallet authorization. `owner` is injected by the
    ///      contract (= current NFT owner), binding the signature to that owner so a pre-signed
    ///      approval cannot be replayed after the agent NFT changes hands. No nonce: replay is
    ///      bounded by the owner binding plus the short {MAX_WALLET_SIG_DELAY} deadline window.
    bytes32 private constant AGENT_WALLET_SET_TYPEHASH =
        keccak256("AgentWalletSet(uint256 agentId,address newWallet,address owner,uint256 deadline)");

    /// @dev Maximum forward window for a wallet-set signature's deadline (nonce replacement).
    uint256 private constant MAX_WALLET_SIG_DELAY = 5 minutes;

    /// @dev Reserved metadata key under which the agent wallet is stored. Protected from
    ///      generic {setMetadata} writes so the typed accessors stay the single source of truth.
    bytes32 private constant RESERVED_AGENT_WALLET_KEY_HASH = keccak256(bytes("agentWallet"));

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Next agentId to assign. Starts at 1 so that 0 stays an unambiguous
    ///      "unregistered" sentinel for downstream consumers (R003/R004/SDKs).
    uint256 private _nextAgentId = 1;

    /// @dev agentId => keccak256(key) => raw value. Key hashed for storage; the plaintext key
    ///      is preserved in the {MetadataSet} event. The agent wallet lives here too, under
    ///      {RESERVED_AGENT_WALLET_KEY_HASH} as `abi.encodePacked(address)` (20 bytes).
    mapping(uint256 => mapping(bytes32 => bytes)) private _metadata;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a non-owner calls an owner-gated mutator.
    error NotAgentOwner(uint256 agentId, address caller);

    /// @notice Thrown when a wallet-set signature's deadline is in the past.
    error SignatureExpired(uint256 deadline);

    /// @notice Thrown when a wallet-set deadline exceeds the max forward window (replay guard).
    error DeadlineTooFar(uint256 deadline);

    /// @notice Thrown when the wallet-set signature is not valid for `newWallet` (EOA or ERC-1271).
    error InvalidWalletSignature();

    /// @notice Thrown when setMetadata targets a contract-reserved key (e.g. "agentWallet").
    error ReservedMetadataKey();

    constructor() ERC721("Agent Passport", "AGENT") EIP712("ERC8004IdentityRegistry", "1") {}

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
    /// @dev The caller must own `agentId`; `newWallet` must authorize via an EIP-712 signature
    ///      over {AGENT_WALLET_SET_TYPEHASH} (EOA) or ERC-1271 (smart-contract wallet). The
    ///      `deadline` must be in the future and within {MAX_WALLET_SIG_DELAY}. Emits
    ///      {MetadataSet} under the "agentWallet" key for off-chain observability.
    function setAgentWallet(uint256 agentId, address newWallet, uint256 deadline, bytes calldata signature) external {
        address owner = ownerOf(agentId);
        if (owner != msg.sender) revert NotAgentOwner(agentId, msg.sender);
        // slither-disable-next-line timestamp — deadline comparison is intentional, not randomness
        if (block.timestamp > deadline) revert SignatureExpired(deadline);
        // slither-disable-next-line timestamp
        if (deadline > block.timestamp + MAX_WALLET_SIG_DELAY) revert DeadlineTooFar(deadline);

        bytes32 structHash = keccak256(abi.encode(AGENT_WALLET_SET_TYPEHASH, agentId, newWallet, owner, deadline));
        bytes32 digest = _hashTypedDataV4(structHash);
        if (!SignatureChecker.isValidSignatureNow(newWallet, digest, signature)) revert InvalidWalletSignature();

        bytes memory packed = abi.encodePacked(newWallet);
        _metadata[agentId][RESERVED_AGENT_WALLET_KEY_HASH] = packed;
        emit MetadataSet(agentId, "agentWallet", "agentWallet", packed);
    }

    /// @inheritdoc IIdentityRegistry
    function unsetAgentWallet(uint256 agentId) external {
        _requireOwner(agentId);
        delete _metadata[agentId][RESERVED_AGENT_WALLET_KEY_HASH];
        emit MetadataSet(agentId, "agentWallet", "agentWallet", "");
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
        bytes memory packed = _metadata[agentId][RESERVED_AGENT_WALLET_KEY_HASH];
        return packed.length == 20 ? address(bytes20(packed)) : address(0);
    }

    /// @inheritdoc ERC721URIStorage
    function supportsInterface(bytes4 interfaceId) public view override(ERC721URIStorage) returns (bool) {
        return interfaceId == type(IIdentityRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @dev Mint a fresh agent NFT to the caller, set its URI, default the agent wallet to the
    ///      owner, emit {Registered}. (Wallet init is silent; explicit changes emit {MetadataSet}.)
    function _mintAgent(string memory agentURI) private returns (uint256 agentId) {
        agentId = _nextAgentId++;
        _safeMint(msg.sender, agentId);
        _setTokenURI(agentId, agentURI);
        _metadata[agentId][RESERVED_AGENT_WALLET_KEY_HASH] = abi.encodePacked(msg.sender);
        emit Registered(agentId, agentURI, msg.sender);
    }

    /// @dev Persist a metadata entry (key hashed) and emit {MetadataSet}. Rejects the reserved
    ///      agent-wallet key so it can only move through {setAgentWallet}/{unsetAgentWallet}.
    function _writeMetadata(uint256 agentId, string calldata key, bytes calldata value) private {
        bytes32 keyHash = keccak256(bytes(key));
        if (keyHash == RESERVED_AGENT_WALLET_KEY_HASH) revert ReservedMetadataKey();
        _metadata[agentId][keyHash] = value;
        emit MetadataSet(agentId, key, key, value);
    }

    /// @dev Revert unless the caller owns `agentId`. `ownerOf` reverts for unregistered ids.
    function _requireOwner(uint256 agentId) private view {
        if (ownerOf(agentId) != msg.sender) revert NotAgentOwner(agentId, msg.sender);
    }

    /// @dev Clear the verified agent wallet on every transfer so it never persists to a new
    ///      owner (the new owner must re-run {setAgentWallet}). No-op on mint (`from == 0`).
    function _update(address to, uint256 tokenId, address auth) internal override returns (address from) {
        from = super._update(to, tokenId, auth);
        if (from != address(0) && from != to) {
            delete _metadata[tokenId][RESERVED_AGENT_WALLET_KEY_HASH];
        }
    }
}
