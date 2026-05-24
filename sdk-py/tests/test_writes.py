"""Write-path: set_agent_uri / set_metadata, register overloads, account requirement."""

from __future__ import annotations

import pytest

from agent_passport import IdentityRegistry, MissingAccountError


@pytest.fixture
def owner_registry(w3, contract_address, accounts) -> IdentityRegistry:
    return IdentityRegistry(w3, contract_address, account=accounts[0])


@pytest.fixture
def readonly_registry(w3, contract_address) -> IdentityRegistry:
    return IdentityRegistry(w3, contract_address)


def test_set_agent_uri_updates(owner_registry: IdentityRegistry) -> None:
    agent_id = owner_registry.register("ipfs://old")
    owner_registry.set_agent_uri(agent_id, "ipfs://new")
    assert owner_registry.agent_uri(agent_id) == "ipfs://new"


def test_set_metadata_writes_value(owner_registry: IdentityRegistry) -> None:
    agent_id = owner_registry.register("ipfs://card")
    owner_registry.set_metadata(agent_id, "venue", b"hyperliquid")
    assert owner_registry.get_metadata(agent_id, "venue") == b"hyperliquid"


def test_set_metadata_empty_value_clears(owner_registry: IdentityRegistry) -> None:
    agent_id = owner_registry.register("ipfs://card")
    owner_registry.set_metadata(agent_id, "venue", b"polymarket")
    owner_registry.set_metadata(agent_id, "venue", b"")
    assert owner_registry.get_metadata(agent_id, "venue") == b""


def test_register_no_uri_overload(owner_registry: IdentityRegistry) -> None:
    agent_id = owner_registry.register()
    assert owner_registry.exists(agent_id) is True
    assert owner_registry.agent_uri(agent_id) == ""


def test_set_agent_uri_returns_tx_hash(owner_registry: IdentityRegistry) -> None:
    agent_id = owner_registry.register("ipfs://card")
    tx_hash = owner_registry.set_agent_uri(agent_id, "ipfs://v2")
    assert isinstance(tx_hash, str) and tx_hash.startswith("0x") and len(tx_hash) == 66


def test_write_without_account_raises(readonly_registry: IdentityRegistry) -> None:
    with pytest.raises(MissingAccountError):
        readonly_registry.set_metadata(1, "venue", b"x")
