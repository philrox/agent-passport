// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentPassport} from "../src/AgentPassport.sol";

/// @notice Unit tests for AgentPassport (R001).
/// Each test isolates one FR/NFR. Multi-step scenarios live in AgentPassport.scenarios.t.sol.
contract AgentPassportTest is Test {
    AgentPassport internal passport;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    bytes32 internal constant ID = bytes32(uint256(0xA1));
    string internal constant NAME = "vaia-ai";
    string internal constant ENDPOINT = "https://vaia.live/agents/ai";
    address internal payment = makeAddr("payment");
    string internal constant URI = "ipfs://card-json";

    // re-declared so we can use vm.expectEmit
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

    function setUp() public {
        passport = new AgentPassport();
    }

    // ---------- FR1: registerAgent stores card ----------

    function test_RegisterAgent_StoresCard() public {
        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, URI);

        AgentPassport.AgentCard memory card = passport.resolveAgent(ID);
        assertEq(card.owner, alice, "owner");
        assertEq(card.name, NAME, "name");
        assertEq(card.endpoint, ENDPOINT, "endpoint");
        assertEq(card.paymentAddress, payment, "paymentAddress");
        assertEq(card.metadataURI, URI, "metadataURI");
    }

    function test_RegisterAgent_SetsRegisteredAt() public {
        vm.warp(1_700_000_000);
        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, URI);

        AgentPassport.AgentCard memory card = passport.resolveAgent(ID);
        assertEq(card.registeredAt, uint64(1_700_000_000), "registeredAt == block.timestamp");
    }

    // ---------- FR5: duplicate revert ----------

    function test_RegisterAgent_RevertsOnDuplicate() public {
        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, URI);

        vm.expectRevert(abi.encodeWithSelector(AgentPassport.AlreadyRegistered.selector, ID));
        vm.prank(bob);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, URI);
    }

    // ---------- FR4: AgentRegistered event ----------

    function test_RegisterAgent_EmitsAgentRegistered() public {
        vm.warp(1_700_000_000);
        vm.expectEmit(true, true, false, true);
        emit AgentRegistered(ID, alice, NAME, ENDPOINT, payment, URI, uint64(1_700_000_000));

        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, URI);
    }

    // ---------- FR2: owner can update ----------

    function test_UpdateAgent_OwnerCanUpdate() public {
        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, URI);

        uint64 originalRegisteredAt = passport.resolveAgent(ID).registeredAt;

        address newPayment = makeAddr("newPayment");
        vm.prank(alice);
        passport.updateAgent(ID, "vaia-ai-v2", "https://vaia.live/v2", newPayment, "ipfs://card-v2");

        AgentPassport.AgentCard memory card = passport.resolveAgent(ID);
        assertEq(card.owner, alice, "owner unchanged");
        assertEq(card.registeredAt, originalRegisteredAt, "registeredAt unchanged");
        assertEq(card.name, "vaia-ai-v2", "name updated");
        assertEq(card.endpoint, "https://vaia.live/v2", "endpoint updated");
        assertEq(card.paymentAddress, newPayment, "payment updated");
        assertEq(card.metadataURI, "ipfs://card-v2", "uri updated");
    }

    // ---------- FR2: non-owner cannot update ----------

    function test_UpdateAgent_RevertsForNonOwner() public {
        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, URI);

        vm.expectRevert(abi.encodeWithSelector(AgentPassport.NotOwner.selector, ID, bob));
        vm.prank(bob);
        passport.updateAgent(ID, "hack", "https://evil", bob, "ipfs://evil");
    }

    // ---------- FR5: update on unknown id ----------

    function test_UpdateAgent_RevertsForUnknownId() public {
        bytes32 unknown = bytes32(uint256(0xDEAD));
        vm.expectRevert(abi.encodeWithSelector(AgentPassport.UnknownAgent.selector, unknown));
        vm.prank(alice);
        passport.updateAgent(unknown, NAME, ENDPOINT, payment, URI);
    }

    // ---------- FR4: AgentUpdated event ----------

    function test_UpdateAgent_EmitsAgentUpdated() public {
        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, URI);

        address newPayment = makeAddr("newPayment");
        vm.expectEmit(true, false, false, true);
        emit AgentUpdated(ID, "vaia-ai-v2", "https://vaia.live/v2", newPayment, "ipfs://card-v2");

        vm.prank(alice);
        passport.updateAgent(ID, "vaia-ai-v2", "https://vaia.live/v2", newPayment, "ipfs://card-v2");
    }

    // ---------- FR3: unknown resolve returns empty (no revert) ----------

    function test_ResolveAgent_UnknownReturnsEmpty() public view {
        AgentPassport.AgentCard memory card = passport.resolveAgent(bytes32(uint256(0xBEEF)));
        assertEq(card.owner, address(0), "empty owner");
        assertEq(card.registeredAt, 0, "empty registeredAt");
        assertEq(bytes(card.name).length, 0, "empty name");
        assertEq(bytes(card.endpoint).length, 0, "empty endpoint");
        assertEq(card.paymentAddress, address(0), "empty payment");
        assertEq(bytes(card.metadataURI).length, 0, "empty uri");
    }
}
