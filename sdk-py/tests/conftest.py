"""Test harness: a real anvil node with a freshly deployed AgentPassport.

We deploy the actual compiled bytecode (from the Foundry artifact) and drive it
through the SDK, so tests exercise real ABI encode/decode and event-topic parsing —
not mocks. A fresh contract per test keeps agentId auto-increment deterministic.
"""

from __future__ import annotations

import json
import socket
import subprocess
import time
from pathlib import Path
from typing import Iterator

import pytest
from eth_account import Account
from eth_account.signers.local import LocalAccount
from web3 import Web3

# Well-known Foundry/anvil default dev keys (public test vectors, not secrets).
_ANVIL_KEYS = [
    "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
    "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
    "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
]
_ARTIFACT = (
    Path(__file__).resolve().parents[2] / "contracts" / "out" / "AgentPassport.sol" / "AgentPassport.json"
)


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


@pytest.fixture(scope="session")
def anvil() -> Iterator[str]:
    """Start an anvil node for the test session; yield its RPC URL."""
    port = _free_port()
    proc = subprocess.Popen(
        ["anvil", "--port", str(port), "--silent"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    rpc = f"http://127.0.0.1:{port}"
    try:
        w3 = Web3(Web3.HTTPProvider(rpc))
        for _ in range(100):
            if w3.is_connected():
                break
            time.sleep(0.1)
        else:
            raise RuntimeError("anvil did not start in time")
        yield rpc
    finally:
        proc.terminate()
        proc.wait(timeout=10)


@pytest.fixture(scope="session")
def chain_id(anvil: str) -> int:
    return Web3(Web3.HTTPProvider(anvil)).eth.chain_id


@pytest.fixture
def accounts() -> list[LocalAccount]:
    return [Account.from_key(k) for k in _ANVIL_KEYS]


@pytest.fixture
def w3(anvil: str) -> Web3:
    return Web3(Web3.HTTPProvider(anvil))


def _send(w3: Web3, account: LocalAccount, tx: dict) -> dict:
    tx.setdefault("from", account.address)
    tx.setdefault("nonce", w3.eth.get_transaction_count(account.address))
    tx.setdefault("chainId", w3.eth.chain_id)
    signed = account.sign_transaction(tx)
    tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
    return dict(w3.eth.wait_for_transaction_receipt(tx_hash))


@pytest.fixture
def contract_address(w3: Web3, accounts: list[LocalAccount]) -> str:
    """Deploy a fresh AgentPassport and return its address."""
    artifact = json.loads(_ARTIFACT.read_text())
    factory = w3.eth.contract(abi=artifact["abi"], bytecode=artifact["bytecode"]["object"])
    deployer = accounts[0]
    tx = factory.constructor().build_transaction(
        {"from": deployer.address, "nonce": w3.eth.get_transaction_count(deployer.address)}
    )
    receipt = _send(w3, deployer, tx)
    return Web3.to_checksum_address(receipt["contractAddress"])
