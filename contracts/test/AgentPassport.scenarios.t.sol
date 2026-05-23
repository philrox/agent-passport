// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentPassport} from "../src/AgentPassport.sol";

/// @title AgentPassport scenario + fuzz tests (SPEC-R002)
/// @dev RED-phase suite. Must FAIL against the stub before implementation.
contract AgentPassportScenariosTest is Test {
    AgentPassport internal registry;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        registry = new AgentPassport();
    }

    // F1: register -> transfer -> resolve. URI survives the ownership change.
    function test_Scenario_RegisterTransferResolve() public {
        vm.prank(alice);
        uint256 id = registry.register("ipfs://alice");
        assertEq(registry.ownerOf(id), alice);

        vm.prank(alice);
        registry.transferFrom(alice, bob, id);

        assertEq(registry.ownerOf(id), bob, "owner after transfer");
        assertEq(registry.tokenURI(id), "ipfs://alice", "URI stable across transfer");
    }

    // F2: three agents, isolated state. Updating one touches no other.
    function test_Scenario_MultiAgent_IsolatedState() public {
        vm.prank(alice);
        uint256 a = registry.register("ipfs://alice");
        vm.prank(bob);
        uint256 b = registry.register("ipfs://bob");
        vm.prank(carol);
        uint256 c = registry.register("ipfs://carol");

        // Bob updates URI + metadata.
        vm.prank(bob);
        registry.setAgentURI(b, "ipfs://bob-v2");
        vm.prank(bob);
        registry.setMetadata(b, "tag", bytes("updated"));

        // Alice + Carol untouched.
        assertEq(registry.tokenURI(a), "ipfs://alice");
        assertEq(registry.tokenURI(c), "ipfs://carol");
        assertEq(registry.getMetadata(a, "tag"), bytes(""));
        assertEq(registry.getMetadata(c, "tag"), bytes(""));
        assertEq(registry.ownerOf(a), alice);
        assertEq(registry.ownerOf(c), carol);
    }

    // F3: fuzz arbitrary callers + URIs. First registration on a fresh registry is always id 1,
    // minted to the caller.
    function testFuzz_RegisterArbitraryURIs(address caller, string calldata uri) public {
        vm.assume(caller != address(0));
        vm.assume(caller.code.length == 0); // EOA: _safeMint to a non-receiver contract reverts
        vm.assume(uint160(caller) > 9); // skip precompiles
        vm.assume(bytes(uri).length <= 256);

        vm.prank(caller);
        uint256 id = registry.register(uri);

        assertEq(id, 1, "first registration id");
        assertEq(registry.ownerOf(id), caller, "owner is caller");
        assertEq(registry.tokenURI(id), uri, "uri roundtrip");
    }
}
