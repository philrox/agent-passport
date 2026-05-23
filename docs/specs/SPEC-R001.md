# SPEC-R001: AgentPassport — Skeleton & Storage Layout

**Status:** 🟡 In Progress
**Owner:** SA1 Contracts
**Estimated:** 3h
**Dependencies:** —
**Repo:** agent-passport
**Created:** 2026-05-23

## Context

R001 ist die Fundament-Spec der Registry. **8 weitere Specs hängen davon ab** (R002 ERC-8004,
R003 JobContract, R004 DecisionReceipts, R005 Python-SDK, R006 TS-SDK, R007 PolymarketAdapter,
R008 HIP-4-Adapter, R014 CI). Day 1 EOD muss grün sein, sonst kippt der gesamte Day-2-Build.

Das Ziel ist ein **minimaler, permissionless Registry-Contract**, der pro `bytes32 agentId` eine
`AgentCard`-Struktur speichert, owner-gated Updates erlaubt und alle Mutationen als Events emittiert.
**Noch kein ERC-8004 NFT** (R002), **kein Cross-Venue Mapping** (R007/R008), **kein Reputation-Update**
(R010). Das Storage-Layout muss upgrade-safe dokumentiert sein, damit R002 nur APPENDET, nicht reordert.

## User Stories

- Als **Agent-Owner** möchte ich meinen Agent unter einer eindeutigen `bytes32`-ID registrieren,
  damit er onchain auditierbar ist.
- Als **Agent-Owner** möchte ich die Metadaten meines Agents updaten können (Endpoint, Payment-Adresse,
  Metadata-URI), damit ich Infrastruktur-Änderungen propagieren kann ohne neue ID.
- Als **Caller** möchte ich einen Agent über seine ID resolven, um seinen Owner und seine
  Capabilities zu sehen.
- Als **Auditor** möchte ich alle Registrierungen + Updates als Events einsehen können (off-chain
  indexing).

## Functional Requirements

- **FR1:** `registerAgent(bytes32 id, string name, string endpoint, address payment, string metadataURI)`
  schreibt eine `AgentCard` in den Storage. `card.owner = msg.sender` wird vom Contract gesetzt
  (Caller kann nicht einen anderen Owner spoofen). `card.registeredAt = block.timestamp`.
- **FR2:** `updateAgent(bytes32 id, string name, string endpoint, address payment, string metadataURI)`
  ist nur durch `agents[id].owner` aufrufbar. `owner` und `registeredAt` bleiben unverändert.
- **FR3:** `resolveAgent(bytes32 id) returns (AgentCard memory)` ist public view. Unbekannte ID gibt
  eine leere Card zurück (`owner == address(0)`), **kein revert**.
- **FR4:** Jede Mutation emittiert ein Event:
  - `AgentRegistered(bytes32 indexed agentId, address indexed owner, string name, string endpoint, address paymentAddress, string metadataURI, uint64 registeredAt)`
  - `AgentUpdated(bytes32 indexed agentId, string name, string endpoint, address paymentAddress, string metadataURI)`
- **FR5:** Custom errors statt revert-strings (Gas):
  - `AlreadyRegistered(bytes32 agentId)`
  - `NotOwner(bytes32 agentId, address caller)`
  - `UnknownAgent(bytes32 agentId)`

## Non-Functional Requirements

- **NFR1:** Gas für `registerAgent` mit Strings ≤ 50 chars < **250k** (angepasst vom Original 200k
  wegen Rich-Struct mit 3 Strings).
- **NFR2:** Storage-Layout in NatSpec dokumentiert, R002 darf nur APPENDEN — kein Reordering.
- **NFR3:** `forge coverage` > **80%** für `AgentPassport.sol` (Ziel: ~100% durch 13 Tests).
- **NFR4:** `forge fmt --check` exitet 0.
- **NFR5:** Compile mit Solidity **0.8.24**, optimizer on, runs = 200.

## Acceptance Tests (written FIRST, must FAIL before implementation)

### Unit Tests — `contracts/test/AgentPassport.t.sol` (9 Tests)

