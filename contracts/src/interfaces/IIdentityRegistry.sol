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

    /// @notice Emitted for every metadata key written via {register} or {setMetadata}.
    /// @param indexedMetadataKey The key as an indexed topic (filterable); equals `metadataKey`.
    /// @param metadataKey The metadata key in plaintext.
    /// @param metadataValue The raw bytes value.
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
    function setMetadata(uint256 agentId, string calldata key, bytes calldata value) external;

    /// @notice Read a metadata value. Unknown keys return empty bytes (never reverts).
    function getMetadata(uint256 agentId, string calldata key) external view returns (bytes memory);

    /// @notice Set the agent's wallet (payment/operator address, distinct from the NFT owner).
    /// @dev R002 deviation: owner-gated; `deadline`/`signature` are accepted but NOT verified.
    ///      The EIP-712 signature-delegation path is a documented follow-up (see SPEC-R002).
    function setAgentWallet(uint256 agentId, address newWallet, uint256 deadline, bytes calldata signature) external;

    /// @notice Read the agent's wallet. Returns address(0) if unset.
    function getAgentWallet(uint256 agentId) external view returns (address);

    /// @notice Clear the agent's wallet. Owner-gated.
    function unsetAgentWallet(uint256 agentId) external;
}
