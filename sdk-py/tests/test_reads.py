"""Read-path: exists / owner_of / agent_uri / get_metadata / get_agent_wallet / get_identity.

These drive a freshly deployed contract. Writes used to set up state go through the
SDK's own write methods, so the read tests also implicitly prove the write path round-trips.
"""

from __future__ import annotations

import pytest

from agent_passport import AgentPassportError, IdentityRegistry, MetadataEntry


@pytest.fixture
def owner_registry(w3, contract_address, accounts) -> IdentityRegistry:
    return IdentityRegistry(w3, contract_address, account=accounts[0])


def test_exists_false_for_unregistered(owner_registry: IdentityRegistry) -> None:
    assert owner_registry.exists(1) is False


def test_exists_true_after_register(owner_registry: IdentityRegistry) -> None:
    agent_id = owner_registry.register("ipfs://card-1")
    assert owner_registry.exists(agent_id) is True


def test_register_assigns_incrementing_ids_from_one(owner_registry: IdentityRegistry) -> None:
    first = owner_registry.register("ipfs://a")
    second = owner_registry.register("ipfs://b")
    assert (first, second) == (1, 2)


def test_owner_of_returns_registrant(owner_registry: IdentityRegistry, accounts) -> None:
    agent_id = owner_registry.register("ipfs://card")
    assert owner_registry.owner_of(agent_id) == accounts[0].address


def test_agent_uri_round_trips(owner_registry: IdentityRegistry) -> None:
    agent_id = owner_registry.register("ipfs://my-card")
    assert owner_registry.agent_uri(agent_id) == "ipfs://my-card"


def test_get_metadata_round_trips(owner_registry: IdentityRegistry) -> None:
    agent_id = owner_registry.register("ipfs://card", [MetadataEntry(key="venue", value=b"polymarket")])
    assert owner_registry.get_metadata(agent_id, "venue") == b"polymarket"


def test_get_metadata_unknown_key_is_empty(owner_registry: IdentityRegistry) -> None:
    agent_id = owner_registry.register("ipfs://card")
    assert owner_registry.get_metadata(agent_id, "missing") == b""


def test_get_agent_wallet_defaults_to_owner_on_register(
    owner_registry: IdentityRegistry, accounts
) -> None:
    # The contract defaults the agent wallet to the registrant at registration.
    agent_id = owner_registry.register("ipfs://card")
    assert owner_registry.get_agent_wallet(agent_id) == accounts[0].address


def test_get_identity_composes_view(owner_registry: IdentityRegistry, accounts) -> None:
    agent_id = owner_registry.register("ipfs://card")
    identity = owner_registry.get_identity(agent_id)
    assert identity.agent_id == agent_id
    assert identity.owner == accounts[0].address
    assert identity.agent_uri == "ipfs://card"
    assert identity.agent_wallet == accounts[0].address


def test_get_identity_unknown_agent_raises(owner_registry: IdentityRegistry) -> None:
    with pytest.raises(AgentPassportError):
        owner_registry.get_identity(999)
