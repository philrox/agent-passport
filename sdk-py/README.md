# agent-passport (Python SDK)

Python SDK for the **Agent Passport** ERC-8004 Identity Registry. Register agents,
read identity/metadata, and enumerate registered agents from a deployed
`AgentPassport` contract.

> Quickstart and full docs land under SPEC-R005 step 8.

```python
from agent_passport import IdentityRegistry, ChainConfig

reg = IdentityRegistry.from_config(
    ChainConfig(rpc_url="http://127.0.0.1:8545", contract_address="0x...", chain_id=31337)
)
print(reg.exists(1))
```
