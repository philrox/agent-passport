"""Synchronous client for the AgentPassport ERC-8004 Identity Registry.

Sync-only by design (see SPEC-R005). Reads need no account; state-changing methods
require an ``eth_account`` ``LocalAccount`` and raise :class:`MissingAccountError`
otherwise.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:  # pragma: no cover - imports for typing only
    from collections.abc import Sequence

    from eth_account.signers.local import LocalAccount
    from web3 import Web3
    from web3.types import BlockIdentifier

from .abi import load_abi
from .config import ChainConfig
from .errors import MissingAccountError
from .models import AgentIdentity, MetadataEntry, RegisteredAgent

_ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"


class IdentityRegistry:
    """Typed sync wrapper over a deployed AgentPassport contract."""

    def __init__(self, web3: "Web3", address: str, account: "LocalAccount | None" = None) -> None:
        from eth_utils import to_checksum_address

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
        raise NotImplementedError

    def owner_of(self, agent_id: int) -> str:
        raise NotImplementedError

    def agent_uri(self, agent_id: int) -> str:
        raise NotImplementedError

    def get_metadata(self, agent_id: int, key: str) -> bytes:
        raise NotImplementedError

    def get_agent_wallet(self, agent_id: int) -> str | None:
        raise NotImplementedError

    def get_identity(self, agent_id: int) -> AgentIdentity:
        raise NotImplementedError

    def list_registered(
        self, from_block: "BlockIdentifier" = 0, to_block: "BlockIdentifier" = "latest"
    ) -> list[RegisteredAgent]:
        raise NotImplementedError

    # ----------------------------------------------------------------- writes
    def register(
        self, agent_uri: str | None = None, metadata: "Sequence[MetadataEntry] | None" = None
    ) -> int:
        raise NotImplementedError

    def set_agent_uri(self, agent_id: int, new_uri: str) -> str:
        raise NotImplementedError

    def set_metadata(self, agent_id: int, key: str, value: bytes) -> str:
        raise NotImplementedError

    def set_agent_wallet(self, agent_id: int, new_wallet: str, signature: bytes, deadline: int) -> str:
        raise NotImplementedError

    def unset_agent_wallet(self, agent_id: int) -> str:
        raise NotImplementedError

    # --------------------------------------------------------------- internal
    def _require_account(self) -> "LocalAccount":
        if self._account is None:
            raise MissingAccountError("this operation requires an account; construct with account=...")
        return self._account
