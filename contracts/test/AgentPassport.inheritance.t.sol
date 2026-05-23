// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentPassport} from "../src/AgentPassport.sol";

/// @notice Proves R002 (ERC-8004 layer) can inherit AgentPassport and access `_agents`
///         directly — and that adding subclass state does not displace the parent's
///         slot 0. Compile failure of this file means the R002 inheritance contract
///         is broken; do NOT silence by lowering visibility.
contract AgentPassportInheritanceHarness is AgentPassport {
    // Subclass-only state added AFTER parent storage. MUST land in slot 1 (after _agents).
    mapping(bytes32 => uint256) internal _subclassTokenIds;

    /// @notice Exposes the parent's `_agents` mapping — would fail to compile if
    ///         the parent's mapping were `private`.
    function readOwnerInternal(bytes32 id) external view returns (address) {
        return _agents[id].owner;
    }

    function setSubclassTokenId(bytes32 id, uint256 tokenId) external {
        _subclassTokenIds[id] = tokenId;
    }

    function getSubclassTokenId(bytes32 id) external view returns (uint256) {
        return _subclassTokenIds[id];
    }
}

contract AgentPassportInheritanceTest is Test {
    AgentPassportInheritanceHarness internal harness;

    address internal alice = makeAddr("alice");
    address internal payment = makeAddr("payment");

    function setUp() public {
        harness = new AgentPassportInheritanceHarness();
    }

    function test_Subclass_CanReadInternal_AgentsMapping() public {
        bytes32 id = bytes32(uint256(0x1));
        vm.prank(alice);
        harness.registerAgent(id, "name", "endpoint", payment, "uri");

        assertEq(harness.readOwnerInternal(id), alice, "internal _agents accessible from subclass");
    }

    function test_Subclass_PreservesParentSlot0_ForAgentsMapping() public {
        // After registration, the AgentCard for `id` MUST live under
        // keccak256(abi.encode(id, 0)) — proving _agents is still at parent slot 0
        // even after the subclass added its own `_subclassTokenIds` mapping.
        bytes32 id = bytes32(uint256(0xCAFE));
        vm.prank(alice);
        harness.registerAgent(id, "n", "e", payment, "u");

        bytes32 root = keccak256(abi.encode(id, uint256(0)));
        bytes32 s0 = vm.load(address(harness), root);
        assertEq(address(uint160(uint256(s0))), alice, "_agents must stay at parent slot 0");
    }

    function test_Subclass_AppendedStorage_LandsInOwnSlot() public {
        // Symmetrical check: subclass's _subclassTokenIds is the FIRST state var
        // declared after AgentPassport — it MUST occupy slot 1.
        bytes32 id = bytes32(uint256(0xBEEF));
        harness.setSubclassTokenId(id, 42);

        // _subclassTokenIds at slot 1; storage[keccak256(abi.encode(id, 1))] == 42
        bytes32 slot = keccak256(abi.encode(id, uint256(1)));
        assertEq(uint256(vm.load(address(harness), slot)), 42, "subclass mapping at slot 1");
        assertEq(harness.getSubclassTokenId(id), 42);
    }
}
