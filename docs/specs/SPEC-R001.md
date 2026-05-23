# SPEC-R001: AgentPassport — Skeleton & Storage Layout

**Status:** 🟢 Done v2 (pending Phil-Review)
**Owner:** SA1 Contracts
**Estimated:** 3h
**Actual:** ~1h v1 + ~30min v2 hardening (code-review fixes)
**Dependencies:** —
**Repo:** agent-passport
**Created:** 2026-05-23
**Revisions:**
- v1 (2026-05-23 12:18) — initial 13-test green
- v2 (2026-05-23 12:45) — hardened per `/code-review` — see `## Changelog v2` at bottom

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
- **FR4:** Jede Mutation emittiert ein Event (v2: 3 indexed topics für indexer-Filter):
  - `AgentRegistered(bytes32 indexed agentId, address indexed owner, address indexed paymentAddress, string name, string endpoint, string metadataURI, uint64 registeredAt)`
  - `AgentUpdated(bytes32 indexed agentId, address indexed owner, address indexed paymentAddress, string name, string endpoint, string metadataURI)`
  - `AgentRelinquished(bytes32 indexed agentId, address indexed owner)`
- **FR5:** Custom errors statt revert-strings (Gas):
  - `AlreadyRegistered(bytes32 agentId)`
  - `NotOwner(bytes32 agentId, address caller)`
  - `UnknownAgent(bytes32 agentId)`
  - **v2:** `ZeroAgentId()`, `ZeroPaymentAddress()`, `EmptyField()`, `NoChange(bytes32 agentId)`
- **FR6 (v2):** `registerAgent` und `updateAgent` validieren Inputs:
  - `agentId != bytes32(0)` (register) — reserviert Null als Sentinel für Downstream-Consumer
  - `paymentAddress != address(0)` (beide) — verhindert Burn durch SDK-Defaults
  - `name`, `endpoint`, `metadataURI` non-empty (beide) — verhindert versehentliches Wipe
- **FR7 (v2):** `updateAgent` revertet mit `NoChange(agentId)` wenn alle vier mutierbaren Felder
  identisch zum gespeicherten Stand sind. Hash-Compare; keine Indexer-Noise.
- **FR8 (v2):** Cheap-Accessors für andere Contracts:
  - `agentOwner(bytes32) returns (address)` — gibt `address(0)` bei unbekannter ID, never reverts
  - `exists(bytes32) returns (bool)` — True wenn registriert (und nicht relinquished)
  - Beide ~2.5k gas vs ~20k für `resolveAgent().owner` (8× cheaper)
- **FR9 (v2):** `relinquishAgent(bytes32)` — Owner kann ID surrendern.
  - Nur Owner; revertet `NotOwner` für andere und `UnknownAgent` für nicht-registrierte
  - `delete _agents[id]` + `emit AgentRelinquished(id, owner)`
  - Slot wird leer; ID ist sofort wieder registrierbar (auch durch denselben Owner mit fresh key — Key-Compromise-Recovery)

## Non-Functional Requirements

- **NFR1:** Gas für `registerAgent` mit Strings ≤ 50 chars < **250k** (median 188k bestätigt).
  In-Test assertion via `test_RegisterAgent_GasUnder250k` — verhindert silent regression in R002.
- **NFR2:** Storage-Layout in NatSpec dokumentiert **UND** durch Test gepinnt
  (`test_StorageLayout_AgentCard_SlotMap` via `vm.load`).
  R002 darf nur APPENDEN — Tests blocken jeden Reorder.
- **NFR3:** `forge coverage` > **80%** für `AgentPassport.sol` (Ziel: ~100% durch 32 Unit-Tests).
- **NFR4:** `forge fmt --check` exitet 0.
- **NFR5:** Compile mit Solidity **0.8.24**, optimizer on, runs = 200.
- **NFR6 (v2):** `_agents` Mapping ist `internal` (nicht `private`) — Voraussetzung für R002
  ERC-8004-Inheritance. Pinned by `AgentPassport.inheritance.t.sol::test_Subclass_CanReadInternal_AgentsMapping`.
- **NFR7 (v2):** Inheritance-Order-Invariant: R002 MUSS `is AgentPassport, ERC721` schreiben
  (NICHT umgekehrt). Andere Order verschiebt `_agents` von Slot 0 → korrupte Storage.
  Dokumentiert in Contract-NatSpec (Zeilen 9-14).

