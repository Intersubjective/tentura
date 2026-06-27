# Tentura documentation index

Short pointers for agents — read only what your task needs. Full inventory: **23 files** under `docs/` (plus this index).

## Product north star

| Doc | Read when |
|-----|-----------|
| [`Tentura_current_status_quo.md`](Tentura_current_status_quo.md) | Orientation on shipped product direction, axioms, inbox/My Work model |
| [`beacon-evaluation-principles.md`](beacon-evaluation-principles.md) | Closure reviews, evaluation eligibility, contest safeguards |
| [`beacon-status-line-rationale.md`](beacon-status-line-rationale.md) | STATUS/NOW/YOU rows, coordination phase copy theory |
| [`before-response-terminal-tombstone.md`](before-response-terminal-tombstone.md) | Terminal inbox rows when user never triaged |
| [`watching-mechanism.md`](watching-mechanism.md) | Watching vs Needs me / Not for me / My Work |
| [`invite-signup-landing-flow.md`](invite-signup-landing-flow.md) | Landing, WASM, native invite/signup routing (implemented) |

## Feature specs (user-facing)

| Doc | Read when |
|-----|-----------|
| [`features/beacon_room.md`](features/beacon_room.md) | Room admission, help offers, Items/People/Log, coordination |
| [`features/new-stuff-indicators.md`](features/new-stuff-indicators.md) | Inbox/My Work “new since last visit” dots and pills |
| [`features/trust_edges.md`](features/trust_edges.md) | User→user trust weights (MeritRank input) |
| [`features/mutual-friends.md`](features/mutual-friends.md) | Mutual-friends query on profiles / invite accept |

## Engineering / ADRs / inventories

| Doc | Read when |
|-----|-----------|
| [`beacon-visibility-matrix.md`](beacon-visibility-matrix.md) | Checking who can see / open / forward a beacon — involvement-type matrix, profile surface mismatches |
| [`tentura-design-system.md`](tentura-design-system.md) | Flutter UI tokens, typography, layout, M3 patterns |
| [`beacon-ontology-icon-mapping.md`](beacon-ontology-icon-mapping.md) | Ontology leaf → `Icons.*_rounded` catalog |
| [`client-ui-inventory.md`](client-ui-inventory.md) | Screens, routes, dialogs — **regenerate before trusting** |
| [`test-coverage-misses.md`](test-coverage-misses.md) | COV-* test backlog for agents claiming coverage work |
| [`adr/0001-capability-event-storage.md`](adr/0001-capability-event-storage.md) | Private capability events, derived reads |
| [`adr/0002-root-session-routing.md`](adr/0002-root-session-routing.md) | `/` cookie routing, landing vs WASM |
| [`adr/0003-settings-credential-linking.md`](adr/0003-settings-credential-linking.md) | Settings credential linking |
| [`adr/0004-beacon-lineage-fork.md`](adr/0004-beacon-lineage-fork.md) | `beaconFork`, lineage forward suggestions |
| [`adr/0005-unified-avatar-system.md`](adr/0005-unified-avatar-system.md) | Avatar system |
| [`adr/0006-client-sentry-observability.md`](adr/0006-client-sentry-observability.md) | Client Sentry (WASM) |
| [`adr/0007-server-sentry-observability.md`](adr/0007-server-sentry-observability.md) | Server Sentry |
| [`adr/0008-beacon-visibility-and-invite-sharing.md`](adr/0008-beacon-visibility-and-invite-sharing.md) | Relationship-scoped visibility, beacon invites |
| [`adr/0009-landing-sentry-observability.md`](adr/0009-landing-sentry-observability.md) | Landing funnel Sentry |

**Root vocabulary:** [`../CONTEXT.md`](../CONTEXT.md) · **Agent entry:** [`../AGENTS.md`](../AGENTS.md) · **Dev conventions:** [`../DEV_GUIDELINES.md`](../DEV_GUIDELINES.md)

## Maintenance

- Retired journals/plans were removed in 2026-06 cleanup; prefer this index + status quo over grep hits in old branches.
- Legacy term drift check: `scripts/check-doc-drift.sh` (Registry tab, Overview tab, `coordination_status`, `beacon.state`, ChatNews, `beacon_blocker`).
- After large UI refactors: refresh [`client-ui-inventory.md`](client-ui-inventory.md); verify home tab order (My Work default), beacon detail tabs (Items / People / Log).
