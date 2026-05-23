## Summary

<!-- 1-3 sentences describing what this PR does and why. -->

## Linked Spec

SPEC-R<!-- e.g. SPEC-R003 — link to docs/specs/SPEC-RXXX.md -->

## Definition of Done

- [ ] Spec-Card in `docs/specs/SPEC-RXXX.md` updated (or referenced if external contribution)
- [ ] Failing tests committed first in a separate commit (TDD-first, `test(RXXX): RED — ...`)
- [ ] All tests pass locally (`forge test -vv`)
- [ ] Coverage stays >80% on touched files (`forge coverage`)
- [ ] `forge fmt --check` clean
- [ ] Slither — no new high/critical findings
- [ ] NatSpec on all new public/external functions
- [ ] Storage-layout changes documented (breaking-change flag if applicable)
- [ ] No new secrets / private keys committed

## Change Type

- [ ] Bug fix (non-breaking)
- [ ] New feature (non-breaking)
- [ ] Breaking change (requires migration notes)
- [ ] Documentation / chore

## Notes for Reviewer

<!-- Anything specific to call out: tricky logic, edge cases, gas trade-offs, follow-ups. -->
