"""Agent Passport — Python SDK for the ERC-8004 Identity Registry."""

from __future__ import annotations

from .config import ChainConfig
from .eip712 import build_typed_data, default_deadline, sign_agent_wallet
from .errors import (
    AgentPassportError,
    ContractRevert,
    DeadlineTooFar,
    InvalidWalletSignature,
    MissingAccountError,
    NotAgentOwner,
    ReservedMetadataKey,
    SignatureExpired,
)
from .models import Address, AgentIdentity, MetadataEntry, RegisteredAgent
from .registry import IdentityRegistry

__all__ = [
    "ChainConfig",
    "IdentityRegistry",
    "MetadataEntry",
    "RegisteredAgent",
    "AgentIdentity",
    "Address",
    "build_typed_data",
    "sign_agent_wallet",
    "default_deadline",
    "AgentPassportError",
    "MissingAccountError",
    "ContractRevert",
    "NotAgentOwner",
    "SignatureExpired",
    "DeadlineTooFar",
    "InvalidWalletSignature",
    "ReservedMetadataKey",
]
