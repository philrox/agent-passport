// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentPassport} from "../src/AgentPassport.sol";

/// @notice Functional (multi-step + fuzz) scenarios for AgentPassport (R001).
/// Unit-level FR coverage lives in AgentPassport.t.sol.
contract AgentPassportScenariosTest is Test {
    AgentPassport internal passport;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal charlie = makeAddr("charlie");

    function setUp() public {
        passport = new AgentPassport();
    }

    // ---------- F1: full lifecycle, registeredAt is sticky ----------

    function test_Roundtrip_RegisterUpdateResolve() public {
        bytes32 id = keccak256("vaia-ai");

        vm.warp(1_700_000_000);
        vm.prank(alice);
        passport.registerAgent(id, "vaia-ai", "https://vaia.live/ai", makeAddr("pay1"), "ipfs://v1");

        AgentPassport.AgentCard memory afterRegister = passport.resolveAgent(id);
        assertEq(afterRegister.owner, alice);
        assertEq(afterRegister.registeredAt, 1_700_000_000);
        assertEq(afterRegister.metadataURI, "ipfs://v1");

        // simulate time passing — registeredAt must NOT change on update
        vm.warp(1_700_000_500);
        vm.prank(alice);
        passport.updateAgent(id, "vaia-ai", "https://vaia.live/ai-v2", makeAddr("pay2"), "ipfs://v2");

        AgentPassport.AgentCard memory afterUpdate = passport.resolveAgent(id);
        assertEq(afterUpdate.owner, alice, "owner sticky");
        assertEq(afterUpdate.registeredAt, 1_700_000_000, "registeredAt sticky (not 1_700_000_500)");
        assertEq(afterUpdate.endpoint, "https://vaia.live/ai-v2");
        assertEq(afterUpdate.metadataURI, "ipfs://v2");
    }

    // ---------- F2: storage isolation across agents ----------

    function test_MultiAgent_IsolatedStorage() public {
        bytes32 idAlice = keccak256("alice-agent");
        bytes32 idBob = keccak256("bob-agent");
        bytes32 idCharlie = keccak256("charlie-agent");

        vm.prank(alice);
        passport.registerAgent(idAlice, "alice", "ep-a", makeAddr("pA"), "uri-a");
        vm.prank(bob);
        passport.registerAgent(idBob, "bob", "ep-b", makeAddr("pB"), "uri-b");
        vm.prank(charlie);
        passport.registerAgent(idCharlie, "charlie", "ep-c", makeAddr("pC"), "uri-c");

        // Update Bob — Alice and Charlie must remain untouched
        vm.prank(bob);
        passport.updateAgent(idBob, "bob-v2", "ep-b-v2", makeAddr("pB2"), "uri-b-v2");

        AgentPassport.AgentCard memory a = passport.resolveAgent(idAlice);
        AgentPassport.AgentCard memory b = passport.resolveAgent(idBob);
        AgentPassport.AgentCard memory c = passport.resolveAgent(idCharlie);

        assertEq(a.name, "alice", "alice untouched by bob's update");
        assertEq(a.endpoint, "ep-a");
        assertEq(b.name, "bob-v2", "bob updated");
        assertEq(b.endpoint, "ep-b-v2");
        assertEq(c.name, "charlie", "charlie untouched by bob's update");
        assertEq(c.endpoint, "ep-c");

        assertEq(a.owner, alice);
        assertEq(b.owner, bob);
        assertEq(c.owner, charlie);
    }

    // ---------- F3: owner is msg.sender, not caller-provided ----------

    function test_RegisterFromMultipleSenders_OwnerIsMsgSender() public {
        bytes32 id1 = keccak256("id-1");
        bytes32 id2 = keccak256("id-2");

        vm.prank(alice);
        passport.registerAgent(id1, "name-1", "ep-1", makeAddr("p1"), "uri-1");

        vm.prank(bob);
        passport.registerAgent(id2, "name-2", "ep-2", makeAddr("p2"), "uri-2");

        assertEq(passport.resolveAgent(id1).owner, alice, "id1 owner == alice");
        assertEq(passport.resolveAgent(id2).owner, bob, "id2 owner == bob");

        // Alice tries to update Bob's agent → must revert
        vm.expectRevert(abi.encodeWithSelector(AgentPassport.NotOwner.selector, id2, alice));
        vm.prank(alice);
        passport.updateAgent(id2, "hijack", "ep", address(0), "uri");
    }

    // ---------- F4: fuzz on register + ownership invariant ----------

    function testFuzz_RegisterArbitraryCards(
        bytes32 id,
        address registrant,
        address attacker,
        string calldata name,
        string calldata endpoint,
        address paymentAddress,
        string calldata metadataURI
    ) public {
        // Filter assumptions: non-zero registrant, distinct attacker, bounded strings
        vm.assume(registrant != address(0));
        vm.assume(attacker != address(0));
        vm.assume(attacker != registrant);
        vm.assume(bytes(name).length <= 64);
        vm.assume(bytes(endpoint).length <= 128);
        vm.assume(bytes(metadataURI).length <= 128);

        vm.prank(registrant);
        passport.registerAgent(id, name, endpoint, paymentAddress, metadataURI);

        AgentPassport.AgentCard memory card = passport.resolveAgent(id);
        assertEq(card.owner, registrant, "owner == registrant (msg.sender)");
        assertEq(card.name, name, "name roundtrips");
        assertEq(card.endpoint, endpoint, "endpoint roundtrips");
        assertEq(card.paymentAddress, paymentAddress, "payment roundtrips");
        assertEq(card.metadataURI, metadataURI, "uri roundtrips");

        // attacker cannot update
        vm.expectRevert(abi.encodeWithSelector(AgentPassport.NotOwner.selector, id, attacker));
        vm.prank(attacker);
        passport.updateAgent(id, "hack", "evil", attacker, "evil-uri");
    }
}
