// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IIdentityRegistry} from "./interfaces/IIdentityRegistry.sol";

/// @title AgentPassport — ERC-8004 Identity Registry
/// @author VAIA team
/// @notice Cross-venue agent identity as an ERC-721. Each agent is a token whose `tokenId`
///         is its `agentId` (uint256, auto-incremented from 1; 0 is reserved as the
///         "unregistered" sentinel). `tokenURI(agentId)` points to the off-chain Agent Card
///         JSON (name, capabilities, endpoints). Registration is permissionless; owner-gated
///         mutators evolve URI/metadata, ERC-721 transfer hands over the identity, and the owner
///         can retire it via {burn} (ERC721Burnable). On transfer/burn all metadata (capabilities,
///         venue claims, agent wallet) is reset — only the `tokenURI` (the identity pointer)
///         survives; a new owner starts from a clean slate. See {_update}.
/// @dev Implements {IIdentityRegistry} (ERC-8004 Identity Registry surface) on top of OZ
///      ERC-721 + URIStorage + Burnable. The agent wallet is set with a signature from the wallet
///      itself (EIP-712 for EOAs, ERC-1271 for smart-contract wallets), matching the canonical
///      erc-8004/erc-8004-contracts implementation. Reputation Registry → R010, Validation
///      Registry → R004. Reference: https://eips.ethereum.org/EIPS/eip-8004
///
///      Retire/recovery: {burn} retires an identity (ids never recycle; recover by burning and
///      registering a fresh id, then re-pointing off-chain references). This does NOT defend
///      against a compromised owner key — whoever holds the key controls (and can burn) the
///      identity; key-rotation is out of scope, consistent with NFT-based identity in general.
contract AgentPassport is ERC721, ERC721URIStorage, ERC721Burnable, EIP712, IIdentityRegistry {
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

    /// @dev agentId => storage-slot => raw value. The slot is {_metadataSlot} =
    ///      keccak256(epoch, keccak256(key)) — i.e. the metadata is namespaced by the agent's
    ///      current {_metadataEpoch}, so a single epoch bump on transfer/burn orphans EVERY key
    ///      (generic metadata + the reserved agent wallet) in O(1) without an unbounded delete
    ///      loop. The plaintext key is preserved in the {MetadataSet} event. The agent wallet
    ///      lives here under {RESERVED_AGENT_WALLET_KEY_HASH} as `abi.encodePacked(address)`.
    mapping(uint256 => mapping(bytes32 => bytes)) private _metadata;

    /// @dev agentId => current metadata epoch. Incremented on every ownership change (transfer)
    ///      and on burn, which re-namespaces all of an agent's metadata and thereby resets it to
    ///      empty for the new owner. A new owner never inherits the previous owner's metadata
    ///      (capability/venue claims, agent wallet). Old values are not zeroed (no gas refund);
    ///      they simply become unreachable. Starts at 0; reads/writes use the live epoch.
    mapping(uint256 => uint256) private _metadataEpoch;

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
        agentId = _prepareAgent(agentURI);
        for (uint256 i; i < metadata.length; ++i) {
            _writeMetadata(agentId, metadata[i].key, metadata[i].value);
        }
        _safeMint(msg.sender, agentId);
    }

    /// @inheritdoc IIdentityRegistry
    function register(string calldata agentURI) external returns (uint256 agentId) {
        agentId = _prepareAgent(agentURI);
        _safeMint(msg.sender, agentId);
    }

    /// @inheritdoc IIdentityRegistry
    function register() external returns (uint256 agentId) {
        agentId = _prepareAgent("");
        _safeMint(msg.sender, agentId);
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
        // Deadline comparison is intentional (a ~5-min signature window); sub-second validator
        // timestamp drift is immaterial. Suppress both linters' timestamp heuristics.
        // slither-disable-next-line timestamp
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > deadline) revert SignatureExpired(deadline);
        // slither-disable-next-line timestamp
        // forge-lint: disable-next-line(block-timestamp)
        if (deadline > block.timestamp + MAX_WALLET_SIG_DELAY) revert DeadlineTooFar(deadline);

        bytes32 structHash = keccak256(abi.encode(AGENT_WALLET_SET_TYPEHASH, agentId, newWallet, owner, deadline));
        bytes32 digest = _hashTypedDataV4(structHash);
        if (!SignatureChecker.isValidSignatureNow(newWallet, digest, signature)) revert InvalidWalletSignature();

        _storeAndEmitWallet(agentId, newWallet);
    }

    /// @inheritdoc IIdentityRegistry
    function unsetAgentWallet(uint256 agentId) external {
        _requireOwner(agentId);
        _storeAndEmitWallet(agentId, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                                 READS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IIdentityRegistry
    function getMetadata(uint256 agentId, string calldata key) external view returns (bytes memory) {
        return _metadata[agentId][_metadataSlot(agentId, keccak256(bytes(key)))];
    }

    /// @inheritdoc IIdentityRegistry
    /// @dev Note: reads the reserved "agentWallet" metadata slot and decodes the 20 packed bytes.
    ///      Returns address(0) for an unset wallet OR an unregistered/burned agentId (no revert).
    function getAgentWallet(uint256 agentId) external view returns (address) {
        bytes memory packed = _metadata[agentId][_metadataSlot(agentId, RESERVED_AGENT_WALLET_KEY_HASH)];
        // forge-lint: disable-next-line(unsafe-typecast) — slot only ever holds 20 packed bytes via _storeAndEmitWallet
        return packed.length == 20 ? address(bytes20(packed)) : address(0);
    }

    /// @notice Cheap, non-reverting existence check for downstream consumers (R003/R004/adapters).
    /// @dev ERC-721 {ownerOf} reverts for unknown ids; this returns false instead. Use it for
    ///      "is there an agent here?" guards to avoid a revert on the no-agent branch.
    /// @return True if `agentId` is currently registered (minted and not burned).
    function exists(uint256 agentId) external view returns (bool) {
        return _ownerOf(agentId) != address(0);
    }

    /// @inheritdoc ERC721URIStorage
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    /// @dev supportsInterface mirrors the canonical ERC-8004 reference: detection is via ERC-721 /
    ///      ERC-721Metadata / ERC-165 (+ ERC-4906 from URIStorage, which we honor by emitting
    ///      MetadataUpdate in _setTokenURI). ERC-8004 defines NO standardized interfaceId, so we
    ///      deliberately do NOT advertise a self-derived id — compliance is established by ERC-721
    ///      detection plus exact selector parity with the reference ABI.
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @dev Apply all registration EFFECTS for a new agent — assign id, set URI, emit {Registered},
    ///      default the agent wallet to the owner — BEFORE the caller performs the _safeMint
    ///      INTERACTION (checks-effects-interactions). At the time the mint's onERC721Received
    ///      callback fires, the agent is already fully initialized.
    function _prepareAgent(string memory agentURI) private returns (uint256 agentId) {
        agentId = _nextAgentId++;
        _setTokenURI(agentId, agentURI);
        emit Registered(agentId, agentURI, msg.sender);
        _storeAndEmitWallet(agentId, msg.sender);
    }

    /// @dev Single source of truth for writing the agent wallet: stores `abi.encodePacked(wallet)`
    ///      (20 bytes, or empty for address(0)) under the reserved key and emits {MetadataSet} so
    ///      every wallet change — including the register-time default — is observable off-chain.
    function _storeAndEmitWallet(uint256 agentId, address wallet) private {
        bytes memory packed = wallet == address(0) ? bytes("") : abi.encodePacked(wallet);
        _metadata[agentId][_metadataSlot(agentId, RESERVED_AGENT_WALLET_KEY_HASH)] = packed;
        emit MetadataSet(agentId, "agentWallet", "agentWallet", packed);
    }

    /// @dev Persist a metadata entry (key hashed) and emit {MetadataSet}. Rejects the reserved
    ///      agent-wallet key so it can only move through {setAgentWallet}/{unsetAgentWallet}.
    function _writeMetadata(uint256 agentId, string calldata key, bytes calldata value) private {
        bytes32 keyHash = keccak256(bytes(key));
        if (keyHash == RESERVED_AGENT_WALLET_KEY_HASH) revert ReservedMetadataKey();
        _metadata[agentId][_metadataSlot(agentId, keyHash)] = value;
        emit MetadataSet(agentId, key, key, value);
    }

    /// @dev Epoch-namespaced storage slot for an agent's metadata key. Mixing the agent's current
    ///      {_metadataEpoch} into the slot means a single `++epoch` (on transfer/burn) atomically
    ///      orphans every key without iterating them — avoiding an unbounded delete loop that an
    ///      agent could grief into a permanently non-transferable token.
    function _metadataSlot(uint256 agentId, bytes32 keyHash) private view returns (bytes32) {
        return keccak256(abi.encode(_metadataEpoch[agentId], keyHash));
    }

    /// @dev Revert unless the caller owns `agentId`. `ownerOf` reverts for unregistered ids.
    function _requireOwner(uint256 agentId) private view {
        if (ownerOf(agentId) != msg.sender) revert NotAgentOwner(agentId, msg.sender);
    }

    /// @dev On a real ownership change (transfer) or burn, bump the agent's metadata epoch. This
    ///      resets ALL metadata — generic keys AND the verified agent wallet — so nothing persists
    ///      to a new owner: capability/venue claims become empty and the wallet must be re-set via
    ///      {setAgentWallet}. O(1): no per-key delete loop (which an agent could grief into an
    ///      untransferable token). No-op on mint (`from == 0`) and self-transfer (`from == to`).
    function _update(address to, uint256 tokenId, address auth) internal override(ERC721) returns (address from) {
        from = super._update(to, tokenId, auth);
        if (from != address(0) && from != to) {
            unchecked {
                ++_metadataEpoch[tokenId];
            }
        }
    }
}
