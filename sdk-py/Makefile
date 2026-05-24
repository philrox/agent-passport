ARTIFACT := ../contracts/out/AgentPassport.sol/AgentPassport.json
ABI_OUT  := src/agent_passport/abi/AgentPassport.json

.PHONY: sync-abi test typecheck

# Regenerate the pinned ABI from the Foundry build artifact. Run after the contract
# changes; the committed ABI must always match (CI/verify checks for no diff).
sync-abi:
	@python3 -c "import json,sys; a=json.load(open('$(ARTIFACT)'))['abi']; json.dump(a, open('$(ABI_OUT)','w'), indent=2); print('synced', len(a), 'abi entries')"

test:
	uv run pytest -v

typecheck:
	uv run mypy --strict src/
