// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IIdentityRegistry — ERC-8004 Identity Registry interface (R002)
/// @notice Canonical surface of the ERC-8004 "Trustless Agents" Identity Registry.
///         The registry is an ERC-721: each agent is a token whose `tokenId` is the
///         `agentId` (uint256, auto-increment). `tokenURI(agentId)` points to the
///         off-chain Agent Card JSON. Reference: https://eips.ethereum.org/EIPS/eip-8004
/// @dev Implemented by {AgentPassport}. ERC-721 / ERC-721-Metadata functions
///      (`ownerOf`, `tokenURI`, `transferFrom`, ...) come from the ERC-721 base and are
///      intentionally NOT redeclared here — this interface covers only the 8004-specific
///      additions so `type(IIdentityRegistry).interfaceId` stays stable and meaningful.
interface IIdentityRegistry {
    /// @notice A single off-chain-extensible metadata entry (key → arbitrary bytes value).
    struct MetadataEntry {
        string key;
        bytes value;
    }

    /// @notice Emitted when a new agent is registered (NFT minted).
    /// @param agentId The freshly assigned, auto-incremented agent id (= ERC-721 tokenId).
    /// @param agentURI The Agent Card URI set at registration (may be empty for the no-arg overload).
    /// @param owner The address that registered and now owns the agent NFT.
    event Registered(uint256 indexed agentId, string agentURI, address indexed owner);

    /// @notice Emitted when an agent's URI is changed via {setAgentURI}.
    event URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy);

    /// @notice Emitted for every metadata key written via {register}, {setMetadata}, and the
    ///         reserved "agentWallet" key (register-time default, setAgentWallet, unsetAgentWallet).
    /// @param indexedMetadataKey The key as an indexed topic. NOTE: because this is an indexed
    ///        dynamic type, the log TOPIC is `keccak256(bytes(metadataKey))`, NOT the plaintext —
    ///        filter by the hash. The plaintext is in `metadataKey`.
    /// @param metadataKey The metadata key in plaintext.
    /// @param metadataValue The raw bytes value. For the reserved "agentWallet" key this is the
    ///        agent wallet as `abi.encodePacked(address)` (20 bytes), or empty bytes when unset.
    event MetadataSet(
        uint256 indexed agentId, string indexed indexedMetadataKey, string metadataKey, bytes metadataValue
    );

    /// @notice Register a new agent with a URI and a batch of metadata entries.
    /// @return agentId The newly minted agent id.
    function register(string calldata agentURI, MetadataEntry[] calldata metadata) external returns (uint256 agentId);

    /// @notice Register a new agent with only a URI.
    function register(string calldata agentURI) external returns (uint256 agentId);

    /// @notice Register a new agent with no URI (set later via {setAgentURI}).
    function register() external returns (uint256 agentId);

    /// @notice Update an agent's URI. Owner-gated.
    function setAgentURI(uint256 agentId, string calldata newURI) external;

    /// @notice Set a metadata key on an agent. Owner-gated.
    /// @dev Generic key→bytes store: writes are last-writer-wins (re-writing a key overwrites it)
    ///      and an empty `value` clears the key — there is no value validation or change-dedup by
    ///      design; validate the Agent Card schema off-chain. A cleared key and a never-set key are
    ///      indistinguishable on read (both return empty bytes) — callers needing presence semantics
    ///      must encode that in the value. All metadata is reset on transfer/burn (see {getMetadata}
    ///      note). The reserved key "agentWallet" is rejected (use {setAgentWallet}).
    function setMetadata(uint256 agentId, string calldata key, bytes calldata value) external;

    /// @notice Read a metadata value. Unknown keys (and unregistered agentIds) return empty bytes,
    ///         never reverts.
    /// @dev The reserved key "agentWallet" is readable here and returns the wallet as
    ///      `abi.encodePacked(address)` (20 bytes); prefer {getAgentWallet} for the typed value.
    ///      All of an agent's metadata is reset on transfer/burn, so reads against a key set by a
    ///      previous owner (or before a burn) return empty bytes.
    function getMetadata(uint256 agentId, string calldata key) external view returns (bytes memory);

    /// @notice Set the agent's wallet (payment/operator address, distinct from the NFT owner).
    /// @dev Caller must own `agentId`. `newWallet` authorizes the assignment with an EIP-712
    ///      signature (EOA) or ERC-1271 (smart-contract wallet) over
    ///      `AgentWalletSet(uint256 agentId,address newWallet,address owner,uint256 deadline)`.
    ///      `deadline` must be in the future and within 5 minutes. There is NO nonce (matching the
    ///      canonical reference): within the deadline window the same signature is replayable —
    ///      including re-setting after {unsetAgentWallet}. This is not a third-party attack vector:
    ///      every call is owner-gated, so only the current owner can replay, and replaying only
    ///      re-sets a wallet the owner already authorized. The `owner` field binds the signature to
    ///      the current owner, voiding it after a transfer (and the epoch reset in {_update} clears
    ///      the stored wallet regardless).
    function setAgentWallet(uint256 agentId, address newWallet, uint256 deadline, bytes calldata signature) external;

    /// @notice Read the agent's wallet. Returns address(0) if unset, unregistered, or burned.
    function getAgentWallet(uint256 agentId) external view returns (address);

    /// @notice Clear the agent's wallet. Owner-gated.
    function unsetAgentWallet(uint256 agentId) external;
}
