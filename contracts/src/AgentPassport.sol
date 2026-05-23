// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title AgentPassport — Cross-Venue Agent Identity Registry (Skeleton, R001)
/// @author VAIA team
/// @notice Permissionless registry mapping `bytes32` agent IDs to AgentCards.
///         Anyone can register a new agentId; only the registering address can update
///         or relinquish it. Reads never revert — unknown IDs return an empty struct.
/// @dev R002 (ERC-8004 compliance) inherits this contract. Two invariants the
///      subclass MUST preserve:
///        1. `_agents` mapping stays at storage slot 0 — add new state AFTER it.
///        2. Inheritance order is `is AgentPassport, ERC721` (NOT the reverse) so
///           AgentPassport's storage is laid down first. Reversing the order would
///           shift `_agents` to a different slot and corrupt every existing record.
contract AgentPassport {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice On-chain record for a registered agent.
    /// @dev Per-entry storage slot map (relative to the value's keccak-derived root):
    ///        slot 0: `owner` (low 160 bits) + `registeredAt` (next 64 bits), packed
    ///        slot 1: `name`           (string)
    ///        slot 2: `endpoint`       (string)
    ///        slot 3: `paymentAddress` (address — own slot, bracketed by strings)
    ///        slot 4: `metadataURI`    (string)
    ///      Pinned by `test_StorageLayout_AgentCard_SlotMap`. New fields MUST be
    ///      appended after `metadataURI`; never insert mid-struct.
    struct AgentCard {
        address owner;
        uint64 registeredAt;
        string name;
        string endpoint;
        address paymentAddress;
        string metadataURI;
    }

    /// @dev `internal` so the R002 ERC-8004 layer can align its NFT ownership
    ///      with this mapping. `private` would force R002 to shadow-store
    ///      ownership and risk dual-source-of-truth drift on transferFrom.
    mapping(bytes32 => AgentCard) internal _agents;

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
    /// @dev Reserves zero as an unambiguous "unset" sentinel for downstream
    ///      consumers (R003 JobContract's default-initialized `bytes32 providerAgentId`,
    ///      indexers' "no agent" rows, etc.).
    error ZeroAgentId();

    /// @notice Thrown when register/update is called with `paymentAddress == address(0)`.
    /// @dev Prevents accidental fund-burn via SDK helpers that forget the field.
    ///      Owners that genuinely want no-payment should route to a sink they control.
    error ZeroPaymentAddress();

    /// @notice Thrown when register/update is called with an empty `name`, `endpoint`,
    ///         or `metadataURI`. Prevents accidental wipe by half-populated SDK calls.
    error EmptyField();

    /// @notice Thrown when updateAgent is called with values identical to the stored
    ///         card. Forces callers to dedupe client-side and keeps event streams clean.
    error NoChange(bytes32 agentId);

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted on every successful registerAgent call.
    /// @dev 3 indexed topics (agentId, owner, paymentAddress) so off-chain indexers
    ///      can filter by any of them via `eth_getLogs`.
    event AgentRegistered(
        bytes32 indexed agentId,
        address indexed owner,
        address indexed paymentAddress,
        string name,
        string endpoint,
        string metadataURI,
        uint64 registeredAt
    );

    /// @notice Emitted on every successful updateAgent call.
    /// @dev Symmetric topic set with AgentRegistered (agentId + owner + paymentAddress).
    event AgentUpdated(
        bytes32 indexed agentId,
        address indexed owner,
        address indexed paymentAddress,
        string name,
        string endpoint,
        string metadataURI
    );

    /// @notice Emitted when an owner surrenders an agentId. After emission the slot
    ///         is empty and re-registerable by anyone (the original owner with a
    ///         fresh key included — supports compromised-key recovery).
    event AgentRelinquished(bytes32 indexed agentId, address indexed owner);

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL WRITES
    //////////////////////////////////////////////////////////////*/

    /// @notice Register a new agent. The caller becomes the agent's owner.
    /// @param agentId Caller-chosen unique identifier (e.g. keccak256 of canonical name). MUST be non-zero.
    /// @param name Human-readable agent name. MUST be non-empty.
    /// @param endpoint Service endpoint URL (HTTP, MCP, A2A, etc.). MUST be non-empty.
    /// @param paymentAddress Address that should receive payments routed to this agent. MUST be non-zero.
    /// @param metadataURI Off-chain pointer (IPFS / HTTPS) to the full Agent Card JSON. MUST be non-empty.
    function registerAgent(
        bytes32 agentId,
        string calldata name,
        string calldata endpoint,
        address paymentAddress,
        string calldata metadataURI
    ) external {
        if (agentId == bytes32(0)) revert ZeroAgentId();
        if (paymentAddress == address(0)) revert ZeroPaymentAddress();
        if (bytes(name).length == 0 || bytes(endpoint).length == 0 || bytes(metadataURI).length == 0) {
            revert EmptyField();
        }
        // slither-disable-next-line timestamp — false positive: this is an address comparison, not a timestamp comparison
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

        emit AgentRegistered(agentId, msg.sender, paymentAddress, name, endpoint, metadataURI, timestamp);
    }

    /// @notice Update an existing agent's metadata. Only the current owner may call this.
    ///         `owner` and `registeredAt` are immutable post-registration. Reverts with
    ///         {NoChange} when the new payload equals the stored card — prevents indexer noise.
    /// @dev Field validation matches {registerAgent}: paymentAddress non-zero, all strings non-empty.
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
        if (paymentAddress == address(0)) revert ZeroPaymentAddress();
        if (bytes(name).length == 0 || bytes(endpoint).length == 0 || bytes(metadataURI).length == 0) {
            revert EmptyField();
        }

        // No-op detection: revert if the payload matches the stored card exactly.
        // Field-by-field short-circuit AND keeps gas minimal on the common "something changed" path.
        bool unchanged = card.paymentAddress == paymentAddress && keccak256(bytes(card.name)) == keccak256(bytes(name))
            && keccak256(bytes(card.endpoint)) == keccak256(bytes(endpoint))
            && keccak256(bytes(card.metadataURI)) == keccak256(bytes(metadataURI));
        if (unchanged) revert NoChange(agentId);

        card.name = name;
        card.endpoint = endpoint;
        card.paymentAddress = paymentAddress;
        card.metadataURI = metadataURI;

        emit AgentUpdated(agentId, msg.sender, paymentAddress, name, endpoint, metadataURI);
    }

    /// @notice Surrender an agentId. After this call the slot is empty and anyone
    ///         (including the original owner with a fresh key) can re-register it.
    /// @dev Supports key-compromise recovery: the compromised key relinquishes,
    ///      a new key re-registers. Attacker who already controls the key can also
    ///      relinquish, but that's no worse than the existing compromise.
    /// @param agentId The identifier to surrender. Must be registered to msg.sender.
    function relinquishAgent(bytes32 agentId) external {
        AgentCard storage card = _agents[agentId];
        if (card.owner == address(0)) revert UnknownAgent(agentId);
        if (card.owner != msg.sender) revert NotOwner(agentId, msg.sender);

        address owner = card.owner;
        delete _agents[agentId];
        emit AgentRelinquished(agentId, owner);
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL READS
    //////////////////////////////////////////////////////////////*/

    /// @notice Return the full AgentCard for a given agentId.
    /// @dev Unknown IDs return an empty struct (owner == address(0)). Never reverts.
    ///      Prefer {agentOwner} or {exists} for owner-only checks (cheaper).
    function resolveAgent(bytes32 agentId) external view returns (AgentCard memory card) {
        return _agents[agentId];
    }

    /// @notice Cheap owner lookup for other contracts (R003 JobContract, R007 adapters).
    /// @dev Unknown IDs return `address(0)`. Never reverts. Avoids decoding the full
    ///      struct (3 dynamic strings) when callers only need ownership.
    /// @return owner The current owner of `agentId`, or `address(0)` if unregistered.
    function agentOwner(bytes32 agentId) external view returns (address owner) {
        return _agents[agentId].owner;
    }

    /// @notice Cheap existence check.
    /// @return True if `agentId` has been registered (and not relinquished).
    function exists(bytes32 agentId) external view returns (bool) {
        // slither-disable-next-line timestamp — false positive: address comparison, not timestamp
        return _agents[agentId].owner != address(0);
    }
}
