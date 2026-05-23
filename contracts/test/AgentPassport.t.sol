// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {AgentPassport} from "../src/AgentPassport.sol";
import {IIdentityRegistry} from "../src/interfaces/IIdentityRegistry.sol";

/// @title AgentPassport unit tests (SPEC-R002, ERC-8004 Identity Registry)
/// @dev RED-phase suite. Must FAIL against the stub before implementation.
contract AgentPassportTest is Test {
    AgentPassport internal registry;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    string internal constant URI1 = "ipfs://card-alice";
    string internal constant URI2 = "ipfs://card-alice-v2";

    // Mirror of the events under test (must match IIdentityRegistry signatures).
    event Registered(uint256 indexed agentId, string agentURI, address indexed owner);
    event URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy);
    event MetadataSet(
        uint256 indexed agentId, string indexed indexedMetadataKey, string metadataKey, bytes metadataValue
    );

    function setUp() public {
        registry = new AgentPassport();
    }

    /*//////////////////////////////////////////////////////////////
                              REGISTRATION
    //////////////////////////////////////////////////////////////*/

    // U1
    function test_Register_AssignsSequentialIds() public {
        vm.prank(alice);
        uint256 id1 = registry.register(URI1);
        vm.prank(bob);
        uint256 id2 = registry.register("ipfs://card-bob");
        assertEq(id1, 1, "first id must be 1");
        assertEq(id2, 2, "second id must be 2");
    }

    // U2
    function test_Register_MintsNFTToCaller() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);
        assertEq(registry.ownerOf(id), alice, "caller must own the agent NFT");
        assertEq(registry.balanceOf(alice), 1, "balance must reflect mint");
    }

    // U3
    function test_Register_EmitsRegistered() public {
        vm.expectEmit(true, true, true, true);
        emit Registered(1, URI1, alice);
        vm.prank(alice);
        registry.register(URI1);
    }

    // U4
    function test_Register_SetsTokenURI() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);
        assertEq(registry.tokenURI(id), URI1, "tokenURI must equal agentURI");
    }

    // U5
    function test_RegisterNoArg_MintsWithEmptyURI() public {
        vm.prank(alice);
        uint256 id = registry.register();
        assertEq(registry.ownerOf(id), alice, "no-arg register must still mint");
        assertEq(registry.tokenURI(id), "", "no-arg register must leave URI empty");
    }

    // U6
    function test_RegisterWithMetadata_StoresAndEmits() public {
        IIdentityRegistry.MetadataEntry[] memory entries = new IIdentityRegistry.MetadataEntry[](2);
        entries[0] = IIdentityRegistry.MetadataEntry({key: "capability", value: bytes("trading")});
        entries[1] = IIdentityRegistry.MetadataEntry({key: "venue", value: bytes("polymarket")});

        vm.expectEmit(true, true, true, true);
        emit MetadataSet(1, "capability", "capability", bytes("trading"));
        vm.expectEmit(true, true, true, true);
        emit MetadataSet(1, "venue", "venue", bytes("polymarket"));

        vm.prank(alice);
        uint256 id = registry.register(URI1, entries);

        assertEq(registry.getMetadata(id, "capability"), bytes("trading"));
        assertEq(registry.getMetadata(id, "venue"), bytes("polymarket"));
    }

    /*//////////////////////////////////////////////////////////////
                                 URI
    //////////////////////////////////////////////////////////////*/

    // U7
    function test_SetAgentURI_OwnerCanUpdate_EmitsURIUpdated() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        vm.expectEmit(true, true, true, true);
        emit URIUpdated(id, URI2, alice);
        vm.prank(alice);
        registry.setAgentURI(id, URI2);

        assertEq(registry.tokenURI(id), URI2, "URI must be updated");
    }

    // U8
    function test_SetAgentURI_RevertsForNonOwner() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        vm.expectRevert(abi.encodeWithSelector(AgentPassport.NotAgentOwner.selector, id, bob));
        vm.prank(bob);
        registry.setAgentURI(id, URI2);
    }

    /*//////////////////////////////////////////////////////////////
                               METADATA
    //////////////////////////////////////////////////////////////*/

    // U9
    function test_SetMetadata_RoundtripGetMetadata() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        vm.expectEmit(true, true, true, true);
        emit MetadataSet(id, "twitter", "twitter", bytes("@vaia"));
        vm.prank(alice);
        registry.setMetadata(id, "twitter", bytes("@vaia"));

        assertEq(registry.getMetadata(id, "twitter"), bytes("@vaia"));
    }

    // U10
    function test_SetMetadata_RevertsForNonOwner() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        vm.expectRevert(abi.encodeWithSelector(AgentPassport.NotAgentOwner.selector, id, bob));
        vm.prank(bob);
        registry.setMetadata(id, "twitter", bytes("@hijack"));
    }

    // U11
    function test_GetMetadata_UnknownKeyReturnsEmpty() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);
        assertEq(registry.getMetadata(id, "nonexistent"), bytes(""), "unknown key must return empty bytes");
    }

    /*//////////////////////////////////////////////////////////////
                            TRANSFER (OWNERSHIP)
    //////////////////////////////////////////////////////////////*/

    // U12
    function test_TransferFrom_ChangesOwnerOf() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        vm.prank(alice);
        registry.transferFrom(alice, bob, id);

        assertEq(registry.ownerOf(id), bob, "transfer must change owner");
        // New owner gains owner-gated rights.
        vm.prank(bob);
        registry.setAgentURI(id, URI2);
        assertEq(registry.tokenURI(id), URI2);
    }

    /*//////////////////////////////////////////////////////////////
                             AGENT WALLET
    //////////////////////////////////////////////////////////////*/

    // U13
    function test_SetAgentWallet_OwnerSets_GetReturns() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        address wallet = makeAddr("paymentWallet");
        vm.prank(alice);
        registry.setAgentWallet(id, wallet, 0, "");

        assertEq(registry.getAgentWallet(id), wallet, "agent wallet must be stored");
    }

    // U14
    function test_SetAgentWallet_RevertsForNonOwner() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        vm.expectRevert(abi.encodeWithSelector(AgentPassport.NotAgentOwner.selector, id, bob));
        vm.prank(bob);
        registry.setAgentWallet(id, bob, 0, "");
    }

    // U15
    function test_UnsetAgentWallet_ResetsToZero() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        address wallet = makeAddr("paymentWallet");
        vm.prank(alice);
        registry.setAgentWallet(id, wallet, 0, "");
        vm.prank(alice);
        registry.unsetAgentWallet(id);

        assertEq(registry.getAgentWallet(id), address(0), "wallet must reset to zero");
    }

    /*//////////////////////////////////////////////////////////////
                          INTERFACE / ERRORS
    //////////////////////////////////////////////////////////////*/

    // U16
    function test_SupportsInterface_ERC721_And_IIdentityRegistry() public view {
        assertTrue(registry.supportsInterface(0x80ac58cd), "must support ERC-721");
        assertTrue(registry.supportsInterface(0x5b5e139f), "must support ERC-721 Metadata");
        assertTrue(registry.supportsInterface(type(IIdentityRegistry).interfaceId), "must support IIdentityRegistry");
    }

    // U17
    function test_TokenURI_RevertsForUnregistered() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999)));
        registry.tokenURI(999);
    }

    // U18
    function test_Register_GasUnderBudget() public {
        vm.prank(alice);
        uint256 gasBefore = gasleft();
        uint256 id = registry.register(URI1);
        uint256 gasUsed = gasBefore - gasleft();
        // Sanity: registration actually happened (fails against the empty stub).
        assertEq(registry.ownerOf(id), alice);
        // Budget pinned from R002 gas report (median ~101k for register(string)); headroom for
        // short URIs. Guards against silent regression in downstream specs.
        assertLt(gasUsed, 150_000, "register gas over budget");
    }
}