## Acceptance Tests (written FIRST, must FAIL before implementation)

**39 Tests total** = 32 Unit + 4 Scenarios + 3 Inheritance.

### Unit Tests — `contracts/test/AgentPassport.t.sol` (32 Tests)

| # | Name | Deckt |
|---|---|---|
| U1 | `test_RegisterAgent_StoresCard` | FR1 |
| U2 | `test_RegisterAgent_SetsRegisteredAt` | FR1 |
| U3 | `test_RegisterAgent_RevertsOnDuplicate` | FR5 AlreadyRegistered |
| U4 | `test_RegisterAgent_EmitsAgentRegistered` | FR4 |
| U5 | `test_UpdateAgent_OwnerCanUpdate` | FR2 |
| U6 | `test_UpdateAgent_RevertsForNonOwner` | FR2, FR5 NotOwner |
| U7 | `test_UpdateAgent_RevertsForUnknownId` | FR5 UnknownAgent |
| U8 | `test_UpdateAgent_EmitsAgentUpdated` | FR4 |
| U9 | `test_ResolveAgent_UnknownReturnsEmpty` | FR3 |
| U10 | `test_RegisterAgent_RevertsOnZeroAgentId` (v2) | FR6, ZeroAgentId |
| U11 | `test_RegisterAgent_RevertsOnZeroPaymentAddress` (v2) | FR6, ZeroPaymentAddress |
| U12 | `test_RegisterAgent_RevertsOnEmptyName` (v2) | FR6, EmptyField |
| U13 | `test_RegisterAgent_RevertsOnEmptyEndpoint` (v2) | FR6, EmptyField |
| U14 | `test_RegisterAgent_RevertsOnEmptyMetadataURI` (v2) | FR6, EmptyField |
| U15 | `test_UpdateAgent_RevertsOnZeroPaymentAddress` (v2) | FR6 |
| U16 | `test_UpdateAgent_RevertsOnEmptyName` (v2) | FR6 |
| U17 | `test_UpdateAgent_RevertsOnEmptyEndpoint` (v2) | FR6 |
| U18 | `test_UpdateAgent_RevertsOnEmptyMetadataURI` (v2) | FR6 |
| U19 | `test_UpdateAgent_RevertsOnNoChange` (v2) | FR7, NoChange |
| U20 | `test_UpdateAgent_PartialChange_PaymentOnly` (v2) | FR7 (positive case) |
| U21 | `test_UpdateAgent_PartialChange_NameOnly` (v2) | FR7 (positive case) |
| U22 | `test_AgentOwner_ReturnsOwner` (v2) | FR8 |
| U23 | `test_AgentOwner_UnknownReturnsZero` (v2) | FR8 |
| U24 | `test_Exists_TrueForRegistered` (v2) | FR8 |
| U25 | `test_Exists_FalseForUnknown` (v2) | FR8 |
| U26 | `test_RelinquishAgent_OwnerCanRelinquish` (v2) | FR9 |
| U27 | `test_RelinquishAgent_RevertsForNonOwner` (v2) | FR9 |
| U28 | `test_RelinquishAgent_RevertsForUnknown` (v2) | FR9 |
| U29 | `test_RelinquishAgent_EmitsEvent` (v2) | FR9, FR4 |
| U30 | `test_RelinquishAgent_AllowsReRegistration` (v2) | FR9 |
| U31 | `test_RegisterAgent_GasUnder250k` (v2) | NFR1 |
| U32 | `test_StorageLayout_AgentCard_SlotMap` (v2) | NFR2 |

### Functional Tests — `contracts/test/AgentPassport.scenarios.t.sol` (4 Tests)

| # | Name | Scenario |
|---|---|---|
| F1 | `test_Roundtrip_RegisterUpdateResolve` | register → resolve → update → resolve mit unveränderter `registeredAt` |
| F2 | `test_MultiAgent_IsolatedStorage` | 3 Agents (alice/bob/charlie) — Update von Bob ändert Alice/Charlie NICHT |
| F3 | `test_RegisterFromMultipleSenders_OwnerIsMsgSender` | 2 verschiedene Sender registrieren → owner = msg.sender pro Card |
| F4 | `testFuzz_RegisterArbitraryCards` | fuzz (1000 runs) — bounded strings, exclude test-contract addresses, owner-Check + non-owner-update revert |

