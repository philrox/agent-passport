// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {IIdentityRegistry} from "./interfaces/IIdentityRegistry.sol";

/// @title AgentPassport — ERC-8004 Identity Registry (R002)
/// @notice STUB for TDD RED phase. Bodies intentionally empty so the suite compiles and
///         fails at runtime. Real implementation lands in the GREEN commit.
contract AgentPassport is ERC721URIStorage, IIdentityRegistry {
    constructor() ERC721("Agent Passport", "AGENT") {}

    function register(string calldata, MetadataEntry[] calldata) external returns (uint256 agentId) {}

    function register(string calldata) external returns (uint256 agentId) {}

    function register() external returns (uint256 agentId) {}

    function setAgentURI(uint256, string calldata) external {}

    function setMetadata(uint256, string calldata, bytes calldata) external {}

    function getMetadata(uint256, string calldata) external view returns (bytes memory) {}

    function setAgentWallet(uint256, address, uint256, bytes calldata) external {}

    function getAgentWallet(uint256) external view returns (address) {}

    function unsetAgentWallet(uint256) external {}

    function supportsInterface(bytes4 interfaceId) public view override(ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
