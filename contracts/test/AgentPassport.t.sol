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

    // re-declared so we can use vm.expectEmit — must match contract byte-for-byte
    event AgentRegistered(
        bytes32 indexed agentId,
        address indexed owner,
        address indexed paymentAddress,
        string name,
        string endpoint,
        string metadataURI,
        uint64 registeredAt
    );
    event AgentUpdated(
        bytes32 indexed agentId,
        address indexed owner,
        address indexed paymentAddress,
        string name,
        string endpoint,
        string metadataURI
    );
    event AgentRelinquished(bytes32 indexed agentId, address indexed owner);

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
        // 3 indexed topics (agentId, owner, paymentAddress) + data check
        vm.expectEmit(true, true, true, true);
        emit AgentRegistered(ID, alice, payment, NAME, ENDPOINT, URI, uint64(1_700_000_000));

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
        // 3 indexed topics (agentId, owner, paymentAddress) + data check
        vm.expectEmit(true, true, true, true);
        emit AgentUpdated(ID, alice, newPayment, "vaia-ai-v2", "https://vaia.live/v2", "ipfs://card-v2");

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

    // ====================================================================
    // FR6 (NEW): input validation — register rejects zero/empty
    // ====================================================================

    function test_RegisterAgent_RevertsOnZeroAgentId() public {
        vm.expectRevert(AgentPassport.ZeroAgentId.selector);
        vm.prank(alice);
        passport.registerAgent(bytes32(0), NAME, ENDPOINT, payment, URI);
    }

    function test_RegisterAgent_RevertsOnZeroPaymentAddress() public {
        vm.expectRevert(AgentPassport.ZeroPaymentAddress.selector);
        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, address(0), URI);
    }

    function test_RegisterAgent_RevertsOnEmptyName() public {
        vm.expectRevert(AgentPassport.EmptyField.selector);
        vm.prank(alice);
        passport.registerAgent(ID, "", ENDPOINT, payment, URI);
    }

    function test_RegisterAgent_RevertsOnEmptyEndpoint() public {
        vm.expectRevert(AgentPassport.EmptyField.selector);
        vm.prank(alice);
        passport.registerAgent(ID, NAME, "", payment, URI);
    }

    function test_RegisterAgent_RevertsOnEmptyMetadataURI() public {
        vm.expectRevert(AgentPassport.EmptyField.selector);
        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, "");
    }

    // ====================================================================
    // FR6 (NEW): input validation — update rejects zero/empty
    // ====================================================================

    function test_UpdateAgent_RevertsOnZeroAgentId() public {
        // Zero is the reserved "unset" sentinel; updateAgent must reject it locally
        // with ZeroAgentId rather than leaking the misleading UnknownAgent error.
        vm.expectRevert(AgentPassport.ZeroAgentId.selector);
        vm.prank(alice);
        passport.updateAgent(bytes32(0), NAME, ENDPOINT, payment, URI);
    }

    function test_UpdateAgent_RevertsOnZeroPaymentAddress() public {
        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, URI);

        vm.expectRevert(AgentPassport.ZeroPaymentAddress.selector);
        vm.prank(alice);
        passport.updateAgent(ID, NAME, ENDPOINT, address(0), URI);
    }

    function test_UpdateAgent_RevertsOnEmptyName() public {
        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, URI);

        vm.expectRevert(AgentPassport.EmptyField.selector);
        vm.prank(alice);
        passport.updateAgent(ID, "", ENDPOINT, payment, URI);
    }

    function test_UpdateAgent_RevertsOnEmptyEndpoint() public {
        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, URI);

        vm.expectRevert(AgentPassport.EmptyField.selector);
        vm.prank(alice);
        passport.updateAgent(ID, NAME, "", payment, URI);
    }

    function test_UpdateAgent_RevertsOnEmptyMetadataURI() public {
        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, URI);

        vm.expectRevert(AgentPassport.EmptyField.selector);
        vm.prank(alice);
        passport.updateAgent(ID, NAME, ENDPOINT, payment, "");
    }

    // ====================================================================
    // FR7 (NEW): NoChange detection in updateAgent
    // ====================================================================

    function test_UpdateAgent_RevertsOnNoChange() public {
        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, URI);

        vm.expectRevert(abi.encodeWithSelector(AgentPassport.NoChange.selector, ID));
        vm.prank(alice);
        passport.updateAgent(ID, NAME, ENDPOINT, payment, URI);
    }

    function test_UpdateAgent_PartialChange_PaymentOnly() public {
        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, URI);

        address newPayment = makeAddr("newPay");
        vm.prank(alice);
        passport.updateAgent(ID, NAME, ENDPOINT, newPayment, URI);

        AgentPassport.AgentCard memory card = passport.resolveAgent(ID);
        assertEq(card.paymentAddress, newPayment, "payment changed");
        assertEq(card.name, NAME, "name unchanged");
        assertEq(card.endpoint, ENDPOINT, "endpoint unchanged");
        assertEq(card.metadataURI, URI, "uri unchanged");
    }

    function test_UpdateAgent_PartialChange_NameOnly() public {
        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, URI);

        vm.prank(alice);
        passport.updateAgent(ID, "vaia-ai-renamed", ENDPOINT, payment, URI);

        assertEq(passport.resolveAgent(ID).name, "vaia-ai-renamed");
    }

    // ====================================================================
    // FR8 (NEW): cheap owner / existence accessors
    // ====================================================================

    function test_AgentOwner_ReturnsOwner() public {
        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, URI);
        assertEq(passport.agentOwner(ID), alice);
    }

    function test_AgentOwner_UnknownReturnsZero() public view {
        assertEq(passport.agentOwner(bytes32(uint256(0xDEAD))), address(0));
    }

    function test_Exists_TrueForRegistered() public {
        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, URI);
        assertTrue(passport.exists(ID));
    }

    function test_Exists_FalseForUnknown() public view {
        assertFalse(passport.exists(bytes32(uint256(0xDEAD))));
    }

    // ====================================================================
    // FR9 (NEW): relinquishAgent — owner surrenders ID for re-registration
    // ====================================================================

    function test_RelinquishAgent_OwnerCanRelinquish() public {
        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, URI);

        vm.prank(alice);
        passport.relinquishAgent(ID);

        assertFalse(passport.exists(ID), "no longer exists");
        assertEq(passport.agentOwner(ID), address(0), "owner cleared");
        AgentPassport.AgentCard memory card = passport.resolveAgent(ID);
        assertEq(card.owner, address(0), "card wiped");
        assertEq(bytes(card.name).length, 0, "name wiped");
    }

    function test_RelinquishAgent_RevertsForNonOwner() public {
        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, URI);

        vm.expectRevert(abi.encodeWithSelector(AgentPassport.NotOwner.selector, ID, bob));
        vm.prank(bob);
        passport.relinquishAgent(ID);
    }

    function test_RelinquishAgent_RevertsForUnknown() public {
        bytes32 unknown = bytes32(uint256(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(AgentPassport.UnknownAgent.selector, unknown));
        vm.prank(alice);
        passport.relinquishAgent(unknown);
    }

    function test_RelinquishAgent_RevertsOnZeroAgentId() public {
        // Zero sentinel rejected locally with ZeroAgentId, not UnknownAgent.
        vm.expectRevert(AgentPassport.ZeroAgentId.selector);
        vm.prank(alice);
        passport.relinquishAgent(bytes32(0));
    }

    function test_RelinquishAgent_EmitsEvent() public {
        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, URI);

        vm.expectEmit(true, true, false, false);
        emit AgentRelinquished(ID, alice);

        vm.prank(alice);
        passport.relinquishAgent(ID);
    }

    function test_RelinquishAgent_AllowsReRegistration() public {
        vm.prank(alice);
        passport.registerAgent(ID, NAME, ENDPOINT, payment, URI);

        vm.prank(alice);
        passport.relinquishAgent(ID);

        vm.prank(bob);
        passport.registerAgent(ID, "bob", "ep-bob", makeAddr("payBob"), "uri-bob");

        AgentPassport.AgentCard memory card = passport.resolveAgent(ID);
        assertEq(card.owner, bob, "new owner");
        assertEq(card.name, "bob", "new name");
    }

    // ====================================================================
    // NFR1 (NEW): gas budget assertion for registerAgent
    // ====================================================================

    function test_RegisterAgent_GasUnder250k() public {
        vm.prank(alice);
        uint256 before = gasleft();
        passport.registerAgent(
            bytes32(uint256(0xA1A1)),
            "vaia-ai", // 7 chars
            "https://vaia.live/agents/ai", // 28 chars
            payment,
            "ipfs://bafybeic1234567890abcdef" // 32 chars
        );
        uint256 used = before - gasleft();
        assertLt(used, 250_000, "NFR1: registerAgent < 250k for short strings");
    }

    // ====================================================================
    // NFR2 (NEW): storage layout snapshot — pins struct slot map
    // ====================================================================

    function test_StorageLayout_AgentCard_SlotMap() public {
        bytes32 id = bytes32(uint256(0xCAFE));
        address pay = makeAddr("layoutPay");
        vm.warp(1_700_000_000);
        vm.prank(alice);
        passport.registerAgent(id, "n", "e", pay, "u");

        // _agents is contract slot 0; agents[id] root = keccak256(abi.encode(id, 0))
        bytes32 root = keccak256(abi.encode(id, uint256(0)));

        // Struct slot 0: owner (low 160 bits) + registeredAt (next 64 bits), packed
        bytes32 s0 = vm.load(address(passport), root);
        assertEq(address(uint160(uint256(s0))), alice, "struct slot 0 [0..160]  = owner");
        assertEq(uint64(uint256(s0) >> 160), uint64(1_700_000_000), "struct slot 0 [160..224] = registeredAt");

        // Struct slot 3: paymentAddress (own slot, no packing — bracketed by strings)
        bytes32 s3 = vm.load(address(passport), bytes32(uint256(root) + 3));
        assertEq(address(uint160(uint256(s3))), pay, "struct slot 3 = paymentAddress");
    }
}
