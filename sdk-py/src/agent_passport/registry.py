"""Synchronous client for the AgentPassport ERC-8004 Identity Registry.

Sync-only by design (see SPEC-R005). Reads need no account; state-changing methods
require an ``eth_account`` ``LocalAccount`` and raise :class:`MissingAccountError`
otherwise.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from eth_utils.address import to_checksum_address
from web3.exceptions import ContractLogicError
from web3.logs import DISCARD

if TYPE_CHECKING:  # pragma: no cover - imports for typing only
    from collections.abc import Sequence

    from eth_account.signers.local import LocalAccount
    from web3 import Web3
    from web3.contract.contract import ContractFunction
    from web3.types import BlockIdentifier, TxReceipt

from .abi import load_abi
from .config import ChainConfig
from .errors import AgentPassportError, ContractRevert, MissingAccountError, raise_for_revert
from .models import AgentIdentity, MetadataEntry, RegisteredAgent

_ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"


class IdentityRegistry:
    """Typed sync wrapper over a deployed AgentPassport contract."""

    def __init__(self, web3: "Web3", address: str, account: "LocalAccount | None" = None) -> None:
        self._w3 = web3
        self._account = account
        self._contract = web3.eth.contract(address=to_checksum_address(address), abi=load_abi())

    @classmethod
    def from_config(cls, config: ChainConfig, account: "LocalAccount | None" = None) -> "IdentityRegistry":
        from web3 import Web3

        web3 = Web3(Web3.HTTPProvider(config.rpc_url))
        return cls(web3, config.contract_address, account)

    # ------------------------------------------------------------------ reads
    def exists(self, agent_id: int) -> bool:
        result: bool = self._contract.functions.exists(agent_id).call()
        return result

    def owner_of(self, agent_id: int) -> str:
        return to_checksum_address(self._contract.functions.ownerOf(agent_id).call())

    def agent_uri(self, agent_id: int) -> str:
        result: str = self._contract.functions.tokenURI(agent_id).call()
        return result

    def get_metadata(self, agent_id: int, key: str) -> bytes:
        result: bytes = self._contract.functions.getMetadata(agent_id, key).call()
        return result

    def get_agent_wallet(self, agent_id: int) -> str | None:
        wallet = to_checksum_address(self._contract.functions.getAgentWallet(agent_id).call())
        return None if wallet == _ZERO_ADDRESS else wallet

    def get_identity(self, agent_id: int) -> AgentIdentity:
        if not self.exists(agent_id):
            raise AgentPassportError(f"agent {agent_id} is not registered")
        return AgentIdentity(
            agent_id=agent_id,
            owner=self.owner_of(agent_id),
            agent_uri=self.agent_uri(agent_id),
            agent_wallet=self.get_agent_wallet(agent_id),
        )

    def list_registered(
        self, from_block: "BlockIdentifier" = 0, to_block: "BlockIdentifier" = "latest"
    ) -> list[RegisteredAgent]:
        logs = self._contract.events.Registered().get_logs(from_block=from_block, to_block=to_block)
        return [
            RegisteredAgent(
                agent_id=int(log["args"]["agentId"]),
                owner=to_checksum_address(log["args"]["owner"]),
                agent_uri=log["args"]["agentURI"],
            )
            for log in logs
        ]

    # ----------------------------------------------------------------- writes
    def register(
        self, agent_uri: str | None = None, metadata: "Sequence[MetadataEntry] | None" = None
    ) -> int:
        fns = self._contract.functions
        if metadata:
            if agent_uri is None:
                raise ValueError("agent_uri is required when metadata is provided")
            entries = [(m.key, m.value) for m in metadata]
            call = fns.register(agent_uri, entries)
        elif agent_uri is not None:
            call = fns.register(agent_uri)
        else:
            call = fns.register()
        receipt = self._send(call)
        # DISCARD: a register receipt also carries Transfer/MetadataSet logs; only
        # decode the Registered ones instead of warning on every mismatch.
        events = self._contract.events.Registered().process_receipt(receipt, errors=DISCARD)
        return int(events[0]["args"]["agentId"])

    def set_agent_uri(self, agent_id: int, new_uri: str) -> str:
        receipt = self._send(self._contract.functions.setAgentURI(agent_id, new_uri))
        return self._w3.to_hex(receipt["transactionHash"])

    def set_metadata(self, agent_id: int, key: str, value: bytes) -> str:
        receipt = self._send(self._contract.functions.setMetadata(agent_id, key, value))
        return self._w3.to_hex(receipt["transactionHash"])

    def set_agent_wallet(self, agent_id: int, new_wallet: str, signature: bytes, deadline: int) -> str:
        call = self._contract.functions.setAgentWallet(
            agent_id, to_checksum_address(new_wallet), deadline, signature
        )
        receipt = self._send(call)
        return self._w3.to_hex(receipt["transactionHash"])

    def unset_agent_wallet(self, agent_id: int) -> str:
        receipt = self._send(self._contract.functions.unsetAgentWallet(agent_id))
        return self._w3.to_hex(receipt["transactionHash"])

    # --------------------------------------------------------------- internal
    def _require_account(self) -> "LocalAccount":
        if self._account is None:
            raise MissingAccountError("this operation requires an account; construct with account=...")
        return self._account

    def _send(self, call: "ContractFunction") -> "TxReceipt":
        """Build, sign, send a state-changing call and wait for its receipt.

        Reverts surface during gas estimation (``build_transaction`` does an
        ``eth_call``) and are mapped to typed exceptions; no silent fallback.
        """
        account = self._require_account()
        try:
            tx = call.build_transaction(
                {
                    "from": account.address,
                    "nonce": self._w3.eth.get_transaction_count(account.address),
                    "chainId": self._w3.eth.chain_id,
                }
            )
        except ContractLogicError as exc:
            _map_revert(exc)
        # web3's TxParams TypedDict and eth_account's expected transaction dict are
        # structurally compatible at runtime; their stubs just don't agree.
        signed = account.sign_transaction(tx)  # type: ignore[arg-type]
        tx_hash = self._w3.eth.send_raw_transaction(signed.raw_transaction)
        receipt = self._w3.eth.wait_for_transaction_receipt(tx_hash)
        if receipt["status"] != 1:
            raise ContractRevert("0x")
        return receipt


def _map_revert(exc: ContractLogicError) -> Any:
    """Translate a web3 revert into a typed SDK exception (or re-raise as-is)."""
    data = getattr(exc, "data", None)
    if isinstance(data, (bytes, bytearray)):
        data = "0x" + bytes(data).hex()
    if isinstance(data, str) and data.startswith("0x"):
        raise_for_revert(data)
    raise exc
