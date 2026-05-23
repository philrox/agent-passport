// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title AgentPassport — Cross-Venue Agent Identity Registry (Skeleton, R001)
/// @author VAIA team
/// @notice Permissionless registry mapping `bytes32` agent IDs to AgentCards.
///         Anyone can register a new agentId; only the registering address can update it.
///         Reads never revert — unknown IDs return an empty struct.
/// @dev Storage layout MUST remain APPEND-ONLY for future upgrades. R002 (ERC-8004
///      compliance) will inherit from this contract and add fields/methods, but MUST
///      NOT reorder existing struct fields. See `AgentCard` for the slot map.
contract AgentPassport {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice On-chain record for a registered agent.
    /// @dev Storage slot map (per agent):
    ///      slot 0: owner (20 bytes) + registeredAt (8 bytes) — packed (28 < 32)
    ///      slot 1: name              (dynamic string)
    ///      slot 2: endpoint          (dynamic string)
    ///      slot 3: paymentAddress    (20 bytes, own slot)
    ///      slot 4: metadataURI       (dynamic string)
    struct AgentCard {
        address owner;
        uint64 registeredAt;
        string name;
        string endpoint;
        address paymentAddress;
        string metadataURI;
    }

    /// @dev Private to keep storage layout opaque; access via {resolveAgent}.
    mapping(bytes32 => AgentCard) private _agents;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when registerAgent is called with an already-used agentId.
    error AlreadyRegistered(bytes32 agentId);

    /// @notice Thrown when updateAgent / relinquishAgent is called by a non-owner.
    error NotOwner(bytes32 agentId, address caller);

    /// @notice Thrown when updateAgent / relinquishAgent targets an unregistered agentId.
    error UnknownAgent(bytes32 agentId);

    /// @notice Thrown when registerAgent is called with `agentId == bytes32(0)`.
    /// @dev Reserves zero as an unambiguous "unset" sentinel for downstream consumers
    ///      (R003 JobContract default-initialized `bytes32 providerAgentId` etc.).
    error ZeroAgentId();

    /// @notice Thrown when register/update is called with `paymentAddress == address(0)`.
    /// @dev Prevents accidental fund-burn via SDK helpers that forget the field.
    error ZeroPaymentAddress();

    /// @notice Thrown when register/update is called with an empty `name`, `endpoint`,
    ///         or `metadataURI`. Prevents accidental wipe by half-populated SDK calls.
    error EmptyField();

    /// @notice Thrown when updateAgent is called with values identical to the stored card.
    ///         Forces callers to dedupe client-side and keeps event streams clean.
    error NoChange(bytes32 agentId);

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted on every successful registerAgent call.
    event AgentRegistered(
        bytes32 indexed agentId,
        address indexed owner,
        string name,
        string endpoint,
        address paymentAddress,
        string metadataURI,
        uint64 registeredAt
    );

    /// @notice Emitted on every successful updateAgent call.
    event AgentUpdated(
        bytes32 indexed agentId, string name, string endpoint, address paymentAddress, string metadataURI
    );

    /// @notice Emitted when an owner surrenders an agentId. After emission the slot
    ///         is empty and re-registerable by anyone (including a fresh key the
    ///         original owner now controls — useful for key-rotation/compromise flows).
    event AgentRelinquished(bytes32 indexed agentId, address indexed owner);

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL WRITES
    //////////////////////////////////////////////////////////////*/

    /// @notice Register a new agent. The caller becomes the agent's owner.
    /// @param agentId Caller-chosen unique identifier (e.g. keccak256 of canonical name).
    /// @param name Human-readable agent name.
    /// @param endpoint Service endpoint URL (HTTP, MCP, A2A, etc.).
    /// @param paymentAddress Address that should receive payments routed to this agent.
    /// @param metadataURI Off-chain pointer (IPFS / HTTPS) to the full Agent Card JSON.
    function registerAgent(
        bytes32 agentId,
        string calldata name,
        string calldata endpoint,
        address paymentAddress,
        string calldata metadataURI
    ) external {
        if (_agents[agentId].owner != address(0)) revert AlreadyRegistered(agentId);

        uint64 timestamp = uint64(block.timestamp);
        _agents[agentId] = AgentCard({
            owner: msg.sender,
            registeredAt: timestamp,
            name: name,
            endpoint: endpoint,
            paymentAddress: paymentAddress,
            metadataURI: metadataURI
        });

        emit AgentRegistered(agentId, msg.sender, name, endpoint, paymentAddress, metadataURI, timestamp);
    }

    /// @notice Update an existing agent's metadata. Only the current owner may call this.
    ///         `owner` and `registeredAt` are immutable post-registration.
    /// @param agentId The identifier of the agent to update.
    /// @param name New name (overwrites previous value).
    /// @param endpoint New endpoint URL (overwrites previous value).
    /// @param paymentAddress New payment address (overwrites previous value).
    /// @param metadataURI New metadata URI (overwrites previous value).
    function updateAgent(
        bytes32 agentId,
        string calldata name,
        string calldata endpoint,
        address paymentAddress,
        string calldata metadataURI
    ) external {
        AgentCard storage card = _agents[agentId];
        if (card.owner == address(0)) revert UnknownAgent(agentId);
        if (card.owner != msg.sender) revert NotOwner(agentId, msg.sender);

        card.name = name;
        card.endpoint = endpoint;
        card.paymentAddress = paymentAddress;
        card.metadataURI = metadataURI;

        emit AgentUpdated(agentId, name, endpoint, paymentAddress, metadataURI);
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL READS
    //////////////////////////////////////////////////////////////*/

    /// @notice Return the AgentCard for a given agentId.
    /// @dev Unknown IDs return an empty struct (owner == address(0)). Never reverts.
    /// @param agentId The identifier to look up.
    /// @return card The stored card or an empty struct if unregistered.
    function resolveAgent(bytes32 agentId) external view returns (AgentCard memory card) {
        return _agents[agentId];
    }

    // -------------------------------------------------------------------------
    // RED STUBS — real implementations land in the GREEN commit.
    // Empty bodies make new tests compile and fail at runtime (not compile-time).
    // -------------------------------------------------------------------------

    /// @notice Cheap owner lookup (stub).
    function agentOwner(bytes32) external pure returns (address) {
        return address(0);
    }

    /// @notice Cheap existence check (stub).
    function exists(bytes32) external pure returns (bool) {
        return false;
    }

    /// @notice Surrender an agentId (stub).
    function relinquishAgent(bytes32) external pure {}
}
