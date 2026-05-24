"""Custom-error decoding: contract reverts surface as specific typed exceptions
with their decoded arguments, never swallowed."""

from __future__ import annotations

import pytest

from agent_passport import IdentityRegistry, NotAgentOwner, ReservedMetadataKey


def test_non_owner_set_metadata_raises_not_agent_owner(w3, contract_address, accounts) -> None:
    owner = IdentityRegistry(w3, contract_address, account=accounts[0])
    stranger = IdentityRegistry(w3, contract_address, account=accounts[1])
    agent_id = owner.register("ipfs://card")

    with pytest.raises(NotAgentOwner) as exc_info:
        stranger.set_metadata(agent_id, "venue", b"x")

    assert exc_info.value.agent_id == agent_id
    assert exc_info.value.caller == accounts[1].address


def test_reserved_metadata_key_raises(w3, contract_address, accounts) -> None:
    owner = IdentityRegistry(w3, contract_address, account=accounts[0])
    agent_id = owner.register("ipfs://card")

    with pytest.raises(ReservedMetadataKey):
        owner.set_metadata(agent_id, "agentWallet", b"\x00" * 20)
