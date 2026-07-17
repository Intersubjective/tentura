# Tentura documentation index

Short pointers for agents — read only what your task needs.

## Layout

| Folder | Contents |
|--------|----------|
| `docs/` (root) | Living product/eng specs and runbooks |
| [`features/`](features/) | User-facing feature specs |
| [`adr/`](adr/) | Architecture decision records |
| [`plans/`](plans/) | **Active** implementation plans |
| [`audits/`](audits/) | QA audits, analyses, UX reviews, readiness reports |
| [`archive/plans/`](archive/plans/) | Done / superseded / historical plans |
| [`archive/journals/`](archive/journals/) | Journals for archived plan work |

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

## Active plans

| Doc | Read when |
|-----|-----------|
| [`plans/beacon-cross-screen-invalidation-refactor.md`](plans/beacon-cross-screen-invalidation-refactor.md) | Sync My Work/Inbox after local room mutations |
| [`plans/beacon-location-google-maps-plan.md`](plans/beacon-location-google-maps-plan.md) | Google Maps picker + external Maps hand-off |
| [`plans/google-maps-server-proxy-plan.md`](plans/google-maps-server-proxy-plan.md) | Server-side Geocoding/Places proxy |
| [`plans/profile-request-routing-plan.md`](plans/profile-request-routing-plan.md) | Profile → request-routing surface (issue #83) |

## Audits and analyses

| Doc | Read when |
|-----|-----------|
| [`audits/beacon-detail-qa-audit.md`](audits/beacon-detail-qa-audit.md) | Beacon detail coordination QA matrix |
| [`audits/room-coordination-audit.md`](audits/room-coordination-audit.md) | Room vs generic-chat architecture audit |
| [`audits/beacon-visibility-analysis.md`](audits/beacon-visibility-analysis.md) | Visibility QA traps and READ/REACH remediation |
| [`audits/beacon-location-ux-review.md`](audits/beacon-location-ux-review.md) | Location UX vs pick/label/map/directions goals |
| [`audits/responsive-design-audit.md`](audits/responsive-design-audit.md) | Responsive layout audit + residual backlog |
| [`audits/desktop-adaptive-readiness-report.md`](audits/desktop-adaptive-readiness-report.md) | Desktop/adaptive readiness snapshot |
| [`audits/staging-invite-forward-qa-audit.md`](audits/staging-invite-forward-qa-audit.md) | Staging invite/forward E2E QA |
| [`audits/staging-invite-forward-qa-audit-supplement.md`](audits/staging-invite-forward-qa-audit-supplement.md) | Delta findings for the staging QA session |
| [`audits/local-playwright-screen-tree.md`](audits/local-playwright-screen-tree.md) | Local Playwright screen-coverage checklist |

## Engineering / ADRs / inventories

| Doc | Read when |
|-----|-----------|
| [`beacon-visibility-matrix.md`](beacon-visibility-matrix.md) | Who can see / open / forward a beacon |
| [`tentura-design-system.md`](tentura-design-system.md) | Flutter UI tokens, typography, layout, M3 patterns |
| [`beacon-ontology-icon-mapping.md`](beacon-ontology-icon-mapping.md) | Ontology leaf → `Icons.*_rounded` catalog |
| [`client-ui-inventory.md`](client-ui-inventory.md) | Screens, routes, dialogs — **regenerate before trusting** |
| [`test-coverage-misses.md`](test-coverage-misses.md) | COV-* test backlog for agents claiming coverage work |
| [`realtime-sync-operations.md`](realtime-sync-operations.md) | Realtime contract, dashboards/log queries, alerts |
| [`local-integration-tests.md`](local-integration-tests.md) | Local integration test harness |
| [`production-deploy.md`](production-deploy.md) | Production deploy runbook |
| [`qa-push-testing.md`](qa-push-testing.md) | Push notification QA |
| [`relationship-states.md`](relationship-states.md) | Relationship state vocabulary |
| [`contracts/realtime-entity-contract.json`](contracts/realtime-entity-contract.json) | Machine-checked realtime wire/projection manifest |
| [`adr/0001-capability-event-storage.md`](adr/0001-capability-event-storage.md) | Private capability events, derived reads |
| [`adr/0002-root-session-routing.md`](adr/0002-root-session-routing.md) | `/` cookie routing, landing vs WASM |
| [`adr/0003-settings-credential-linking.md`](adr/0003-settings-credential-linking.md) | Settings credential linking |
| [`adr/0004-beacon-lineage-fork.md`](adr/0004-beacon-lineage-fork.md) | `beaconFork`, lineage forward suggestions |
| [`adr/0005-unified-avatar-system.md`](adr/0005-unified-avatar-system.md) | Avatar system |
| [`adr/0006-client-sentry-observability.md`](adr/0006-client-sentry-observability.md) | Client Sentry (WASM) |
| [`adr/0007-server-sentry-observability.md`](adr/0007-server-sentry-observability.md) | Server Sentry |
| [`adr/0008-beacon-visibility-and-invite-sharing.md`](adr/0008-beacon-visibility-and-invite-sharing.md) | Relationship-scoped visibility, beacon invites |
| [`adr/0009-landing-sentry-observability.md`](adr/0009-landing-sentry-observability.md) | Landing funnel Sentry |
| [`adr/0010-attention-receipt-extension.md`](adr/0010-attention-receipt-extension.md) | Attention receipts / Updates outbox extension |

**Root vocabulary:** [`../CONTEXT.md`](../CONTEXT.md) · **Agent entry:** [`../AGENTS.md`](../AGENTS.md) · **Dev conventions:** [`../DEV_GUIDELINES.md`](../DEV_GUIDELINES.md)

## Archive

Done and superseded plans live under [`archive/plans/`](archive/plans/) (e.g. Updates tab, adaptive router, issue 73, room split, invite genealogy graph reuse, hidden-neighbor counters, topbar unification, superseded reverse-geocoding). Companion journals under [`archive/journals/`](archive/journals/). Do not implement archived plans without checking for a newer active plan.

## Maintenance

- New implementation plans go in [`plans/`](plans/). When done or superseded, move to [`archive/plans/`](archive/plans/), update this index, and fix inbound path citations.
- QA/analysis/review snapshots go in [`audits/`](audits/).
- Prefer this index + status quo over grep hits for retired paths in old branches.
- Legacy term drift check: `scripts/check-doc-drift.sh` (Registry tab, Overview tab, `coordination_status`, `beacon.state`, ChatNews, `beacon_blocker`).
- User-facing terminology: `scripts/check-user-facing-terminology.sh` (Request/Chat vs internal Beacon/room).
- After large UI refactors: refresh [`client-ui-inventory.md`](client-ui-inventory.md); verify home tab order (My Work default), beacon detail tabs (Items / People / Log).
