"""Pydantic v2 models for the public SDK boundary.

Typed boundaries everywhere: no raw ``dict``/``str`` addresses cross the public API.
Addresses are validated and EIP-55 checksummed on the way in.
"""

from __future__ import annotations

from typing import Annotated

from eth_utils.address import to_checksum_address
from pydantic import AfterValidator, BaseModel, ConfigDict, Field

__all__ = ["Address", "MetadataEntry", "RegisteredAgent", "AgentIdentity"]


def _checksum(value: str) -> str:
    """Validate a hex address and return its EIP-55 checksummed form."""
    return to_checksum_address(value)


# A 0x-prefixed, EIP-55 checksummed Ethereum address. Validation rejects malformed
# input at the boundary; the stored value is always checksummed.
Address = Annotated[str, AfterValidator(_checksum)]


class MetadataEntry(BaseModel):
    """A single off-chain-extensible metadata entry (key -> raw bytes value)."""

    model_config = ConfigDict(frozen=True)

    key: str
    value: bytes


class RegisteredAgent(BaseModel):
    """One decoded ``Registered`` event log."""

    model_config = ConfigDict(frozen=True)

    agent_id: int = Field(ge=1)
    owner: Address
    agent_uri: str


class AgentIdentity(BaseModel):
    """Composed identity view assembled from on-chain read calls."""

    model_config = ConfigDict(frozen=True)

    agent_id: int = Field(ge=1)
    owner: Address
    agent_uri: str
    agent_wallet: Address | None