### Inheritance Tests — `contracts/test/AgentPassport.inheritance.t.sol` (3 Tests, v2)

| # | Name | Scenario |
|---|---|---|
| I1 | `test_Subclass_CanReadInternal_AgentsMapping` | Harness contract `is AgentPassport` kann `_agents` lesen (compile-Time-Beweis für NFR6) |
| I2 | `test_Subclass_PreservesParentSlot0_ForAgentsMapping` | `_agents` bleibt bei Slot 0 auch nach Subclass-Storage-Addition |
| I3 | `test_Subclass_AppendedStorage_LandsInOwnSlot` | Subclass-Mapping landet Slot 1 — beweist append-safe |

→ **Pre-Implementation:** alle Tests müssen FAIL sein (RED commits). v1 commit `967dd6d` + `80c93f4`; v2 commit `00a8599`.

## Implementation Notes

- **Storage-Layout** (gepinnt durch Test U32):
  ```solidity
  struct AgentCard {
      address owner;          // slot 0 [0..160]
      uint64 registeredAt;    // slot 0 [160..224] — packed
      string name;            // slot 1
      string endpoint;        // slot 2
      address paymentAddress; // slot 3 (own slot, bracketed by strings)
      string metadataURI;     // slot 4
  }
  mapping(bytes32 => AgentCard) internal _agents;  // v2: was private
  ```
- `owner + registeredAt` zusammen 28 Bytes → packen in 1 Slot.
- `string calldata` für Inputs (gas).
- Owner-Check via `card.owner != address(0)` (EVM-Invariant: tx-sender ≠ 0).
- Keine OpenZeppelin-Inheritance in R001 (kommt erst R002 mit ERC-721).
- Keine Reentrancy-Guards nötig (keine external calls / kein ETH-Handling).
- Custom errors mit `bytes32` und `address` als Args für gute Decodierung.
- **v2 NoChange-Detection:** Field-by-field short-circuit AND mit `keccak256(bytes(...))` für
  Strings — Gas-Overhead ~5k auf "unchanged" path, ~3k auf typical "something changed".
- **v2 Inheritance Invariant:** R002 muss `is AgentPassport, ERC721` deklarieren
  (NICHT umgekehrt). Sonst verschieben sich die Storage-Slots → korrupte Reads.

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
- Owner-Transfer-Funktion (Custodian-Wechsel) → **R002** (kommt über NFT-Transfer).
  v2 `relinquishAgent` ist KEIN Transfer — es leert die ID und macht sie neu registrierbar
  durch jeden (inkl. Original-Owner mit fresh key). Kein Custodian-State-Transfer.
- Validation Registry Hooks → späteres Spec, ausserhalb Hackathon
- Slither static-analysis Run → **R014** (CI-Pipeline)
- Deployment auf Arc-Testnet → Phil-Manual nach R007 fertig
- Optimistic Concurrency Token für update (relevant erst nach R002 NFT-Transfer enables ownership change mid-block) → R002 design

## Definition of Done

- [x] Spec-Card vollständig ausgefüllt
- [x] Failing Unit-Tests committed (eigener Commit, 8/9 RED + 1 trivial-PASS)
- [x] Failing Functional-Tests committed (eigener Commit, 4 RED)
- [x] Implementation committed, alle 13 Tests grün (`forge test`)
- [x] `forge coverage` 100% für `AgentPassport.sol` (>80% Schwelle) — v2: 100% (38/38 lines, 11/11 branches)
- [x] `forge test --gas-report` archiviert in `docs/gas-reports/R001.md`
- [x] `registerAgent`-Gas Median 188k bestätigt (<250k) — v2: in-Test pinned via U31
- [x] `forge fmt --check` exitet 0
- [x] NatSpec auf alle external Functions + Storage-Layout-Kommentar
- [x] **v2:** Storage-Layout durch Test gepinnt (U32) + Inheritance-Tests (I1-I3)
- [x] **v2:** Input-Validation gegen Zero-ID / Zero-Payment / Empty-Strings
- [x] **v2:** NoChange-Detection auf updateAgent
- [x] **v2:** relinquishAgent für Key-Compromise-Recovery
- [x] **v2:** Cheap accessors agentOwner/exists für R002+R003-Consumer
- [x] **v2:** Events haben 3 indexed topics (agentId/owner/paymentAddress) für off-chain filtering
- [ ] **Phil-Review erledigt** ← pending (v2 fertig zum Review)
- [x] Spec-Card Status auf 🟢
- [x] SPECS-INDEX.md status auf 🟢
- [x] IMPLEMENTATION-LOG.md appended

