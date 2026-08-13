# Availability / request-receptiveness — implementation journal

## Scope

- **Objective:** implement
  [`availability-request-receptiveness-implementation-plan.md`](availability-request-receptiveness-implementation-plan.md)
  end to end for per-user request-receptiveness (availability): orthogonal `is_limited` /
  `resume_on`, V2 mutations, transactional forward gate, typed `ForwardDeliveryResult`, and
  client surfaces (own profile, other profile, graph, picker, person-forward).
- **Plan source:** [`availability-request-receptiveness-architecture.md`](availability-request-receptiveness-architecture.md)
  **rev 3**; the implementation plan records user approval on 2026-08-13 and is authoritative
  over the stale architecture front-matter `status: draft`.
- **S10 / S12 closures (plan §0, frozen for v1):**
  - **S10 — band rows:** exclude availability-paused people from the client-side capability band
    after `fetchForwardContext`; do not add a special pause line to a band row. Preserve the
    surviving band order. The server recommender remains availability-blind.
  - **S12 — entry point:** own profile only. Do not add a Settings tile.
- **Repository:** `/home/vader/MY_SRC/tentura`
- **Branch / starting HEAD:** `main` / `9c9bcf518e85668023b9afb2e8ce490a6a266c1c`
- **Started:** 2026-08-13.

## Live baseline (verified at UNIT 00)

| Item | Value |
|---|---|
| Latest migration | `m0147` |
| `packages/client/pubspec.yaml` | `5.12.1` |
| `packages/client/web/index.html` cache-buster | `flutter_bootstrap.js?v=5.12.1` |
| `packages/server/lib/env.dart` `kDefaultMinClientVersion` | `5.6.38` |

Target release for this feature (plan §0): client `5.13.0`, web cache-buster `5.13.0`, server
minimum `5.13.0` (UNIT 16). This plan owns migration `m0148`.

## Protected pre-existing worktree changes

Do not edit, stage, revert, or commit these unless a later unit proves a file is genuinely
required; in that case stop that unit and record the conflict.

```text
 M docs/README.md
 M docs/archive/journals/commitment-truth-rework-journal.md
 M docs/archive/plans/commitment-truth-rework-plan.md
 M docs/audits/room-coordination-audit.md
 M packages/server/test/api/controllers/websocket/websocket_realtime_protocol_test.mocks.dart
 M scripts/run_client_integration_web_local.sh
?? dart-defines
?? docs/plans/algorithm-invariant-suites-plan.md
?? docs/plans/availability-request-receptiveness-architecture.md
?? docs/plans/availability-request-receptiveness-implementation-plan.md
?? docs/plans/availability-review-codex.md
?? docs/plans/availability-review-grok46.md
?? docs/plans/availability-review-kimik3.md
?? docs/plans/graph-navigation-implementation-guide.md
?? docs/plans/graph-navigation-rework-plan.md
?? docs/plans/issue-100-people-graph-person-context-implementation-plan.md
?? docs/plans/issue-115-reply-to-message-implementation-journal.md
?? docs/plans/issue-115-reply-to-message-plan.md
?? docs/plans/received-reviews-trust-changes-plan.md
?? docs/plans/subjective-help-tag-evidence-architecture.md
?? docs/plans/subjective-help-tag-evidence-implementation-plan.md
?? graph-ego-neighbors-layout-issue.md
?? key.fb
?? out.key
?? product_testing_compact_buglist.md
?? product_testing_detailed_report.md
```

The architecture and implementation plan files are pre-existing and untracked. They are
authoritative for this run but must not be staged or committed by workers. This journal is
orchestrator-owned once UNIT 00 lands.

## Stop conditions (plan §1)

Stop and record `BLOCKED` instead of guessing when:

- the latest migration is no longer `m0147` or `m0148` already exists;
- the client version is no longer `5.12.1` (until UNIT 16 bumps to `5.13.0`);
- an owned file has unrelated local modifications that cannot be preserved by a narrow edit;
- rev 3 field names, mutation names, temporal rule, or typed-result fields have changed;
- a required PostgreSQL/Hasura test cannot be run in an isolated disposable database.

A changed starting Git commit alone is not a blocker. Reconcile live symbols and proceed if
the contracts and reserved identifiers still match.

## Executor contract (plan §2)

1. Work units in manifest order. Complete one unit, run its checks, append the journal, and make
   its focused local commit before starting the next unit. Do not push or deploy.
