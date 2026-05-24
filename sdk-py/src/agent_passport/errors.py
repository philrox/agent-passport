"""Typed exceptions for the SDK, plus decoding of contract custom-error reverts.

No silent fallbacks: every contract revert we recognise becomes a specific Python
exception; unrecognised reverts surface as :class:`ContractRevert` carrying the raw
data, never swallowed.
"""

from __future__ import annotations

from typing import NoReturn

from eth_abi.abi import decode as abi_decode
from eth_utils.abi import function_signature_to_4byte_selector
from eth_utils.address import to_checksum_address

__all__ = [
    "AgentPassportError",
    "MissingAccountError",
    "ContractRevert",
    "NotAgentOwner",
    "SignatureExpired",
    "DeadlineTooFar",
    "InvalidWalletSignature",
    "ReservedMetadataKey",
]


class AgentPassportError(Exception):
    """Base class for all SDK errors."""


class MissingAccountError(AgentPassportError):
    """Raised when a state-changing method is called on a read-only client."""


class ContractRevert(AgentPassportError):
    """A contract revert the SDK does not map to a more specific exception."""

    def __init__(self, data: str) -> None:
        super().__init__(f"unrecognised contract revert: {data}")
        self.data = data


class NotAgentOwner(AgentPassportError):
    """The caller does not own the agent for an owner-gated operation."""

    def __init__(self, agent_id: int, caller: str) -> None:
        super().__init__(f"caller {caller} does not own agent {agent_id}")
        self.agent_id = agent_id
        self.caller = caller


class SignatureExpired(AgentPassportError):
    """A wallet-set signature's deadline is in the past."""

    def __init__(self, deadline: int) -> None:
        super().__init__(f"wallet-set signature expired at {deadline}")
        self.deadline = deadline


class DeadlineTooFar(AgentPassportError):
    """A wallet-set deadline exceeds the contract's 5-minute forward window."""

    def __init__(self, deadline: int) -> None:
        super().__init__(f"wallet-set deadline {deadline} exceeds the 5-minute window")
        self.deadline = deadline


class InvalidWalletSignature(AgentPassportError):
    """The wallet-set signature is not valid for the new wallet."""


class ReservedMetadataKey(AgentPassportError):
    """setMetadata targeted a contract-reserved key (e.g. ``agentWallet``)."""


# Map each custom-error 4-byte selector to a builder that turns the decoded ABI
# arguments into the corresponding typed exception.
def _selector(signature: str) -> bytes:
    return function_signature_to_4byte_selector(signature)


_DECODERS: dict[bytes, tuple[list[str], object]] = {
    _selector("NotAgentOwner(uint256,address)"): (
        ["uint256", "address"],
        lambda agent_id, caller: NotAgentOwner(agent_id, to_checksum_address(caller)),
    ),
    _selector("SignatureExpired(uint256)"): (["uint256"], lambda d: SignatureExpired(d)),
    _selector("DeadlineTooFar(uint256)"): (["uint256"], lambda d: DeadlineTooFar(d)),
    _selector("InvalidWalletSignature()"): ([], lambda: InvalidWalletSignature()),
    _selector("ReservedMetadataKey()"): ([], lambda: ReservedMetadataKey()),
}


def raise_for_revert(revert_data: str | None) -> NoReturn:
    """Map raw revert data (``0x`` + selector + args) to a typed exception and raise.

    Falls back to :class:`ContractRevert` for any selector we do not recognise.
    """
    if not revert_data or not revert_data.startswith("0x") or len(revert_data) < 10:
        raise ContractRevert(revert_data or "0x")

    raw = bytes.fromhex(revert_data[2:])
    selector, payload = raw[:4], raw[4:]
    entry = _DECODERS.get(selector)
    if entry is None:
        raise ContractRevert(revert_data)

    arg_types, builder = entry
    args = abi_decode(arg_types, payload) if arg_types else ()
    raise builder(*args)  # type: ignore[operator]  # builder arity matches arg_types by construction
