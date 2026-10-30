# Consolidated audit fix list (Round A4, 2026-10-30)

**Issue:** Refs [#839](https://github.com/Intersubjective/tentura/issues/839)  
**Inputs re-verified:** [A1 duplication](./2026-10-30-duplication-audit.md), [A2 feature pairs](./2026-10-30-feature-pair-audit.md), [A3 reference counts](./2026-10-30-reference-count-audit.md) (on `main`), [T1 dead tests](./2026-10-30-dead-tests-audit.md).

**Method (this round):** Checked out current branch against `main`; ran client/server codegen as in A3; re-grepped hand-written and generated `lib/`, `build.yaml`, `*.graphql`, `pubspec.yaml`, `web/`, `hook/`, `bin/`, `scripts/`, `integration_test/`, and tests where relevant.

**Codegen (2026-10-30, this run):**

```bash
cd packages/client && flutter pub get && flutter gen-l10n && dart run build_runner build -d
cd packages/server && dart pub get && dart run build_runner build -d
```

**Excluded from “delete” work (per brief + ADR):** `DORMANT(item-threads)` plumbing; `@Injectable(env: Environment.test)` mocks under `lib/**/mock/` (DI codegen scans `lib/` — relocation is a design change).

---

## Verification summary counts

| Report | Findings audited | CONFIRMED | REFUTED | CHANGED | Notes |
| :--- | ---: | ---: | ---: | ---: | :--- |
| **A1** | 15 (13 actionable + 2 dormant N/A) | 11 | 1 | 1 | 2 dormant = not findings |
| **A2** | 15 | 15 | 0 | 0 | |
| **A3** | 62 line-items (423-key l10n aggregate + 41 named rows) | 58 | 0 | 4 | See l10n aggregate row |
| **T1** | 53 | 47 | 4 | 2 | |
| **Total** | **145** | **131** | **5** | **7** | De-duplicated work items below |

---

## Verification table

Status: **CONFIRMED** = claim holds on current tree; **REFUTED** = claim false; **CHANGED** = partly true, renamed, or scope differs.

### A1 — Duplication & hygiene

| ID | Report | Status | One-line evidence |
| :--- | :--- | :--- | :--- |
| A1-1.1 | A1 | CONFIRMED | Duplicate `kUserHandleRegExp` / `isValidUserHandleFormat` in `lib/consts.dart` and `packages/server/lib/consts/user_handle_consts.dart` (same pattern; server + client both call it). |
| A1-1.2 | A1 | CONFIRMED | Path strip `raw.split(RegExp(r'[/\\]')).last.trim()` in both `packages/server/lib/utils/sanitized_attachment_name.dart:3` and `domain/util/attachment_filename.dart:3` (different suffix sanitization). |
| A1-1.3 | A1 | CONFIRMED | Whitespace collapse + 160-rune truncation in client `features/beacon_threads/ui/util/room_reply_excerpt.dart` and server `domain/util/room_reply_excerpt.dart`; both heavily used in prod. |
| A1-1.4 | A1 | CHANGED | Client `pending_attachments.dart` `_mimeFromExtension`; server `beacon_room_case.dart` `_normalizeAttachmentMime` (~2320) — same fallback idea, different names/signatures. |
| A1-1.5 | A1 | CONFIRMED | Two `PostSummary` classes: client `features/inbox/domain/entity/post_summary.dart` vs server `domain/entity/post_summary.dart`; client lacks `forwardedById` / `lastMessageAt`. |
| A1-1.6 | A1 | CONFIRMED | `RegExp(r'^[0-9]+$')` as `_decimalRevision` in client `invalidation_service.dart:242` and server `websocket_path_entity_changes.dart:17`. |
| A1-2.1 | A1 | CONFIRMED | `@Deprecated` `myWorkMasterDetailSeparatorWidth` at `tentura_responsive_scope.dart:132`; `rg` → only definition + `test/design_system/my_work_layout_packing_test.dart`. |
| A1-2.2 | A1 | CONFIRMED | `deskMasterPaneWidth`, `kDeskDetailMinWidth`, `deskDetailBudget`, `deskFitsMasterDetail` — no prod callers outside `tentura_responsive_scope.dart` + packing test. |
| A1-2.3 | A1 | CHANGED | `@Deprecated` `selectNode` still called inside `graph_cubit.dart` and from tests/e2e (`integration_test/support/e2e_test_helpers.dart`); not dead, still deprecated. |
| A1-3.1 | A1 | CONFIRMED | U18c retired-totals comment still at `packages/client/lib/domain/attention/attention_case.dart` (~627). |
| A1-3.2 | A1 | CONFIRMED | Legacy 30° layout comment at `features/graph/domain/layout/radial_hop_positions.dart` (~215). |
| A1-4.1 | A1 | CONFIRMED | `ForwardsGraphRepository` + `GraphRepository` both implement `GraphSourceRepository`; forwards screen injects `ForwardsGraphRepository`, default cubit uses `GraphRepository`. |
| A1-4.2 | A1 | CONFIRMED | Both `CoordinationItemRepositoryPort` and `CoordinationRepositoryPort` registered in `di.config.dart` and injected from separate use cases. |
| A1-5.1 | A1 | N/A | DORMANT `thread_item_id` — intentional (ADR 0013). |
| A1-5.2 | A1 | N/A | DORMANT client `threadItemId` filter — intentional. |

### A2 — Feature-pair duplication

| ID | Report | Status | One-line evidence |
| :--- | :--- | :--- | :--- |
| A2-1.1 | A2 | CONFIRMED | Same scroll threshold at `activity_stream_view.dart:311` and `updates_feed_pane.dart:112` (`maxScrollExtent - sectionGap`). |
| A2-1.2 | A2 | CONFIRMED | Parallel load-more spinners: `_ActivityLoadMoreIndicator` vs `_LoadMoreIndicator` (same padding + adaptive indicator). |
| A2-1.3 | A2 | CONFIRMED | Three empty-state stacks: `ForYouEmptyState`, `MyWorkEmptyBody`, `_EmptyUpdates` still separate. |
| A2-1.4 | A2, A1-1.5 | CONFIRMED | `posts_repository.dart:46-49` merges `lastActivityAt`/`lastMessageAt`; server entity keeps both timestamps. |
| A2-2.1 | A2 | CONFIRMED | Request forward uses `beaconViewOpenForwardThenMaybeNudgeOfferHelp`; Post screen pushes `ForwardBeaconRoute` without nudge helper. |
| A2-2.2 | A2 | CONFIRMED | Post actions duplicated in `post_view_screen.dart` overflow and `post_info_sheet.dart`. |
| A2-2.3 | A2 | CONFIRMED | `_Overflow` uses `DateTime.now()` at `post_view_screen.dart:592` while screen passes `cubit.now()` as `lifetimeNow` elsewhere. |
| A2-3.1 | A2 | CONFIRMED | Request recipients embed `ForwardRecipientPicker`; Post bud uses local `_InviteeRow` checkbox list. |
| A2-3.2 | A2 | CONFIRMED | Parallel candidate-load paths: `ForwardCubit._loadCandidates` vs `BeaconCreateCubit` post-bud invite step. |
| A2-4.1 | A2 | CONFIRMED | Client Freezed `AuthorInvite` (string status, optional fields) vs server class (required lineage IDs, int status codes). |
| A2-4.2 | A2, A1-1.5 | CONFIRMED | Same as A2-1.4 / A1-1.5 field drift. |
| A2-5.1 | A2 | CONFIRMED | Identical readability guard in `attention_repository.dart:396-400` and `attention_sweep_repository.dart:659-663`. |
| A2-5.2 | A2 | CONFIRMED | `author_invite_repository.dart` inline `beacon_can_read_content`; attention uses shared prelude in `attention_dismissible_sql.dart:107`. |
| A2-6.1 | A2 | CONFIRMED | My Work empty body still bespoke vs `TenturaEmptyState` on Posts tab. |
| A2-6.2 | A2 | CONFIRMED | `BeaconCardPillReadOnly` in `beacon_operational_header_card.dart:326` vs shared `BeaconCardPill` in `beacon_card_primitives.dart`. |

### A3 — Reference counts

| ID | Report | Status | One-line evidence |
| :--- | :--- | :--- | :--- |
| A3-1-aggregate | A3 | CHANGED | **2930** EN/RU keys, **0** parity drift; **423** keys with **0** `lib/` hits (**391** deletable + **32** test-only); prefix clusters `beacon*` 155, `coordination*` 37, `inbox*` 31, `my*` 26 (re-run Python in A3 doc). |
| A3-1-1 … A3-1-15 | A3 | CONFIRMED | Sample keys (`actionHide`, `beaconViewButton`, `buttonCrop`, `beaconHudSituationPanelTitle`, …) — `rg` → **0** hits under `packages/client/lib` (excluding `l10n/`). |
| A3-1b-aggregate | A3 | CONFIRMED | **32** keys with lib **0**, test **≥1** (e.g. `threadGeneralTitle` lib 0 / test 2). |
| A3-1b-1 … A3-1b-4 | A3 | CONFIRMED | Named test-only keys match A3 table (`threadGeneralTitle`, `inboxForwardedByLabel`, `myWorkStatusNeedsMoreHelp`, `constellationAbsenceFilterHidden`). |
| A3-2-1 … A3-2-7 | A3 | CONFIRMED | Seven `packages/client/web/icons/web_*dp.png` files exist; `rg -l 'web_24dp' packages/client` → **0** non-binary refs. |
| A3-2-8 | A3 | CONFIRMED | `web/.well-known/assetlinks.json` exists; `rg -l assetlinks packages/client` → **0**. |
| A3-2b | A3 | CONFIRMED | `pubspec.yaml` asset globs still referenced from `lib/` (spot-check unchanged). |
| A3-3-1 | A3 | CHANGED | `UserSubscribe` / `GUserSubscribeReq`: **0** use in hand-written `lib/`; **1** use in `integration_test/support/e2e_test_helpers.dart:1291` (not prod-dead). |
| A3-3-2 | A3 | CONFIRMED | `polling_model.graphql` fragment; no spreads in other `.graphql`; no non-`_g` `lib/` consumers. |
| A3-4-1 … A3-4-5 | A3 | CONFIRMED | Master-detail symbols — same as A1-2.1/A1-2.2. |
| A3-4-6 | A3 | CONFIRMED | `BeaconActivityEventVisibilityBits` — **1** hit in `lib/` (declaration); **10** in tests. |
| A3-4-7 … A3-4-8 | A3 | CONFIRMED | Same as A3-3-1, A3-3-2. |
| A3-4-9 … A3-4-12 | A3 | CONFIRMED | Test mocks in `lib/` — **0** prod callers; wired via `di.config.dart` `@Injectable(test)` (keep until relocation design). |
| A3-5-1 | A3 | CONFIRMED | `scrollable_positioned_list` in pubspec; `rg 'ScrollablePositionedList\|scrollable_positioned_list' packages/client/{lib,bin,tool}` → **0**. |
| A3-5-2 | A3 | CONFIRMED | `gql_dedupe_link` — **0** imports; dedupe via `CancellableDedupeLink` in client. |
| A3-5-3 | A3 | CONFIRMED | `html` in pubspec; `rg 'package:html/' packages/client/{lib,bin,tool,hook}` → **0**. |
| A3-5-4 | A3 | CONFIRMED | Client `latlong2` direct dep; `rg 'package:latlong2/' packages/client/{lib,bin,tool}` → **0** (coordinates via `tentura_root`). |
| A3-5-5 | A3 | CONFIRMED | Server `latlong2` direct dep; `rg 'package:latlong2/' packages/server/{lib,bin,tool}` → **0**. |
| A3-5-6 | A3 | CONFIRMED | `hooks` + `pubspec_parse` used under `packages/client/hook/build/*.dart`. |
| A3-5-7 | A3 | CONFIRMED | `drift_dev` not imported from `lib/`; used in `test/drift/` + `build.yaml`. |
| A3-5-8 | A3 | CONFIRMED | `json_annotation` — no direct `lib/` imports (codegen/transitive); keep. |
| A3-X-UpdatesScreen | A3 appendix | REFUTED | `UpdatesRoute` registered `root_router.dart:173`; generated `root_router.gr.dart`. |
| A3-X-TimestamptzSerializer | A3 appendix | REFUTED | Registered in `packages/client/build.yaml:161`; `serializers.gql.dart` adds `TimestamptzSerializer()`. |

### T1 — Dead / unreachable tests

| ID | Report | Status | One-line evidence |
| :--- | :--- | :--- | :--- |
| T1-1.1 | T1 | CONFIRMED | `migration_test.dart:53` — `skip: 'TODO: wire data-integrity fixtures…'`. |
| T1-1.2 | T1 | CONFIRMED | `constellation_timeline_spans_test.dart` — `markTestSkipped('VM Timeline capture needs…')`. |
| T1-1.3 | T1 | CONFIRMED | `wasm_preload_artifacts_test.dart` — conditional skip when Node missing. |
| T1-1.4 | T1 | CONFIRMED | `sw_update_reload_test.dart` — conditional skip when Node missing. |
| T1-1.5 | T1 | CONFIRMED | `mutation_beacon_people_test.dart:111` — conditional Postgres skip. |
| T1-1.6 … T1-1.11 | T1 | CONFIRMED | Six Hasura pg files still contain empty `test('Docker unavailable', …, skip: 'Docker not available')`. |
| T1-2.1 | T1 | CONFIRMED | `widget_test.dart:8` — `expect(true, isTrue)`. |
| T1-2.2 | T1 | CONFIRMED | Same skipped migration test body empty (pairs with T1-1.1). |
| T1-2.3 … T1-2.8 | T1 | CONFIRMED | Same six Docker placeholder tests — empty bodies. |
| T1-3.1 | T1 | CHANGED | `legacyClosureOpenReason` used in prod `beacon_activity_event_presenter.dart:132,259` and tests — not test-only. |
| T1-4.1 | T1 | CONFIRMED | `BeaconActivityEventVisibilityBits` — prod lib declaration only; tests reference. |
| T1-4.2 … T1-4.5 | T1 | CONFIRMED | Mocks in `lib/data/repository/mock/` — **0** non-DI prod refs; `@Injectable(test)` in `di.config.dart`. |
| T1-5.1 … T1-5.2 | T1 | CONFIRMED | Root `test/domain/availability_test.dart` duplicates client/server availability tests. |
| T1-5.3 … T1-5.4 | T1 | CONFIRMED | `attention_intent_case_test.dart` — three tests named `excludes candidate when actor blocked them` (lines 498, 534, 604). |
| T1-5.5 … T1-5.6 | T1 | CONFIRMED | `beacon_case_media_test.dart` duplicate names at 243 & 358 (and 255 & 370). |
| T1-5.7 … T1-5.9 | T1 | CONFIRMED | `beacon_fact_card_case_edit_test.dart` duplicate test names at 194/244, 200/251, 205/256. |
| T1-6.1 … T1-6.11 | T1 | CONFIRMED | Eleven dart files under repo-root `test/` (`find /workspace/test -name '*.dart'`); CI runs package tests only (`pipeline.yml` client/server shards, no root `test/`). |
| T1-6.12 | T1 | REFUTED | `attention_read_clear_axis_test.dart` tagged `@Tags(['repo-files'])`, not `pg` — runs in CI repo-files shard. |
| T1-6.13 | T1 | REFUTED | `updates_event_contract_test.dart` — `@Tags(['repo-files'])`. |
| T1-6.14 | T1 | REFUTED | `profile_untrust_mutation_contract_test.dart` — `@Tags(['repo-files'])`. |
| T1-6.15 | T1 | REFUTED | `inbox_provenance_latest_note_test.dart` — `@Tags(['repo-files'])`. |
| T1-6.16 | T1 | CONFIRMED | `populated_tag_delete_screen_pg_test.dart` — `@Tags(['pg', 'repo-files'])`; client CI uses `--exclude-tags pg`. |
| T1-7.1 | T1 | CONFIRMED | `rg 'tentura_q8s8_beacon_operational_header_pre_mount'` → **0** imports (file self-contained duplicate widgets). |
| T1-7.2 … T1-7.3 | T1 | CONFIRMED | Root `test/fixtures/agents_alloy_memory_*.txt` — **0** refs. |

---

## Ordered work items

Low-risk deletions first, then consolidations, then design changes. Each item is independently mergeable.

### Low-risk deletions & CI hygiene

#### W1 — Drop unused client pub dependencies

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | S |
| **Risk** | low — zero `lib/`/`bin/`/`tool` imports |
| **Files** | `packages/client/pubspec.yaml` |
| **Steps** | Remove `scrollable_positioned_list`, `gql_dedupe_link`, `html`; run `flutter pub get`; ensure no comment-only references need updating in tests. |
| **Verify** | `cd packages/client && flutter pub get && flutter analyze --no-fatal-infos`; `../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test test/data/service/remote_api_client/graphql_fetch_cancellation_test.dart` |
| **Sources** | A3-5-1, A3-5-2, A3-5-3 |

#### W2 — Remove unreferenced web icon PNGs

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | S |
| **Risk** | low — no repo references |
| **Files** | `packages/client/web/icons/web_{24,32,36,48,64,96,512}dp.png` |
| **Steps** | Delete seven files; confirm PWA/manifest still uses committed launcher assets. |
| **Verify** | `rg 'web_24dp' packages/client` → 0; optional `flutter build web` smoke |
| **Sources** | A3-2-1 … A3-2-7 |

#### W3 — Delete orphan GraphQL `PollingModel` fragment

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | S |
| **Risk** | low — no spreads, no lib use |
| **Files** | `packages/client/lib/data/gql/polling_model.graphql`; regenerate `_g/*` locally (do not commit generated output) |
| **Steps** | Remove `.graphql`; `dart run build_runner build -d`; confirm serializers shrink. |
| **Verify** | `rg 'PollingModel' packages/client/lib --glob '!**/_g/**'` → 0; `flutter analyze --no-fatal-infos` |
| **Sources** | A3-3-2, A3-4-8 |

#### W4 — Remove empty “Docker unavailable” placeholder tests

| Field | Value |
| :--- | :--- |
| **Scope** | server |
| **Size** | S |
| **Risk** | low — fixtures already skip when Docker missing |
| **Files** | `packages/server/test/api/hasura_beacon_expires_at_pg_test.dart`, `hasura_vote_beacon_post_guard_pg_test.dart`, `help_offer_post_hasura_pg_test.dart`, `post_hasura_read_pg_test.dart`, `post_inbox_hasura_pg_test.dart`, `post_room_block_hasura_pg_test.dart` |
| **Steps** | Delete the empty skipped `Docker unavailable` test block in each file. |
| **Verify** | `cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test test/api/post_hasura_read_pg_test.dart --exclude-tags pg` (or tagged pg file with disposable fixture) |
| **Sources** | T1-1.6 … T1-1.11, T1-2.3 … T1-2.8 |

#### W5 — Remove placeholder `widget_test.dart`

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | S |
| **Risk** | low |
| **Files** | `packages/client/test/widget_test.dart` |
| **Steps** | Delete file or replace with real smoke test (prefer delete if covered elsewhere). |
| **Verify** | `flutter test` client gates shard unaffected |
| **Sources** | T1-2.1 |

#### W6 — Delete orphan fixtures

| Field | Value |
| :--- | :--- |
| **Scope** | CI/test-infra |
| **Size** | S |
| **Risk** | low |
| **Files** | `packages/client/test/fixtures/tentura_q8s8_beacon_operational_header_pre_mount.dart`, `test/fixtures/agents_alloy_memory_5zq_lesson_snippet.txt`, `test/fixtures/agents_alloy_memory_tail_unified_after_5zq.txt` |
| **Steps** | Delete three files. |
| **Verify** | `rg 'tentura_q8s8_beacon_operational_header_pre_mount\|agents_alloy_memory'` → 0 |
| **Sources** | T1-7.1 … T1-7.3 |

#### W7 — Root `test/` suite: delete duplicates and relocate the rest

| Field | Value |
| :--- | :--- |
| **Scope** | CI/test-infra |
| **Size** | M |
| **Risk** | low–medium — must pick correct package per test topic |
| **Files** | `test/mention_span_validation_test.dart`, `test/domain/**/*.dart` (11 files), delete `test/domain/availability_test.dart` outright |
| **Steps** | Move each file into `packages/client/test` or `packages/server/test` mirroring existing duplicates; delete availability duplicate; optionally add CI guard script later (out of scope unless requested). |
| **Verify** | Per moved file: `scripts/run_tests.sh client-files <path>` or `server-files <path>`; `rg '^test/' scripts/ci_changes.py` unchanged |
| **Sources** | T1-5.1, T1-5.2, T1-6.1 … T1-6.11 |

#### W8 — Remove deprecated master-detail layout helpers

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | S |
| **Risk** | low — prod Inbox/My Work no longer uses geometry |
| **Files** | `packages/client/lib/design_system/tentura_responsive_scope.dart`, `packages/client/test/design_system/my_work_layout_packing_test.dart` |
| **Steps** | Remove `myWorkMasterDetailSeparatorWidth`, `deskMasterPaneWidth`, `kDeskDetailMinWidth`, `deskDetailBudget`, `deskFitsMasterDetail`; delete or rewrite packing test. |
| **Verify** | `flutter analyze --no-fatal-infos`; `flutter test test/design_system/` |
| **Sources** | A1-2.1, A1-2.2, A3-4-1 … A3-4-5 |

#### W9 — Move `BeaconActivityEventVisibilityBits` to test support

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | S |
| **Risk** | low |
| **Files** | `packages/client/lib/domain/entity/beacon_activity_event_consts.dart`, affected tests under `test/features/beacon_*` |
| **Steps** | Move class to `test/support/` (or test-only export); keep prod consts file for wire reasons still used in presenter. |
| **Verify** | `flutter test test/features/beacon_view/beacon_activity_sheet_test.dart` |
| **Sources** | T1-4.1, A3-4-6 |

#### W10 — Prune unused l10n keys (batched by prefix)

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | L (split into ~10 PRs) |
| **Risk** | low–medium — confirm product retired copy; skip 32 test-only keys until tests updated |
| **Files** | `packages/client/l10n/app_en.arb`, `app_ru.arb`; run `flutter gen-l10n` locally |
| **Steps** | Batch ~40 keys per PR by prefix (`beaconHud*`, `beaconClosurePanel*`, `coordination*`, …); remove EN+RU; regenerate l10n; update any accidental test-only keys in same batch. Full deletable list: reproduce A3 Python script (**391** keys). |
| **Verify** | `flutter gen-l10n`; `flutter test test/l10n/`; `bash scripts/check-user-facing-terminology.sh` |
| **Sources** | A3-1-aggregate, A3-1-1 … A3-1-15 |

#### W11 — Resolve `UserSubscribe` GraphQL op

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | S |
| **Risk** | medium — e2e helper still calls it |
| **Files** | `packages/client/lib/data/gql/user_subscribe.graphql`, `integration_test/support/e2e_test_helpers.dart` |
| **Steps** | Either wire a thin repository used in prod **or** delete op and switch e2e to HTTP/Hasura helper; regenerate codegen. |
| **Verify** | `rg 'GUserSubscribeReq' packages/client/lib --glob '!**/_g/**'`; integration test path if kept |
| **Sources** | A3-3-1, A3-4-7 |

#### W12 — Drop redundant `latlong2` direct dependencies

| Field | Value |
| :--- | :--- |
| **Scope** | shared |
| **Size** | S |
| **Risk** | low — verify workspace still resolves via `tentura_root` |
| **Files** | `packages/client/pubspec.yaml`, `packages/server/pubspec.yaml` |
| **Steps** | Remove direct `latlong2` entries; `pub get` in workspace root. |
| **Verify** | Client + server `dart analyze` / `flutter analyze` on packages |
| **Sources** | A3-5-4, A3-5-5 |

#### W13 — Document or remove `assetlinks.json`

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | S |
| **Risk** | medium — may be deployed out-of-band |
| **Files** | `packages/client/web/.well-known/assetlinks.json`, deploy docs |
| **Steps** | Confirm with release process; delete or add README in `web/.well-known/`. |
| **Verify** | N/A (docs/deploy) |
| **Sources** | A3-2-8 |

#### W14 — Move `drift_dev` to dev_dependencies (client)

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | S |
| **Risk** | low |
| **Files** | `packages/client/pubspec.yaml` |
| **Steps** | Relocate `drift_dev` to `dev_dependencies`; confirm `build.yaml` still resolves. |
| **Verify** | `dart run build_runner build -d` in client; migration tests |
| **Sources** | A3-5-7 |

#### W15 — Deduplicate server test cases (same name/body)

| Field | Value |
| :--- | :--- |
| **Scope** | server |
| **Size** | S |
| **Risk** | low |
| **Files** | `packages/server/test/domain/attention/attention_intent_case_test.dart`, `beacon_case_media_test.dart`, `beacon_fact_card_case_edit_test.dart` |
| **Steps** | Merge duplicate blocks or rename with distinct scenarios. |
| **Verify** | `scripts/run_tests.sh server-files test/domain/attention/attention_intent_case_test.dart` (and siblings) |
| **Sources** | T1-5.3 … T1-5.9 |

### Consolidations (medium risk)

#### W16 — Centralize inbox readability SQL guard

| Field | Value |
| :--- | :--- |
| **Scope** | server |
| **Size** | M |
| **Risk** | high — undo vs feed visibility must stay aligned |
| **Files** | `packages/server/lib/data/repository/attention_repository.dart`, `attention_sweep_repository.dart`, `attention_dismissible_sql.dart` |
| **Steps** | Extract shared `undoOutcomeReadabilityGuard` / eligible-row fragment; replace duplicated literals. |
| **Verify** | `scripts/run_tests.sh server-files test/data/repository/attention_repository_pg_test.dart test/data/repository/attention_sweep_repository_pg_test.dart` |
| **Sources** | A2-5.1 |

#### W17 — Shared SQL fragment for invite readability

| Field | Value |
| :--- | :--- |
| **Scope** | server |
| **Size** | M |
| **Risk** | medium — document intentional tombstone exclusion |
| **Files** | `author_invite_repository.dart`, `attention_dismissible_sql.dart` |
| **Steps** | Introduce named fragment; comment where invite path excludes tombstone OR branch. |
| **Verify** | Server pg tests touching invites + attention |
| **Sources** | A2-5.2 |

#### W18 — Unify `PostSummary` model and mapping

| Field | Value |
| :--- | :--- |
| **Scope** | shared |
| **Size** | L |
| **Risk** | medium — inbox sort/display semantics |
| **Files** | `lib/domain/entity/post_summary.dart` (new), client inbox entity + `posts_repository.dart`, server `domain/entity/post_summary.dart`, GraphQL fragments |
| **Steps** | Add shared entity with `forwardedById`, `lastMessageAt`, `lastActivityAt`; stop collapsing timestamps in `_toEntity`; align server JSON mapping. |
| **Verify** | Client `flutter test test/features/inbox/`; server post/inbox pg tests |
| **Sources** | A1-1.5, A2-1.4, A2-4.2 |

#### W19 — Single clock on Post view overflow

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | S |
| **Risk** | medium — mute/lifetime UX |
| **Files** | `packages/client/lib/features/post_view/ui/screen/post_view_screen.dart` |
| **Steps** | Pass `lifetimeNow` into `_Overflow`; replace `DateTime.now()` for mute checks. |
| **Verify** | `flutter test test/features/post_view/` |
| **Sources** | A2-2.3 |

#### W20 — Post action menu single builder

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | M |
| **Risk** | medium |
| **Files** | `post_view_screen.dart`, `post_info_sheet.dart`, new small helper under `post_view/ui/` |
| **Steps** | Extract `PostActionMenu.items(PostViewState, …)` consumed by overflow + sheet. |
| **Verify** | `flutter test test/features/post_view/` |
| **Sources** | A2-2.2 |

#### W21 — Shared forward opener (Request nudge vs Post)

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | S |
| **Risk** | low–medium — product intent for Post nudge |
| **Files** | `beacon_view_forward_overflow.dart`, `post_view_screen.dart`, shared util |
| **Steps** | Add `openForwardForBeacon(context, id, {ForwardTargetProfile profile})` wrapping route + optional nudge. |
| **Verify** | Widget tests for beacon_view + post_view forward affordances |
| **Sources** | A2-2.1 |

#### W22 — Scroll pagination + load-more indicator

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | S |
| **Risk** | low |
| **Files** | `activity_stream_view.dart`, `updates_feed_pane.dart`, `design_system/` or `ui/widget/` |
| **Steps** | Extract shared scroll listener + `TenturaFeedLoadMoreIndicator`. |
| **Verify** | `flutter test test/features/inbox/` and `test/features/updates/` |
| **Sources** | A2-1.1, A2-1.2 |

#### W23 — Empty-state consolidation (Inbox / My Work / Updates)

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | M |
| **Risk** | medium — design-system lint surface |
| **Files** | `for_you_empty_state.dart`, `my_work_empty_body.dart`, `updates_feed_pane.dart` |
| **Steps** | Migrate to `TenturaEmptyState` / `CaughtUpPanel` parameters. |
| **Verify** | Feature widget tests + custom lint on touched UI |
| **Sources** | A2-1.3, A2-6.1 |

#### W24 — Consolidate user-handle validation in `tentura_root`

| Field | Value |
| :--- | :--- |
| **Scope** | shared |
| **Size** | S |
| **Risk** | low |
| **Files** | `lib/consts.dart`, `packages/server/lib/consts/user_handle_consts.dart`, server tests |
| **Steps** | Server imports root consts; delete duplicate file or re-export. |
| **Verify** | `dart test test/consts/user_handle_consts_test.dart` (server) |
| **Sources** | A1-1.1 |

#### W25 — Merge attachment filename path utilities (server)

| Field | Value |
| :--- | :--- |
| **Scope** | server |
| **Size** | S |
| **Risk** | low |
| **Files** | `utils/sanitized_attachment_name.dart`, `domain/util/attachment_filename.dart` |
| **Steps** | Shared private path basename helper; keep distinct public APIs. |
| **Verify** | Server unit tests for attachment naming |
| **Sources** | A1-1.2 |

#### W26 — Shared room-reply excerpt helper (`tentura_root`)

| Field | Value |
| :--- | :--- |
| **Scope** | shared |
| **Size** | M |
| **Risk** | medium — rune boundary behavior |
| **Files** | new `lib/domain/util/room_reply_excerpt.dart`, client UI wrapper, server util |
| **Steps** | Extract core truncation; client keeps poll/question wrapper. |
| **Verify** | `room_reply_excerpt_test.dart` client + server |
| **Sources** | A1-1.3 |

#### W27 — Shared attachment MIME fallback map

| Field | Value |
| :--- | :--- |
| **Scope** | shared |
| **Size** | M |
| **Risk** | medium |
| **Files** | `lib/` util, `pending_attachments.dart`, `beacon_room_case.dart` |
| **Steps** | Single extension→MIME table used by client picker + server normalize. |
| **Verify** | Client widget tests + server `beacon_room_case` media tests |
| **Sources** | A1-1.4 |

#### W28 — Shared decimal revision regexp

| Field | Value |
| :--- | :--- |
| **Scope** | shared |
| **Size** | S |
| **Risk** | low |
| **Files** | `lib/consts.dart` or websocket consts, client `invalidation_service.dart`, server WS handler |
| **Steps** | Export `kDecimalRevisionPattern`; import both sides. |
| **Verify** | Client invalidation tests + server websocket tests |
| **Sources** | A1-1.6 |

#### W29 — `BeaconCardPillReadOnly` → design-system variant

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | S |
| **Risk** | low |
| **Files** | `beacon_card_primitives.dart`, `beacon_operational_header_card.dart` |
| **Steps** | Add read-only/muted style to `BeaconCardPill`; delete duplicate widget. |
| **Verify** | `flutter test test/features/beacon_view/` |
| **Sources** | A2-6.2 |

#### W30 — Stale comments (U18c, graph 30°)

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | S |
| **Risk** | low |
| **Files** | `attention_case.dart`, `radial_hop_positions.dart` |
| **Steps** | Update comments to current architecture naming. |
| **Verify** | Docs-only; `flutter analyze` on package |
| **Sources** | A1-3.1, A1-3.2 |

### Design changes (defer or plan explicitly)

#### W31 — Relocate Injectable test mocks out of `lib/`

| Field | Value |
| :--- | :--- |
| **Scope** | shared |
| **Size** | L |
| **Risk** | high — DI/codegen must still register test env |
| **Files** | `packages/client/lib/data/repository/mock/*`, `packages/server/lib/data/repository/mock/*`, `build.yaml` / injectable config |
| **Steps** | Design injectable scan path or manual test module; move mocks to `test/support/` without breaking `ENV=test`. |
| **Verify** | Full `flutter test --dart-define=ENV=test` + server unit suite |
| **Sources** | T1-4.2 … T1-4.5, A3-4-9 … A3-4-12 |

#### W32 — Graph repository unification

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | L |
| **Risk** | high |
| **Files** | `graph_repository.dart`, `forwards_graph_repository.dart`, `graph_cubit.dart`, DI |
| **Steps** | Single repository with mode flag or strategy; preserve forwards-specific fetch APIs. |
| **Verify** | `flutter test test/features/graph/` |
| **Sources** | A1-4.1 |

#### W33 — Coordination port boundary refactor

| Field | Value |
| :--- | :--- |
| **Scope** | server |
| **Size** | L |
| **Risk** | high |
| **Files** | `coordination_*_repository_port.dart`, repositories, `beacon_room_case.dart`, `coordination_case.dart` |
| **Steps** | Document overlap; merge or narrow ports with migration plan. |
| **Verify** | `scripts/run_tests.sh server-regression` |
| **Sources** | A1-4.2 |

#### W34 — Canonical `AuthorInvite` DTO in `tentura_root`

| Field | Value |
| :--- | :--- |
| **Scope** | shared |
| **Size** | L |
| **Risk** | high — wire encoding int vs string |
| **Files** | `lib/domain/entity/`, client Freezed, server entity, GraphQL mappers |
| **Steps** | Introduce explicit API subset; map lineage fields; align status encoding. |
| **Verify** | Client + server author-invite test suites |
| **Sources** | A2-4.1 |

#### W35 — Post bud invite vs forward picker shared rows

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | L |
| **Risk** | medium |
| **Files** | `post_bud_invite_step.dart`, `forward_recipient_picker.dart`, beacon_create widgets |
| **Steps** | Shared checkbox+note row or embedded picker mode. |
| **Verify** | `flutter test test/features/beacon_create/` |
| **Sources** | A2-3.1 |

#### W36 — Shared candidate-load state machine

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | M |
| **Risk** | medium |
| **Files** | `forward_cubit.dart`, `beacon_create_cubit.dart` |
| **Steps** | Sealed `CandidateLoadState` + mappers from forward vs bud APIs. |
| **Verify** | Forward + beacon_create bloc tests |
| **Sources** | A2-3.2 |

#### W37 — Wire Drift migration data-integrity test

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | M |
| **Risk** | medium |
| **Files** | `packages/client/test/drift/tentura/migration_test.dart` |
| **Steps** | Replace skip with fixtures from drift schema helper. |
| **Verify** | `flutter test test/drift/tentura/migration_test.dart` |
| **Sources** | T1-1.1, T1-2.2 |

#### W38 — Client pg-tagged UI test strategy

| Field | Value |
| :--- | :--- |
| **Scope** | CI/test-infra |
| **Size** | M |
| **Risk** | medium |
| **Files** | `populated_tag_delete_screen_pg_test.dart`, CI workflow or refactor to mocks |
| **Steps** | Either mock DB in test or document as manual-only; only **one** client file still `@Tags(['pg'])`. |
| **Verify** | CI client shard with/without `pg` label |
| **Sources** | T1-6.16 |

#### W39 — Deprecate `GraphCubit.selectNode` migration

| Field | Value |
| :--- | :--- |
| **Scope** | client-only |
| **Size** | M |
| **Risk** | medium |
| **Files** | `graph_cubit.dart`, tests, e2e helpers |
| **Steps** | Route callers to `handleNodeTap` / public API; then remove deprecated methods. |
| **Verify** | `flutter test test/features/graph/` + e2e graph flows |
| **Sources** | A1-2.3 |

#### W40 — Review `legacyClosureOpenReason` lifecycle

| Field | Value |
| :--- | :--- |
| **Scope** | shared |
| **Size** | M |
| **Risk** | medium — still referenced in presenter |
| **Files** | `beacon_activity_event_consts.dart`, presenter, server migrations |
| **Steps** | Confirm DB still emits `reviewWindowOpened`; remove fallback only after migration proof. |
| **Verify** | Client presenter tests + server activity tests |
| **Sources** | T1-3.1 |

---

## Refuted — do not act (on false premise)

| ID | Why |
| :--- | :--- |
| **A1-2.3 (as “unused”)** | `selectNode` remains on the hot path inside `GraphCubit` and e2e/tests — deprecation cleanup ≠ dead-code deletion. |
| **T1-6.12 – T1-6.15** | Four “client pg tests excluded from CI” files are `@Tags(['repo-files'])` and **do** run in CI repo-files shards; only comments mention pg server tests. |
| **A3-X-UpdatesScreen** | Updates tab route is registered and used (`UpdatesRoute` / `InboxScreen` push). |
| **A3-X-TimestamptzSerializer** | Registered in Ferry `build.yaml` custom serializers. |
| **T1-4.2 – T1-4.5 (as “move mocks to test/ now”)** | Mocks are required for Injectable test env from `lib/` — treat as **W31** design change, not drive-by deletion. |

---

## Appendix — l10n deletable keys (391)

Reproduce after edits:

```bash
python3 - <<'PY'
import re, subprocess
from pathlib import Path
C = Path("packages/client")
keys = [m.group(1) for m in re.finditer(r'\n  "([^"@][^"]*)"\s*:', (C/"l10n/app_en.arb").read_text())]
for key in keys:
    if subprocess.run(["rg","-q",re.escape(key),str(C/"lib"),"--glob","!**/l10n/**"], cwd=".").returncode: continue
    if subprocess.run(["rg","-q",re.escape(key),str(C/"test")], cwd=".").returncode: continue
    print(key)
PY
```

Split batches per **W10** (~40 keys × ~10 PRs). Do **not** delete the **32** test-only keys until contract tests are updated (see A3-1b).

---

*Round A4 completed with documentation only; no application source edits. `flutter analyze` on `packages/client` after codegen: **3551** issues (pre-existing baseline).*
