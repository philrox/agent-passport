"""Network configuration. No network is hardcoded — the caller injects RPC, the
deployed contract address, and the chain id (Arc testnet, anvil, a fork, ...)."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field

from .models import Address


class ChainConfig(BaseModel):
    """Everything needed to bind the SDK to a deployed AgentPassport instance."""

    model_config = ConfigDict(frozen=True)

    rpc_url: str
    contract_address: Address
    chain_id: int = Field(gt=0)
