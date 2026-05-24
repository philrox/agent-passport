// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {AgentPassport} from "../src/AgentPassport.sol";

/// @title AgentPassport scenario + fuzz tests (SPEC-R002)
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

    // F4: fuzz the owner-gate over arbitrary adversary addresses — no non-owner may mutate.
    function testFuzz_NonOwnerCannotMutate(address attacker) public {
        vm.assume(attacker != alice && attacker != address(0));
        vm.prank(alice);
        uint256 id = registry.register("ipfs://alice");

        vm.expectRevert(abi.encodeWithSelector(AgentPassport.NotAgentOwner.selector, id, attacker));
        vm.prank(attacker);
        registry.setAgentURI(id, "ipfs://hijack");

        vm.expectRevert(abi.encodeWithSelector(AgentPassport.NotAgentOwner.selector, id, attacker));
        vm.prank(attacker);
        registry.setMetadata(id, "k", bytes("v"));
    }

    // F5: registering from a contract that is not an ERC-721 receiver reverts (safe mint).
    function test_Register_FromNonReceiverContract_Reverts() public {
        NonReceiver nr = new NonReceiver(registry);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(nr)));
        nr.doRegister();
    }
}

/// @dev A contract that does NOT implement IERC721Receiver; registering from it must revert.
contract NonReceiver {
    AgentPassport private reg;

    constructor(AgentPassport _reg) {
        reg = _reg;
    }

    function doRegister() external returns (uint256) {
        return reg.register("ipfs://nonreceiver");
    }
}
