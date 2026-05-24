"""EIP-712 helpers for authorizing an agent wallet.

`setAgentWallet` requires a signature from the **new wallet** itself (EOA via
EIP-712, or a smart-contract wallet via ERC-1271). The current NFT **owner** then
submits the transaction. This module builds the typed-data and signs it as an EOA.

Domain and type hash mirror the contract verbatim:
  domain  = ("ERC8004IdentityRegistry", "1", chainId, verifyingContract)
  typehash = AgentWalletSet(uint256 agentId,address newWallet,address owner,uint256 deadline)
"""

from __future__ import annotations

import time
from typing import Any

from eth_account import Account
from eth_account.messages import encode_typed_data
from eth_account.signers.local import LocalAccount
from eth_utils.address import to_checksum_address

# Contract constant: MAX_WALLET_SIG_DELAY. The deadline must be in the future AND
# within this window of `now`. We default below it to leave clock-skew headroom.
MAX_WALLET_SIG_DELAY = 5 * 60
_DEFAULT_DELAY = 4 * 60


def default_deadline() -> int:
    """A deadline `_DEFAULT_DELAY` seconds out — safely under the contract's cap."""
    return int(time.time()) + _DEFAULT_DELAY


def build_typed_data(
    *,
    agent_id: int,
    new_wallet: str,
    owner: str,
    deadline: int,
    contract_address: str,
    chain_id: int,
) -> dict[str, Any]:
    """Assemble the EIP-712 typed-data document for an `AgentWalletSet` authorization."""
    return {
        "types": {
            "EIP712Domain": [
                {"name": "name", "type": "string"},
                {"name": "version", "type": "string"},
                {"name": "chainId", "type": "uint256"},
                {"name": "verifyingContract", "type": "address"},
            ],
            "AgentWalletSet": [
                {"name": "agentId", "type": "uint256"},
                {"name": "newWallet", "type": "address"},
                {"name": "owner", "type": "address"},
                {"name": "deadline", "type": "uint256"},
            ],
        },
        "primaryType": "AgentWalletSet",
        "domain": {
            "name": "ERC8004IdentityRegistry",
            "version": "1",
            "chainId": chain_id,
            "verifyingContract": to_checksum_address(contract_address),
        },
        "message": {
            "agentId": agent_id,
            "newWallet": to_checksum_address(new_wallet),
            "owner": to_checksum_address(owner),
            "deadline": deadline,
        },
    }


def sign_agent_wallet(
    wallet: LocalAccount,
    *,
    agent_id: int,
    owner: str,
    deadline: int,
    contract_address: str,
    chain_id: int,
) -> bytes:
    """Sign an `AgentWalletSet` authorization as the new wallet (EOA).

    `new_wallet` is `wallet.address` — a wallet authorizes its own assignment.
    Returns the 65-byte signature to pass to `IdentityRegistry.set_agent_wallet`.
    """
    typed = build_typed_data(
        agent_id=agent_id,
        new_wallet=wallet.address,
        owner=owner,
        deadline=deadline,
        contract_address=contract_address,
        chain_id=chain_id,
    )
    signable = encode_typed_data(full_message=typed)
    signed = Account.sign_message(signable, wallet.key)
    return bytes(signed.signature)