| # | Name | Deckt |
|---|---|---|
| U1 | `test_RegisterAgent_StoresCard` | FR1 |
| U2 | `test_RegisterAgent_SetsRegisteredAt` | FR1 |
| U3 | `test_RegisterAgent_RevertsOnDuplicate` | FR5, AlreadyRegistered |
| U4 | `test_RegisterAgent_EmitsAgentRegistered` | FR4 |
| U5 | `test_UpdateAgent_OwnerCanUpdate` | FR2 |
| U6 | `test_UpdateAgent_RevertsForNonOwner` | FR2, FR5 NotOwner |
| U7 | `test_UpdateAgent_RevertsForUnknownId` | FR5 UnknownAgent |
| U8 | `test_UpdateAgent_EmitsAgentUpdated` | FR4 |
| U9 | `test_ResolveAgent_UnknownReturnsEmpty` | FR3 |

### Functional Tests — `contracts/test/AgentPassport.scenarios.t.sol` (4 Tests)

| # | Name | Scenario |
|---|---|---|
| F1 | `test_Roundtrip_RegisterUpdateResolve` | register → resolve → update → resolve mit unveränderter `registeredAt` |
| F2 | `test_MultiAgent_IsolatedStorage` | 3 Agents (alice/bob/charlie) — Update von Bob ändert Alice/Charlie NICHT |
| F3 | `test_RegisterFromMultipleSenders_OwnerIsMsgSender` | 2 verschiedene Sender registrieren → owner = msg.sender pro Card |
| F4 | `testFuzz_RegisterArbitraryCards` | fuzz mit random bytes32 + bounded strings, owner-Check |

→ **Pre-Implementation:** alle 13 Tests müssen FAIL sein (RED commits).

## Implementation Notes

- **Storage-Layout:**
  ```
  struct AgentCard {
      address owner;          // slot N (20 bytes)
      uint64 registeredAt;    // slot N (8 bytes, packed)
      string name;            // slot N+1
      string endpoint;        // slot N+2
      address paymentAddress; // slot N+3
      string metadataURI;     // slot N+4
  }
  mapping(bytes32 => AgentCard) private _agents;
  ```
- `owner + registeredAt` zusammen 28 Bytes → packen in 1 Slot.
- `string calldata` für Inputs (gas).
- Owner-Check via `card.owner != address(0)` (EVM-Invariant: tx-sender ≠ 0).
- Keine OpenZeppelin-Inheritance in R001 (kommt erst R002 mit ERC-721).
- Keine Reentrancy-Guards nötig (keine external calls / kein ETH-Handling).
- Custom errors mit `bytes32` und `address` als Args für gute Decodierung.

## Files

- `contracts/foundry.toml` (already committed Step 1)
- `contracts/src/AgentPassport.sol` (NEW, Step 5)
- `contracts/test/AgentPassport.t.sol` (NEW, Step 3)
- `contracts/test/AgentPassport.scenarios.t.sol` (NEW, Step 4)
- `contracts/script/Deploy.s.sol` (NEW, minimal — Step 5 oder R014)
- `docs/specs/SPEC-R001.md` (THIS FILE, Step 2)
- `docs/gas-reports/R001.md` (NEW, Step 6)

## Out of Scope

- ERC-8004 NFT-Minting / ERC-721 Interface → **R002**
- Cross-Venue-Lookups (Polymarket Builder Code, HIP-4) → **R007/R008**
- Reputation-Update-Logic → **R010**
- Owner-Transfer-Funktion → **R002** (kommt über NFT-Transfer)
- Validation Registry Hooks → späteres Spec, ausserhalb Hackathon
- Slither static-analysis Run → **R014** (CI-Pipeline)
- Deployment auf Arc-Testnet → Phil-Manual nach R007 fertig

## Definition of Done

- [x] Spec-Card vollständig ausgefüllt (this file)
- [ ] Failing Unit-Tests committed (eigener Commit, alle 9 RED)
- [ ] Failing Functional-Tests committed (eigener Commit, alle 4 RED)
- [ ] Implementation committed, alle 13 Tests grün (`forge test`)
- [ ] `forge coverage` > 80% für `AgentPassport.sol`
- [ ] `forge test --gas-report` archiviert in `docs/gas-reports/R001.md`
- [ ] `registerAgent`-Gas < 250k bestätigt
- [ ] `forge fmt --check` exitet 0
- [ ] NatSpec auf alle external Functions + Storage-Layout-Kommentar
- [ ] Phil-Review erledigt
- [ ] Spec-Card Status auf 🟢
- [ ] SPECS-INDEX.md status auf 🟢
- [ ] IMPLEMENTATION-LOG.md appended

## Progress Log

- 2026-05-23 11:18 — Foundry-Projekt initialisiert + OZ-Submodule (commit 914e1e2)
- 2026-05-23 11:35 — Spec-Card erstellt (this commit)
