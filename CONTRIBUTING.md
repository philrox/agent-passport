# Contributing to Agent Passport

Thanks for your interest in Agent Passport — the Cross-Venue Agent Identity Layer for prediction markets. We welcome contributions: bug reports, feature requests, standard proposals, and pull requests.

This project was open-sourced during the [Agora Agents Hackathon](https://agora.thecanteenapp.com/) (May 21–25 2026) and is actively developed.

## Development Setup

You'll need:

- [Foundry](https://book.getfoundry.sh/) for contracts (`forge`, `cast`, `anvil`)
- [Node.js](https://nodejs.org/) 20+ for the TypeScript SDK (`sdk-ts/`, once it lands)
- Python 3.11+ and [`uv`](https://docs.astral.sh/uv/) for the Python SDK (`sdk-py/`, once it lands)

```bash
git clone https://github.com/philrox/agent-passport
cd agent-passport

# Contracts
cd contracts
forge install
forge test -vv
forge coverage

# TS SDK (when present)
cd ../sdk-ts && npm install && npm test

# Python SDK (when present)
cd ../sdk-py && uv sync && uv run pytest
```

## TDD-First Workflow (mandatory)

Every change follows this sequence — no shortcuts:

1. Open or reference a spec in `docs/specs/SPEC-RXXX.md`
2. Write failing tests **first**, commit them as a separate commit (`test(RXXX): RED — <description>`)
3. Implement until tests pass (`feat(RXXX): <description>`)
4. Run `forge test -vv`, `forge coverage` (>80% on touched files), `forge fmt --check` clean
5. Run Slither — no new high/critical findings
6. Open a PR using the template, mark the Definition-of-Done checklist complete

If you skip the failing-tests step, the PR will not be merged.

## Standard Proposals

Agent Passport defines a candidate standard in `docs/SPEC.md`. Proposed changes to the standard go through the **Spec Proposal** issue template before opening a PR. Standards-level changes need maintainer sign-off plus at least one community comment supporting the change.

## Branch & Commit Conventions

- Branch from `main`, name like `feature/spec-r007-polymarket-adapter` or `fix/passport-storage-collision`
- Commit messages: imperative mood, no trailing period (`Add HIP-4 adapter`, not `Added HIP-4 adapter.`)
- Conventional-commit prefixes for spec work: `test(RXXX)`, `feat(RXXX)`, `fix(RXXX)`, `docs(RXXX)`, `chore(RXXX)`
- Squash on merge — keep commit history linear

## PR Review Policy

- **External contributors**: open a PR from your fork. A maintainer (@philrox) will review before merging.
- **Maintainers**: self-merge allowed after CI passes; no approval required.

## Smart Contract Discipline

This is on-chain code. Be especially careful with:

- **Storage layout** — document any changes; treat as breaking unless the contract is not yet deployed
- **External calls** — use reentrancy guards where state mutates
- **Custom errors** instead of `require` strings (gas)
- **Events** on every state mutation
- **NatSpec** on all public/external functions
- No `tx.origin`, no `block.timestamp` for randomness
- Test fuzz invariants where applicable

## Reporting Issues

Use the issue templates: bug report, feature request, or standard proposal. Security issues: see [SECURITY.md](SECURITY.md) — do **not** open public issues for vulnerabilities.

## Code of Conduct

By participating, you agree to abide by the [Code of Conduct](CODE_OF_CONDUCT.md).
