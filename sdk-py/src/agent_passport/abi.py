"""Loader for the pinned AgentPassport ABI shipped inside the package.

The ABI is vendored at build time (see ``make sync-abi``) so the SDK installs and
runs standalone — without the Foundry toolchain or the contracts repo present.
"""

from __future__ import annotations

import json
from functools import lru_cache
from importlib import resources
from typing import Any


@lru_cache(maxsize=1)
def load_abi() -> list[dict[str, Any]]:
    """Return the AgentPassport contract ABI as a list of ABI entries."""
    # NB: load via the top-level package + joinpath, not `agent_passport.abi` — the
    # latter would import the sibling module `abi.py` (name collision), not the data dir.
    raw = resources.files("agent_passport").joinpath("abi", "AgentPassport.json").read_text()
    abi: list[dict[str, Any]] = json.loads(raw)
    return abi
