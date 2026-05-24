"""Enumeration: list_registered() reads Registered logs (the contract is NOT
ERC721Enumerable, so log-reading is the only way to list all agents)."""

from __future__ import annotations

import pytest

from agent_passport import IdentityRegistry, RegisteredAgent


@pytest.fixture
def owner_registry(w3, contract_address, accounts) -> IdentityRegistry:
    return IdentityRegistry(w3, contract_address, account=accounts[0])


def test_list_registered_empty(owner_registry: IdentityRegistry) -> None:
    assert owner_registry.list_registered() == []


def test_list_registered_returns_all(owner_registry: IdentityRegistry, accounts) -> None:
    owner_registry.register("ipfs://a")
    owner_registry.register("ipfs://b")
    owner_registry.register("ipfs://c")

    agents = owner_registry.list_registered()

    assert [a.agent_id for a in agents] == [1, 2, 3]
    assert [a.agent_uri for a in agents] == ["ipfs://a", "ipfs://b", "ipfs://c"]
    assert all(isinstance(a, RegisteredAgent) for a in agents)
    assert all(a.owner == accounts[0].address for a in agents)


def test_list_registered_captures_owner_per_agent(w3, contract_address, accounts) -> None:
    IdentityRegistry(w3, contract_address, account=accounts[0]).register("ipfs://a")
    IdentityRegistry(w3, contract_address, account=accounts[1]).register("ipfs://b")

    agents = IdentityRegistry(w3, contract_address).list_registered()

    by_id = {a.agent_id: a.owner for a in agents}
    assert by_id == {1: accounts[0].address, 2: accounts[1].address}