2. Preserve all pre-existing modified and untracked files. Never reset, stash, clean, or stage
   unrelated work. Stage explicit paths only.
3. Every journal entry contains unit, status, commit, exact tests, files, findings, and remaining
   work.
4. If live code contradicts this plan, do not improvise across a boundary. Record the exact
   symbol/path and stop that unit. Mechanical line-number drift is not a contradiction.
5. Server use cases depend on domain ports only. Client domain types never import data/UI. Cubits
   never import `data/service`.
6. Use Freezed where the package convention applies. Run codegen; never edit `*.g.dart`,
   `*.freezed.dart`, `*.gr.dart`, `*.config.dart`, or `_g/`.
7. Feature UI uses `context.tt`, `TenturaText`, `TenturaStatusText`, Material 3, 48 dp targets.
   No raw colors, text sizes, padding numbers, or radii. No chips/badges/icons for availability
   status.
8. Tests tagged `pg` must use an isolated disposable PostgreSQL database.

**Journal entry template:**

```markdown
## UNIT <id> — <complete|partial|blocked> — <ISO date>
COMMITS: <hash and subject, or none>
TESTS: <exact command and outcome>
FILES: <paths>
FINDINGS: <live facts that differed from the plan, or none>
REMAINING: <specific work, or none>
```

## Boundaries (plan §0, §2)

Do **not** add availability to presence, WebSockets, realtime entities, Updates, notifications,
avatars, room/member lists, contacts, global search, My Work, or Inbox. Do **not** gate existing
forwards, chats, offers, admissions, cancellations, edits, or beacon-invite acceptance. Do **not**
edit generated files by hand. Units are sequential — do not parallelize (schema/codegen, shared
`Profile`, forward contracts, and release files overlap).

## Ordered manifest

Units are sequential. Check off only after the unit's focused commit and verification.

- [x] **UNIT 00 — Journal and immutable baseline** — depends: — — commit:
  `docs: start availability implementation journal`
- [ ] **UNIT 01 — Shared calendar/view model and entities** — depends: 00 — commit:
  `feat: add availability domain model`
- [ ] **UNIT 02 — `m0148`, Drift table, Hasura visibility** — depends: 01 — commit:
  `feat(server): add user availability storage`
- [ ] **UNIT 03 — Atomic availability repository, use case, janitor** — depends: 02 — commit:
  `feat(server): add availability commands`
- [ ] **UNIT 04 — Server public-user read parity** — depends: 03 — commit:
  `feat(server): expose availability in public users`
- [ ] **UNIT 05 — Three V2 availability mutations** — depends: 03 — commit:
  `feat(server): add availability mutations`
- [ ] **UNIT 06 — Transactional forward gate and typed result** — depends: 03 — commit:
  `feat(server): enforce availability on forwards`
- [ ] **UNIT 07 — Server PostgreSQL/concurrency/API proof** — depends: 04–06 — commit:
  `test(server): prove availability invariants`
- [ ] **UNIT 08 — Client schema, date scalar, entities, read parity** — depends: 04–06 — commit:
  `feat(client): map availability data`
- [ ] **UNIT 09 — Client availability command repository and Cubit** — depends: 05, 08 — commit:
  `feat(client): wire availability commands`
- [ ] **UNIT 10 — Calendar presets, formatting, localization** — depends: 08 — commit:
  `feat(client): add availability copy and dates`
- [ ] **UNIT 11 — Own-profile control and status** — depends: 09–10 — commit:
  `feat(client): add availability profile control`
- [ ] **UNIT 12 — Other-profile and graph policy/rendering** — depends: 10 — commit:
  `feat(client): gate person request actions`
- [ ] **UNIT 13 — Picker host policy, row precedence, band exclusion** — depends: 08, 10 —
  commit: `feat(client): show availability in recipient picker`
- [ ] **UNIT 14 — Picker preselection, expiry refresh, typed delivery UX** — depends: 06, 08,
  10, 13 — commit: `feat(client): report actual forward delivery`
- [ ] **UNIT 15 — Deep-link person-forward gate** — depends: 06, 08, 10, 12 — commit:
  `feat(client): gate person forward flow`
- [ ] **UNIT 16 — Client release gate and cache-buster** — depends: 11–15 — commit:
  `chore: release availability client 5.13.0`
- [ ] **UNIT 17 — End-to-end and plan-wide closeout** — depends: 07, 16 — commit:
  `test: close availability implementation`

## Per-unit verification commands