## Progress Log

### v1 — initial 13-test green
- 2026-05-23 11:18 — Foundry-Projekt initialisiert + OZ-Submodule (commit `914e1e2`)
- 2026-05-23 11:35 — Spec-Card erstellt (commit `dbfe19e`)
- 2026-05-23 11:48 — RED: 9 Unit-Tests + Stub (commit `967dd6d`) — 8 fail, 1 trivial-pass
- 2026-05-23 11:55 — RED: 4 Functional + Fuzz (commit `80c93f4`) — 12/13 fail
- 2026-05-23 12:05 — GREEN: AgentPassport impl (commit `0cebda4`) — 13/13 grün, fuzz 256 runs
- 2026-05-23 12:12 — Gas-Report + Coverage 100% archiviert (commit `2190c4e`)
- 2026-05-23 12:18 — DoD checklist + status → 🟢 (commit `55c4be5`)

### v2 — hardening per `/code-review` (15 findings actioned)
- 2026-05-23 12:25 — chore: .gitignore + foundry.toml fixes (commit `55101b0`)
- 2026-05-23 12:35 — RED: 22 new tests + fuzz hardening + stubs (commit `00a8599`) — 17/36 fail
- 2026-05-23 12:42 — GREEN: contract hardening (commit `60d038c`) — 39/39 grün, coverage 100%
- 2026-05-23 12:50 — docs: Spec-Card v2 + DoD update (this commit)

## Changelog v2

Drivers: `/code-review` produced 15 findings. All actioned.

**Contract:**
- `_agents` `private` → `internal` (enables R002 inheritance) — Finding #1
- New errors: `ZeroAgentId`, `ZeroPaymentAddress`, `EmptyField`, `NoChange` — Findings #3, #4, #5, #13
- Input validation on register + update (zero-id, zero-payment, empty strings) — Findings #3, #4, #5
- `NoChange` detection on updateAgent via hash-compare — Finding #13
- New function `relinquishAgent(bytes32)` for key-compromise recovery — Finding #14
- New cheap accessors `agentOwner(bytes32)` and `exists(bytes32)` (~2.5k gas vs ~20k) — Finding #6
- Event signatures: `AgentRegistered` gains `indexed paymentAddress`; `AgentUpdated` gains `indexed owner`+`indexed paymentAddress` — Finding #8
- New event `AgentRelinquished(agentId, owner)`
- NatSpec block documents R002 inheritance order invariant (`is AgentPassport, ERC721`, NOT reverse) — Finding #9

**Tests (39 total, +26 from v1):**
- 9 new validation reverts (5 register + 4 update)
- 2 NoChange + partial-change tests
- 4 agentOwner/exists tests
- 5 relinquishAgent tests
- 1 gas-budget assertion (NFR1 in-test) — Finding #7
- 1 storage-layout snapshot via `vm.load` — Finding #11
- 3 inheritance tests (new file `AgentPassport.inheritance.t.sol`) — Findings #1, #11
- Fuzz hardened: assume non-zero/non-empty/non-test-contract; attacker uses distinct payment — Finding #12

**Config:**
- `.gitignore`: removed accidental `docs/` rule — Finding #2
- `foundry.toml`: `gas_reports = ["*"]` (covers R002+ automatically) — Finding #10
- `foundry.toml`: `fuzz.runs` 256 → 1_000 + raised `max_test_rejects` for assume-heavy fuzz

**Not actioned (with reason):**
- ERC-721 inheritance storage-shift risk (Finding #9) — mitigated via NatSpec invariant + inheritance tests; the actual ERC-721 inheritance lands in R002 and that PR will add the order-pinning test
- Optimistic concurrency token (Finding deferred to R002) — relevant only post-R002 NFT-transfer
