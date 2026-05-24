// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
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
        vm.warp(1_700_000_000); // realistic timestamp for deadline checks
        registry = new AgentPassport();
    }

    /*//////////////////////////////////////////////////////////////
                         EIP-712 SIGNING HELPERS
    //////////////////////////////////////////////////////////////*/

    bytes32 private constant AGENT_WALLET_SET_TYPEHASH =
        keccak256("AgentWalletSet(uint256 agentId,address newWallet,address owner,uint256 deadline)");

    /// @dev Reconstructs the registry's EIP-712 domain separator independently (also asserts
    ///      the contract uses the canonical ERC-8004 domain name/version).
    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ERC8004IdentityRegistry")),
                keccak256(bytes("1")),
                block.chainid,
                address(registry)
            )
        );
    }

    function _signWallet(uint256 agentId, address newWallet, address owner, uint256 deadline, uint256 pk)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(AGENT_WALLET_SET_TYPEHASH, agentId, newWallet, owner, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
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

    // U27: register emits MetadataSet for the wallet-init-to-owner (event-source consistency).
    function test_Register_EmitsWalletInitMetadataSet() public {
        vm.expectEmit(true, true, true, true);
        emit MetadataSet(1, "agentWallet", "agentWallet", abi.encodePacked(alice));
        vm.prank(alice);
        registry.register(URI1);
    }

    // U28: CEI — during the _safeMint receiver callback, the agent is already fully initialized
    // (URI set, wallet defaulted). Proves effects happen before the external mint interaction.
    function test_Register_ReentrantReceiver_SeesFullyInitializedState() public {
        ReentrantRegistrant r = new ReentrantRegistrant(registry);
        r.doRegister();
        uint256 id = r.agentId();
        assertEq(r.observedURI(), "ipfs://recv", "URI must be set before the mint callback (CEI)");
        assertEq(r.observedWallet(), address(r), "wallet must be inited before the mint callback (CEI)");
        assertEq(registry.ownerOf(id), address(r));
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
                       AGENT WALLET (EIP-712 / ERC-1271)
    //////////////////////////////////////////////////////////////*/

    // U13: owner submits, newWallet's EIP-712 signature authorizes. MetadataSet emitted (interop).
    function test_SetAgentWallet_ValidSig_OwnerSets_GetReturns() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        (address wallet, uint256 walletPk) = makeAddrAndKey("paymentWallet");
        uint256 deadline = block.timestamp + 60;
        bytes memory sig = _signWallet(id, wallet, alice, deadline, walletPk);

        vm.expectEmit(true, true, true, true);
        emit MetadataSet(id, "agentWallet", "agentWallet", abi.encodePacked(wallet));
        vm.prank(alice);
        registry.setAgentWallet(id, wallet, deadline, sig);

        assertEq(registry.getAgentWallet(id), wallet, "agent wallet must be stored");
        // Interop: readable via generic getMetadata under the reserved key.
        assertEq(registry.getMetadata(id, "agentWallet"), abi.encodePacked(wallet));
    }

    // U14: caller authorization is checked before the signature.
    function test_SetAgentWallet_RevertsForNonOwner() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        (address wallet, uint256 walletPk) = makeAddrAndKey("paymentWallet");
        uint256 deadline = block.timestamp + 60;
        bytes memory sig = _signWallet(id, wallet, bob, deadline, walletPk);

        vm.expectRevert(abi.encodeWithSelector(AgentPassport.NotAgentOwner.selector, id, bob));
        vm.prank(bob);
        registry.setAgentWallet(id, wallet, deadline, sig);
    }

    // U15: unset needs no signature, owner-gated, resets to zero.
    function test_UnsetAgentWallet_ResetsToZero() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        (address wallet, uint256 walletPk) = makeAddrAndKey("paymentWallet");
        uint256 deadline = block.timestamp + 60;
        bytes memory sig = _signWallet(id, wallet, alice, deadline, walletPk);
        vm.prank(alice);
        registry.setAgentWallet(id, wallet, deadline, sig);

        vm.prank(alice);
        registry.unsetAgentWallet(id);
        assertEq(registry.getAgentWallet(id), address(0), "wallet must reset to zero");
    }

    // U19: expired deadline rejected.
    function test_SetAgentWallet_RevertsOnExpiredDeadline() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        (address wallet, uint256 walletPk) = makeAddrAndKey("paymentWallet");
        uint256 deadline = block.timestamp - 1;
        bytes memory sig = _signWallet(id, wallet, alice, deadline, walletPk);

        vm.expectRevert(abi.encodeWithSelector(AgentPassport.SignatureExpired.selector, deadline));
        vm.prank(alice);
        registry.setAgentWallet(id, wallet, deadline, sig);
    }

    // U20: deadline beyond the 5-minute cap rejected (nonce replacement).
    function test_SetAgentWallet_RevertsOnDeadlineTooFar() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        (address wallet, uint256 walletPk) = makeAddrAndKey("paymentWallet");
        uint256 deadline = block.timestamp + 6 minutes;
        bytes memory sig = _signWallet(id, wallet, alice, deadline, walletPk);

        vm.expectRevert(abi.encodeWithSelector(AgentPassport.DeadlineTooFar.selector, deadline));
        vm.prank(alice);
        registry.setAgentWallet(id, wallet, deadline, sig);
    }

    // U21: signature from a key other than newWallet rejected.
    function test_SetAgentWallet_RevertsOnWrongSigner() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        (address wallet,) = makeAddrAndKey("paymentWallet");
        (, uint256 attackerPk) = makeAddrAndKey("attacker");
        uint256 deadline = block.timestamp + 60;
        bytes memory sig = _signWallet(id, wallet, alice, deadline, attackerPk);

        vm.expectRevert(AgentPassport.InvalidWalletSignature.selector);
        vm.prank(alice);
        registry.setAgentWallet(id, wallet, deadline, sig);
    }

    // U22: owner-binding — a signature minted for a different owner value is invalid.
    function test_SetAgentWallet_RevertsIfSignedForDifferentOwner() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        (address wallet, uint256 walletPk) = makeAddrAndKey("paymentWallet");
        uint256 deadline = block.timestamp + 60;
        // newWallet signs but binds to bob as owner; actual owner is alice -> digest mismatch.
        bytes memory sig = _signWallet(id, wallet, bob, deadline, walletPk);

        vm.expectRevert(AgentPassport.InvalidWalletSignature.selector);
        vm.prank(alice);
        registry.setAgentWallet(id, wallet, deadline, sig);
    }

    // U23: ERC-1271 smart-contract wallet path.
    function test_SetAgentWallet_ERC1271_ContractWallet() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        Mock1271 scWallet = new Mock1271();
        uint256 deadline = block.timestamp + 60;
        // Mock returns the magic value regardless of signature contents.
        vm.prank(alice);
        registry.setAgentWallet(id, address(scWallet), deadline, hex"00");

        assertEq(registry.getAgentWallet(id), address(scWallet), "ERC-1271 wallet must be accepted");
    }

    // U24: register initializes the agent wallet to the owner.
    function test_Register_InitializesAgentWalletToOwner() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);
        assertEq(registry.getAgentWallet(id), alice, "wallet must default to owner");
    }

    // U25: NFT transfer clears the verified wallet (must not persist to new owner).
    function test_Transfer_ClearsAgentWallet() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        (address wallet, uint256 walletPk) = makeAddrAndKey("paymentWallet");
        uint256 deadline = block.timestamp + 60;
        bytes memory sig = _signWallet(id, wallet, alice, deadline, walletPk);
        vm.prank(alice);
        registry.setAgentWallet(id, wallet, deadline, sig);
        // Pin the pre-transfer state so the post-transfer assert isn't vacuous (init defaults to alice).
        assertEq(registry.getAgentWallet(id), wallet, "wallet must be set before transfer");

        vm.prank(alice);
        registry.transferFrom(alice, bob, id);

        assertEq(registry.getAgentWallet(id), address(0), "wallet must clear on transfer");
    }

    // U26: the generic setMetadata cannot spoof the reserved agentWallet key.
    function test_SetMetadata_RevertsOnReservedAgentWalletKey() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        vm.expectRevert(AgentPassport.ReservedMetadataKey.selector);
        vm.prank(alice);
        registry.setMetadata(id, "agentWallet", abi.encodePacked(bob));
    }

    // U29: ERC-1271 wallet that REJECTS the signature -> InvalidWalletSignature (reject path).
    function test_SetAgentWallet_ERC1271_RejectingWallet_Reverts() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        Mock1271Reject scWallet = new Mock1271Reject();
        uint256 deadline = block.timestamp + 60;

        vm.expectRevert(AgentPassport.InvalidWalletSignature.selector);
        vm.prank(alice);
        registry.setAgentWallet(id, address(scWallet), deadline, hex"00");
    }

    // U30: characterizes the (intentional) replay window — no nonce. A signature is replayable
    // within its deadline, INCLUDING re-setting after unset. Matches the canonical reference
    // (replay bounded by owner-binding + 5-min deadline cap). Pinned so a future nonce addition
    // is a deliberate, test-visible change.
    function test_SetAgentWallet_SignatureReplayableWithinDeadline() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        (address wallet, uint256 walletPk) = makeAddrAndKey("paymentWallet");
        uint256 deadline = block.timestamp + 60;
        bytes memory sig = _signWallet(id, wallet, alice, deadline, walletPk);

        vm.prank(alice);
        registry.setAgentWallet(id, wallet, deadline, sig);
        vm.prank(alice);
        registry.unsetAgentWallet(id);
        assertEq(registry.getAgentWallet(id), address(0));

        // Same signature replays successfully before the deadline (no nonce).
        vm.prank(alice);
        registry.setAgentWallet(id, wallet, deadline, sig);
        assertEq(registry.getAgentWallet(id), wallet, "sig is replayable within deadline (no nonce)");
    }

    // U31: after the deadline the same signature no longer works.
    function test_SetAgentWallet_ReplayFailsAfterDeadline() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        (address wallet, uint256 walletPk) = makeAddrAndKey("paymentWallet");
        uint256 deadline = block.timestamp + 60;
        bytes memory sig = _signWallet(id, wallet, alice, deadline, walletPk);
        vm.prank(alice);
        registry.setAgentWallet(id, wallet, deadline, sig);

        vm.warp(deadline + 1);
        vm.expectRevert(abi.encodeWithSelector(AgentPassport.SignatureExpired.selector, deadline));
        vm.prank(alice);
        registry.setAgentWallet(id, wallet, deadline, sig);
    }

    /*//////////////////////////////////////////////////////////////
                       EXISTS / BURN / UNREGISTERED
    //////////////////////////////////////////////////////////////*/

    // U32
    function test_Exists_TrueForRegistered() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);
        assertTrue(registry.exists(id));
    }

    // U33
    function test_Exists_FalseForUnknown() public view {
        assertFalse(registry.exists(999), "unknown id must not exist (no revert)");
    }

    // U34: owner can burn (retire); ownerOf reverts, exists() false, wallet cleared.
    function test_Burn_OwnerCanBurn_ClearsState() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);
        assertEq(registry.getAgentWallet(id), alice);

        vm.prank(alice);
        registry.burn(id);

        assertFalse(registry.exists(id), "burned agent must not exist");
        assertEq(registry.getAgentWallet(id), address(0), "burn must clear the wallet");
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, id));
        registry.ownerOf(id);
    }

    // U35: non-owner cannot burn.
    function test_Burn_RevertsForNonOwner() public {
        vm.prank(alice);
        uint256 id = registry.register(URI1);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, bob, id));
        vm.prank(bob);
        registry.burn(id);
    }

    // U36: reads against an unregistered id are non-reverting sentinels (return zero/empty).
    function test_UnregisteredId_ReadsReturnZeroAndEmpty() public view {
        assertEq(registry.getAgentWallet(12_345), address(0), "unknown wallet -> 0");
        assertEq(registry.getMetadata(12_345, "anything"), bytes(""), "unknown metadata -> empty");
    }

    // U37: mutating an unregistered id reverts via ERC-721 ownership check.
    function test_SetAgentWallet_RevertsForNonexistentAgent() public {
        (address wallet, uint256 walletPk) = makeAddrAndKey("paymentWallet");
        uint256 deadline = block.timestamp + 60;
        bytes memory sig = _signWallet(999, wallet, alice, deadline, walletPk);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999)));
        vm.prank(alice);
        registry.setAgentWallet(999, wallet, deadline, sig);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERFACE / ERRORS
    //////////////////////////////////////////////////////////////*/

    // U16: supportsInterface matches the canonical ERC-8004 reference (ERC-721 detection only).
    // ERC-8004 defines no standardized interfaceId, so we deliberately do NOT advertise a
    // self-derived IIdentityRegistry id (that would be a fake "8004 id" no client checks for).
    function test_SupportsInterface_MatchesCanonicalReference() public view {
        assertTrue(registry.supportsInterface(0x01ffc9a7), "must support ERC-165");
        assertTrue(registry.supportsInterface(0x80ac58cd), "must support ERC-721");
        assertTrue(registry.supportsInterface(0x5b5e139f), "must support ERC-721 Metadata");
        assertTrue(registry.supportsInterface(0x49064906), "must support ERC-4906 (URIStorage)");
        assertFalse(
            registry.supportsInterface(type(IIdentityRegistry).interfaceId),
            "must NOT fake a canonical 8004 interfaceId (none exists)"
        );
        assertFalse(registry.supportsInterface(0xffffffff), "ERC-165: 0xffffffff must be false");
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
        // Budget pinned from R002 gas report (register(string) median ~124k incl. wallet-init
        // SSTORE; short-URI exec gas measured ~114k). Tightened to 125k so a cold-SSTORE-sized
        // regression in a downstream spec actually trips this guard.
        assertLt(gasUsed, 125_000, "register gas over budget");
    }
}

/// @dev Minimal ERC-1271 smart-contract wallet that accepts any signature.
contract Mock1271 {
    function isValidSignature(bytes32, bytes memory) external pure returns (bytes4) {
        return 0x1626ba7e; // ERC-1271 magic value
    }
}

/// @dev ERC-1271 wallet that REJECTS every signature (returns a non-magic value).
contract Mock1271Reject {
    function isValidSignature(bytes32, bytes memory) external pure returns (bytes4) {
        return 0xffffffff;
    }
}

/// @dev Registers itself and inspects the registry's state DURING the _safeMint callback,
///      proving effects are applied before the external interaction (CEI).
contract ReentrantRegistrant is IERC721Receiver {
    AgentPassport public reg;
    uint256 public agentId;
    string public observedURI;
    address public observedWallet;

    constructor(AgentPassport _reg) {
        reg = _reg;
    }

    function doRegister() external {
        agentId = reg.register("ipfs://recv");
    }

    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external returns (bytes4) {
        observedURI = reg.tokenURI(tokenId);
        observedWallet = reg.getAgentWallet(tokenId);
        return IERC721Receiver.onERC721Received.selector;
    }
}
