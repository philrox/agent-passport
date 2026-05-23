// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title AgentPassport — STUB for RED phase
/// @notice Empty bodies on purpose. Real implementation lands in Step 5 (GREEN).
contract AgentPassport {
    struct AgentCard {
        address owner;
        uint64 registeredAt;
        string name;
        string endpoint;
        address paymentAddress;
        string metadataURI;
    }

    error AlreadyRegistered(bytes32 agentId);
    error NotOwner(bytes32 agentId, address caller);
    error UnknownAgent(bytes32 agentId);

    event AgentRegistered(
        bytes32 indexed agentId,
        address indexed owner,
        string name,
        string endpoint,
        address paymentAddress,
        string metadataURI,
        uint64 registeredAt
    );
    event AgentUpdated(
        bytes32 indexed agentId, string name, string endpoint, address paymentAddress, string metadataURI
    );

    function registerAgent(
        bytes32 agentId,
        string calldata name,
        string calldata endpoint,
        address paymentAddress,
        string calldata metadataURI
    ) external {}

    function updateAgent(
        bytes32 agentId,
        string calldata name,
        string calldata endpoint,
        address paymentAddress,
        string calldata metadataURI
    ) external {}

    function resolveAgent(bytes32) external pure returns (AgentCard memory empty) {
        return empty;
    }
}