| Unit | Verify |
|---|---|
| 01 | `dart test test/domain/availability_test.dart`; `(cd packages/client && dart run build_runner build -d && flutter test test/domain/entity/availability_test.dart)`; `(cd packages/server && dart run build_runner build -d && dart test test/domain/entity/user_availability_entity_test.dart)` |
| 02 | `(cd packages/server && dart run build_runner build -d)`; `(cd packages/server && dart test -t pg test/data/database/m0148_user_availability_migration_test.dart)`; `(cd packages/server && dart test -t pg test/data/database/beacon_cover_migration_test.dart)` |
| 03 | unit tests in owned paths (see plan) |
| 07 | `(cd packages/server && dart test -t pg test/data/repository/user_availability_repository_pg_test.dart)`; `(cd packages/server && dart test -t pg test/data/repository/forward_edge_availability_pg_test.dart)`; `(cd packages/server && dart test test/api/controllers/graphql/forward_delivery_result_test.dart)`; `(cd packages/server && dart test -x pg)` |
| 17 (plan-wide) | see **Plan-wide verification** below |

## Plan-wide verification (UNIT 17)

```bash
dart test
(cd packages/tentura_lints && dart test)
./scripts/check-custom-lints.sh packages/server
./scripts/check-custom-lints.sh packages/client
bash scripts/check-user-facing-terminology.sh
(cd packages/server && dart test -x pg)
(cd packages/server && dart test -t pg)
(cd packages/client && flutter gen-l10n)
(cd packages/client && dart run build_runner build -d)
(cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos)
(cd packages/client && flutter test --dart-define=ENV=test)
(cd packages/client && flutter test --platform chrome test/data/gql/calendar_date_serializer_test.dart)
git diff --check
```

## Final acceptance checklist (plan §4)

- [ ] Architecture D1–D30 and the S10/S12 closures in this plan are implemented.
- [ ] All three mutations are self-only, non-null, V2-routed, and use-case-owned.
- [ ] `m0148` is logged/sparse, has no backfill/creation trigger, and is in rollback simulation.
- [ ] `updated_at` and any instant are absent from public schemas, maps, and entities.
- [ ] Client/server share the UTC-calendar comparison and equality boundary.
- [ ] PostgreSQL two-connection tests prove command independence and pause/forward ordering.
- [ ] Server result, snackbar, and create confirmation report actual inserted recipients.
- [ ] Every server public-user producer and client V2 adapter carries availability.
- [ ] Host enum makes all picker render/no-render choices explicit.
- [ ] Band excludes paused candidates; unseen retains paused rows and row-count semantics.
- [ ] Own profile, other profile, graph, picker, search, and person-forward match tone/action
      rules; lineage preview and non-send surfaces do not render availability.
- [ ] No existing interaction is withdrawn or gated; invite acceptance remains availability-blind.
- [ ] EN/RU copy is Request/Chat terminology-safe and human-reviewed for gender neutrality.
- [ ] Client `5.13.0`, web cache-buster `5.13.0`, server minimum `5.13.0` match.
- [ ] All plan-wide checks pass, or remaining failures are explicitly scoped and the plan remains
      incomplete.

## Worker protocol

Every worker reads the complete source plan and this complete journal before editing, appends
progress and final evidence here, preserves the protected changes above, and commits only its
owned coherent verified steps locally.

---

## UNIT 00 — complete — 2026-08-13

COMMITS: `77a017913` docs: start availability implementation journal
TESTS: baseline inspection — `git rev-parse HEAD` → `9c9bcf518e85668023b9afb2e8ce490a6a266c1c`;
`git branch --show-current` → `main`; migration tail `m0147` (no `m0148`); client `5.12.1`; web
`flutter_bootstrap.js?v=5.12.1`; `kDefaultMinClientVersion = '5.6.38'` — all match plan §1
FILES: `docs/plans/availability-request-receptiveness-implementation-journal.md`
FINDINGS: none — live baseline matches plan §1; no stop-condition triggers
REMAINING: none for UNIT 00; UNIT 01 is next

## UNIT 00 final evidence — 2026-08-13

COMMITS: `77a017913c60dbb2c2f17f45e9b8d56214e1b033` docs: start availability implementation journal
TESTS: `git diff --check` → clean (no conflict markers); baseline reconfirmed after commit
FILES: `docs/plans/availability-request-receptiveness-implementation-journal.md`
FINDINGS: none
REMAINING: none — UNIT 01 (`feat: add availability domain model`) is next
