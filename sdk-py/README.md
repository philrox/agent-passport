# agent-passport (Python SDK)

Python SDK for the **Agent Passport** ERC-8004 Identity Registry. Register agents,
read identity/metadata, set the agent wallet (EIP-712), and enumerate all registered
agents — from a deployed `AgentPassport` contract.

Sync-only, [Pydantic v2](https://docs.pydantic.dev/) typed boundaries,
[web3.py](https://web3py.readthedocs.io/) under the hood. Scope: the ERC-8004
**Identity Registry** (R002). Jobs/Receipts modules arrive with R003/R004.

## Install

```bash
uv pip install -e .          # from agent-passport/sdk-py
# or, once published:  pip install agent-passport
```

## Quickstart (against a local anvil)

```bash
anvil &                       # local dev chain on :8545
# deploy AgentPassport with your usual forge script, note the address
```

```python
from eth_account import Account
from agent_passport import ChainConfig, IdentityRegistry, MetadataEntry

acct = Account.from_key("0x...")  # the registrant / owner
reg = IdentityRegistry.from_config(
    ChainConfig(
        rpc_url="http://127.0.0.1:8545",
        contract_address="0xYourAgentPassport",
        chain_id=31337,
    ),
    account=acct,
)

# Register an agent (returns its uint256 agentId)
agent_id = reg.register("ipfs://agent-card.json", [MetadataEntry(key="venue", value=b"polymarket")])

# Read it back
print(reg.exists(agent_id))                 # True
print(reg.agent_uri(agent_id))              # ipfs://agent-card.json
print(reg.get_metadata(agent_id, "venue"))  # b"polymarket"
print(reg.get_identity(agent_id))           # AgentIdentity(...)

# Enumerate every registered agent (reads Registered logs — the contract is
# NOT ERC721Enumerable, so this is the only way to list them)
for a in reg.list_registered():
    print(a.agent_id, a.owner, a.agent_uri)
```

### Setting the agent wallet (EIP-712)

The **new wallet** authorizes its own assignment by signing; the **owner** submits
the transaction.

```python
from agent_passport import sign_agent_wallet, default_deadline

deadline = default_deadline()                 # now + 4 min (contract cap is 5 min)
signature = sign_agent_wallet(
    new_wallet_account,                        # signs as the new wallet
    agent_id=agent_id,
    owner=acct.address,                        # current NFT owner
    deadline=deadline,
    contract_address=reg_address,
    chain_id=31337,
)
reg.set_agent_wallet(agent_id, new_wallet_account.address, signature, deadline)
print(reg.get_agent_wallet(agent_id))          # new wallet
```

## Public surface

| Method | Kind | Returns |
|---|---|---|
| `exists(agent_id)` | read | `bool` |
| `owner_of(agent_id)` | read | checksummed address |
| `agent_uri(agent_id)` | read | `str` |
| `get_metadata(agent_id, key)` | read | `bytes` |
| `get_agent_wallet(agent_id)` | read | address or `None` |
| `get_identity(agent_id)` | read | `AgentIdentity` |
| `list_registered(from_block, to_block)` | read | `list[RegisteredAgent]` |
| `register(agent_uri?, metadata?)` | write | `int` (agentId) |
| `set_agent_uri(agent_id, new_uri)` | write | tx hash |
| `set_metadata(agent_id, key, value)` | write | tx hash |
| `set_agent_wallet(agent_id, new_wallet, signature, deadline)` | write | tx hash |
| `unset_agent_wallet(agent_id)` | write | tx hash |

Reads work without an `account`; writes require one and raise `MissingAccountError`
otherwise. Contract reverts surface as typed exceptions (`NotAgentOwner`,
`ReservedMetadataKey`, `SignatureExpired`, `DeadlineTooFar`,
`InvalidWalletSignature`); anything unrecognised raises `ContractRevert` with the
raw data — never swallowed.

## Development

```bash
make test        # uv run pytest — spins up anvil, deploys the real contract
make typecheck   # uv run mypy --strict src/
make sync-abi    # regenerate the pinned ABI from ../contracts/out/...
```

The pinned ABI lives in `src/agent_passport/abi/AgentPassport.json` so the SDK
installs standalone. After changing the contract, run `make sync-abi` and commit.
Tests require `anvil` (Foundry) on `PATH`.
