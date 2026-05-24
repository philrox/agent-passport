"""Agent-wallet path: EIP-712 sign (by the new wallet) -> set (by the owner) ->
get -> unset, plus the contract's signature/deadline guard reverts."""

from __future__ import annotations

import time

import pytest

from agent_passport import (
    DeadlineTooFar,
    IdentityRegistry,
    InvalidWalletSignature,
    SignatureExpired,
    default_deadline,
    sign_agent_wallet,
)


@pytest.fixture
def owner_registry(w3, contract_address, accounts) -> IdentityRegistry:
    return IdentityRegistry(w3, contract_address, account=accounts[0])


def test_set_agent_wallet_round_trip(owner_registry, contract_address, chain_id, accounts) -> None:
    owner, new_wallet = accounts[0], accounts[1]
    agent_id = owner_registry.register("ipfs://card")
    deadline = default_deadline()
    signature = sign_agent_wallet(
        new_wallet,
        agent_id=agent_id,
        owner=owner.address,
        deadline=deadline,
        contract_address=contract_address,
        chain_id=chain_id,
    )
    owner_registry.set_agent_wallet(agent_id, new_wallet.address, signature, deadline)
    assert owner_registry.get_agent_wallet(agent_id) == new_wallet.address


def test_unset_agent_wallet(owner_registry, contract_address, chain_id, accounts) -> None:
    owner, new_wallet = accounts[0], accounts[1]
    agent_id = owner_registry.register("ipfs://card")
    deadline = default_deadline()
    signature = sign_agent_wallet(
        new_wallet,
        agent_id=agent_id,
        owner=owner.address,
        deadline=deadline,
        contract_address=contract_address,
        chain_id=chain_id,
    )
    owner_registry.set_agent_wallet(agent_id, new_wallet.address, signature, deadline)
    owner_registry.unset_agent_wallet(agent_id)
    assert owner_registry.get_agent_wallet(agent_id) is None


def test_expired_deadline_raises(owner_registry, contract_address, chain_id, accounts) -> None:
    owner, new_wallet = accounts[0], accounts[1]
    agent_id = owner_registry.register("ipfs://card")
    deadline = int(time.time()) - 60
    signature = sign_agent_wallet(
        new_wallet, agent_id=agent_id, owner=owner.address, deadline=deadline,
        contract_address=contract_address, chain_id=chain_id,
    )
    with pytest.raises(SignatureExpired):
        owner_registry.set_agent_wallet(agent_id, new_wallet.address, signature, deadline)


def test_deadline_too_far_raises(owner_registry, contract_address, chain_id, accounts) -> None:
    owner, new_wallet = accounts[0], accounts[1]
    agent_id = owner_registry.register("ipfs://card")
    deadline = int(time.time()) + 60 * 60  # 1h, well beyond the 5-min cap
    signature = sign_agent_wallet(
        new_wallet, agent_id=agent_id, owner=owner.address, deadline=deadline,
        contract_address=contract_address, chain_id=chain_id,
    )
    with pytest.raises(DeadlineTooFar):
        owner_registry.set_agent_wallet(agent_id, new_wallet.address, signature, deadline)


def test_wrong_signer_raises_invalid_signature(
    owner_registry, contract_address, chain_id, accounts
) -> None:
    owner, claimed_wallet, wrong_signer = accounts[0], accounts[1], accounts[2]
    agent_id = owner_registry.register("ipfs://card")
    deadline = default_deadline()
    # wrong_signer signs (so the signature authorizes accounts[2]), but we submit
    # claimed_wallet (accounts[1]) as newWallet -> signature invalid for newWallet.
    signature = sign_agent_wallet(
        wrong_signer, agent_id=agent_id, owner=owner.address, deadline=deadline,
        contract_address=contract_address, chain_id=chain_id,
    )
    with pytest.raises(InvalidWalletSignature):
        owner_registry.set_agent_wallet(agent_id, claimed_wallet.address, signature, deadline)
