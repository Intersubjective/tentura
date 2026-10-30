# Reference-count audit (Round A3, 2026-10-30)

**Issue:** Refs [#836](https://github.com/Intersubjective/tentura/issues/836)  
**Method:** After full client/server codegen, count references across hand-written `lib/`, generated outputs (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `di.config.dart`, `_g/*.gql.dart`, `lib/ui/l10n/*.dart`), config (`build.yaml`, `*.graphql`, `pubspec.yaml`), and repo roots (`web/`, `tool/`, `bin/`, `scripts/`, `integration_test/`). Tests are excluded for l10n and public-symbol “production unused” claims unless noted.

**Codegen run (2026-10-30):**

```bash
cd packages/client && flutter pub get && flutter gen-l10n && dart run build_runner build -d
cd packages/server && dart pub get && dart run build_runner build -d
```

**Prior rounds:** [A1 duplication](./2026-10-30-duplication-audit.md), [A2 feature pairs](./2026-10-30-feature-pair-audit.md), [T1 dead tests](./2026-10-30-dead-tests-audit.md).

No application code was changed in this round.

---

## Category summary

| Category | Count (reported) | Notes |
| :--- | ---: | :--- |
| **1. Unused l10n keys** (no `lib/` use) | **423** | 2,930 EN/RU keys; parity OK |
| **1b. l10n test-only** (`lib/` 0, `test/` > 0) | **32** | Contract tests / fixtures |
| **2. Unused assets** | **8** | 7× `web/icons/web_*dp.png` + `.well-known/assetlinks.json` unreferenced in tree |
| **2b. Declared-but-never-loaded assets** | **0** | All `pubspec.yaml` asset globs referenced |
| **3. Unused GraphQL ops/fragments** (no non-`_g` `lib/` use) | **2** | `UserSubscribe`, `PollingModel` |
| **4. Unused public symbols** (high-confidence sample) | **12** | Full automated scan is noisy; table lists verified public/top-level items |
| **5. Unused `dependencies:` imports** | **5** | Client: 4 high + 1 medium; server: 1 medium |
| **Excluded (dormant / DI / codegen)** | — | `DORMANT(item-threads)`, `@injectable` mocks, `@RoutePage`, `@freezed`, serializers wired in `build.yaml` |

---

## 1. Unused l10n keys

**Rule:** Key present in `packages/client/l10n/app_en.arb` (and RU twin); generated getter/method never referenced under `packages/client/lib/` (excluding `lib/ui/l10n/`). Test-only references listed separately (§1b).

**Parity:** Top-level keys — EN **2,930**, RU **2,930**, **0** keys in only one locale file (verified with `\n  "key":` line-anchored parse).

**Volume:** **423** keys with **0** matches in `lib/` (excluding l10n generated). Largest prefix clusters: `beacon*` (166), `coordination*` (37), `my*` (32), `inbox*` (32), `forward*` (23). Many align with retired beacon HUD / master–detail / coordination UI strings still in ARB.

### Representative findings (full list available via audit command below)

| # | Where | Symbol | Evidence | Confidence | Suggested action |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | `packages/client/l10n/app_en.arb:2880` | `actionHide` | `rg -c 'actionHide' packages/client/lib --glob '!**/l10n/**'` → **0** hits | high | delete key (+ RU) if product confirms hide action removed |
| 2 | `packages/client/l10n/app_en.arb:988` | `beaconViewButton` | same pattern → **0** lib hits | high | delete |
| 3 | `packages/client/l10n/app_en.arb:191` | `buttonCrop` | **0** lib hits | high | delete or wire crop UI |
| 4 | `packages/client/l10n/app_en.arb:4960` | `beaconHudSituationPanelTitle` | **0** lib hits | high | delete HUD cluster or restore panel |
| 5 | `packages/client/l10n/app_en.arb:5139` | `beaconClosurePanelTitleReady` | **0** lib hits | high | delete closure panel copy or restore UI |
| 6 | `packages/client/l10n/app_en.arb:10650` | `beaconLobbyEmpty` | **0** lib hits (Questions tab uses other keys) | high | delete stale lobby strings |
| 7 | `packages/client/l10n/app_en.arb:6553` | `beaconRoomActionMarkAsk` | **0** lib hits | medium | confirm coordination ask action removed before delete |
| 8 | `packages/client/l10n/app_en.arb:8242` | `constellationComposerList` | **0** lib hits | high | delete |
| 9 | `packages/client/l10n/app_en.arb:1718` | `constellationViewModeText` | **0** lib hits | high | delete |
| 10 | `packages/client/l10n/app_en.arb:2880` | `activityTriageRequestsNeedResponse` | **0** lib hits | medium | delete or wire Activity triage |
| 11 | `packages/client/l10n/app_en.arb:7386` | `attentionCardClearAll` | **0** lib hits | high | delete |
| 12 | `packages/client/l10n/app_en.arb:6838` | `beaconPublishBlockedDescription` | **0** lib hits | medium | delete publish gate copy or restore gate UI |
| 13 | `packages/client/l10n/app_en.arb:552` | `buttonMakeLive` | **0** lib hits | high | delete |
| 14 | `packages/client/l10n/app_en.arb:6420` | `closeAckPrompt` | **0** lib hits | medium | delete |
| 15 | `packages/client/l10n/app_en.arb:2490` | `changeVoteButton` | **0** lib hits | high | delete |

**Reproduce full unused set:**

```bash
python3 - <<'PY'
import re, subprocess
from pathlib import Path
C = Path("packages/client")
en = (C/"l10n/app_en.arb").read_text()
keys = [m.group(1) for m in re.finditer(r'\n  "([^"@][^"]*)"\s*:', en)]
for key in keys:
    r = subprocess.run(["rg","-q",re.escape(key),str(C/"lib"),"--glob","!**/l10n/**"], cwd=".")
    if r.returncode != 0:
        print(key)
PY
```

---

## 1b. l10n referenced from tests only (not counted as unused for deletion without test updates)

| # | Where | Symbol | Evidence | Confidence | Suggested action |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | `app_en.arb` (see `threadGeneralTitle`) | `threadGeneralTitle` | `rg -c 'threadGeneralTitle' packages/client/lib` → 0; `packages/client/test` → ≥1 | high | keep for terminology contract tests; do not delete without updating `request_terminology_contract_test.dart` |
| 2 | `app_en.arb` | `inboxForwardedByLabel` | lib **0**, test **1** | high | keep until inbox tests rewritten |
| 3 | `app_en.arb` | `myWorkStatusNeedsMoreHelp` | lib **0**, test **2** | high | keep or migrate tests to active copy keys |
| 4 | `app_en.arb` | `constellationAbsenceFilterHidden` | lib **0**, test **2** | high | keep for constellation layout tests |

**Count:** **32** keys (same grep method, require `test/` hits > 0).

---

## 2. Unused assets

| # | Where | Symbol / path | Evidence | Confidence | Suggested action |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | `packages/client/web/icons/web_24dp.png` | file | `rg -l 'web_24dp' packages/client` → **0** files | high | delete or wire manifest / HTML |
| 2 | `packages/client/web/icons/web_32dp.png` | file | `rg -l 'web_32dp' packages/client` → **0** | high | delete |
| 3 | `packages/client/web/icons/web_36dp.png` | file | `rg -l 'web_36dp' packages/client` → **0** | high | delete |
| 4 | `packages/client/web/icons/web_48dp.png` | file | `rg -l 'web_48dp' packages/client` → **0** | high | delete |
| 5 | `packages/client/web/icons/web_64dp.png` | file | `rg -l 'web_64dp' packages/client` → **0** | high | delete |
| 6 | `packages/client/web/icons/web_96dp.png` | file | `rg -l 'web_96dp' packages/client` → **0** | high | delete |
| 7 | `packages/client/web/icons/web_512dp.png` | file | `rg -l 'web_512dp' packages/client` → **0** | high | delete |
| 8 | `packages/client/web/.well-known/assetlinks.json` | file | `rg -l 'assetlinks.json' packages/client` → **0** (Android App Links not referenced from repo) | medium | keep if deployed manually; else delete or document |

**Declared assets:** `pubspec.yaml` lists `images/placeholder/`, SVGs, fonts — all referenced from `lib/` (e.g. `images/placeholder/avatar.jpg` in `tentura_avatar.dart`) or font families. **0** orphaned declarations.

---

## 3. Unused GraphQL operations and fragments

Generated types exist under `packages/client/lib/data/gql/_g/` (e.g. `GUserSubscribeReq` in `serializers.gql.dart`); criterion is **no use in non-generated `lib/`**.

| # | Where | Symbol | Evidence | Confidence | Suggested action |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | `packages/client/lib/data/gql/user_subscribe.graphql:1` | `UserSubscribe` / `GUserSubscribeReq` | `rg 'GUserSubscribeReq' packages/client/lib` → **0**; `integration_test/support/e2e_test_helpers.dart:1291` → **1** | high | delete op + codegen **or** move call into a lib repository; drop dead generated serializers on delete |
| 2 | `packages/client/lib/data/gql/polling_model.graphql:1` | `PollingModel` | `rg 'PollingModel' packages/client/lib` → **1** hit (definition only); no other `.graphql` spreads this fragment | high | delete file; no `_g` consumers in `lib/` |

---

## 4. Unused public symbols

Skipped: `@injectable` test mocks (`client_repository_mocks.dart`, server `data/repository/mock/*`), `@RoutePage` screens, `@freezed` types, `main`, symbols only referenced from generated code (e.g. `TimestamptzSerializer` via `build.yaml` → **confirmed used**; see appendix).

| # | Where | Symbol | Evidence | Confidence | Suggested action |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | `packages/client/lib/design_system/tentura_responsive_scope.dart:132` | `myWorkMasterDetailSeparatorWidth` | `rg 'myWorkMasterDetailSeparatorWidth' packages/client/lib` → **1** (definition); `test/design_system/my_work_layout_packing_test.dart` → **1** | high | delete deprecated wrapper; update test to call `deskMasterDetailSeparatorWidth` |
| 2 | `packages/client/lib/design_system/tentura_responsive_scope.dart:121` | `deskMasterPaneWidth` | `rg 'deskMasterPaneWidth' packages/client` → **only** `tentura_responsive_scope.dart` + packing test | high | delete master–detail geometry helpers + test file **or** keep documented as layout spec |
| 3 | `packages/client/lib/design_system/tentura_responsive_scope.dart:143` | `deskFitsMasterDetail` | same → test-only external use | high | delete with #2 |
| 4 | `packages/client/lib/design_system/tentura_responsive_scope.dart:136` | `deskDetailBudget` | no callers outside same file | high | delete with #2 |
| 5 | `packages/client/lib/design_system/tentura_responsive_scope.dart:125` | `kDeskDetailMinWidth` | no external callers | high | delete with #2 |
| 6 | `packages/client/lib/domain/entity/beacon_activity_event_consts.dart:2` | `BeaconActivityEventVisibilityBits` | `rg 'BeaconActivityEventVisibilityBits' packages/client/lib` → **1**; tests → **10** hits | high | move to `test/support/` (T1 dead-target) |
| 7 | `packages/client/lib/data/gql/user_subscribe.graphql:1` | `UserSubscribe` | see §3 | high | delete or wire |
| 8 | `packages/client/lib/data/gql/polling_model.graphql:1` | `PollingModel` | see §3 | high | delete |
| 9 | `packages/client/lib/data/repository/mock/client_repository_mocks.dart:55` | `BeaconLobbyRepositoryMock` | production `@Injectable` test env — **excluded** from delete; 0 non-DI prod callers (T1) | — | keep (DI); optional move to test tree in cleanup pass |
| 10 | `packages/client/lib/data/repository/mock/client_repository_mocks.dart:77` | `ClosureRepositoryMock` | same | — | keep (DI) |
| 11 | `packages/server/lib/data/repository/mock/pair_block_query_repository_mock.dart:10` | `PairBlockQueryRepositoryMock` | test-only wiring (T1) | — | keep until mock relocation |
| 12 | `packages/server/lib/data/repository/mock/trust_ledger_repository_mock.dart:11` | `TrustLedgerRepositoryMock` | test-only (T1) | — | keep until mock relocation |

---

## 5. Unused dependencies

Criterion: no `package:<name>/` import in that package’s `lib/`, `bin/`, or `tool/` (client `hook/` noted separately).

| # | Where | Package | Evidence | Confidence | Suggested action |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | `packages/client/pubspec.yaml:88` | `scrollable_positioned_list` | `rg 'scrollable_positioned_list\|ScrollablePositionedList' packages/client/lib packages/client/bin packages/client/tool` → **0** | high | remove dependency |
| 2 | `packages/client/pubspec.yaml:76` | `gql_dedupe_link` | `rg 'package:gql_dedupe_link/' packages/client` → **0**; dedupe implemented by `CancellableDedupeLink` in `fetch_cancellation_link.dart` | high | remove dependency |
| 3 | `packages/client/pubspec.yaml:91` | `html` | `rg 'package:html/' packages/client/{lib,bin,tool,hook}` → **0** | high | remove dependency |
| 4 | `packages/client/pubspec.yaml:27` | `latlong2` | `rg 'package:latlong2/' packages/client/{lib,bin,tool}` → **0**; `Coordinates` uses `latlong2` in root `lib/domain/entity/coordinates.dart` via `tentura_root` | medium | remove direct client dep if workspace resolution still satisfies root |
| 5 | `packages/server/pubspec.yaml:21` | `latlong2` | `rg 'package:latlong2/' packages/server/{lib,bin,tool}` → **0** | medium | remove if server uses `Coordinates` from `tentura_root` only |
| 6 | `packages/client/pubspec.yaml:92-93` | `hooks`, `pubspec_parse` | used under `packages/client/hook/` (outside `lib/bin/tool`) | medium | keep, or move to `dev_dependencies` / document as build-hook deps |
| 7 | `packages/client/pubspec.yaml:28` | `drift_dev` | `rg 'package:drift_dev/' packages/client/lib` → **0**; used in `test/` + `build.yaml` | medium | move to `dev_dependencies` |
| 8 | `packages/client/pubspec.yaml:32` | `json_annotation` | no direct imports in `lib/` (codegen uses it) | low | keep unless analyzer confirms redundant |

---

## Top 15 to delete first

Low risk, high confidence, minimal blast radius:

1. **`packages/client/lib/data/gql/polling_model.graphql`** — orphan fragment, no spreads, no `lib/` use.
2. **`scrollable_positioned_list`** from `packages/client/pubspec.yaml`.
3. **`gql_dedupe_link`** from `packages/client/pubspec.yaml`.
4. **`html`** from `packages/client/pubspec.yaml`.
5. **Seven `web/icons/web_*dp.png`** files — no references; PWA uses `favicon.png` / launcher icons per `flutter_launcher_icons.yaml`.
6. **`myWorkMasterDetailSeparatorWidth`** — deprecated, test-only external caller.
7. **Master–detail geometry block** in `tentura_responsive_scope.dart` (`deskMasterPaneWidth`, `deskDetailBudget`, `deskFitsMasterDetail`, `kDeskDetailMinWidth`) + narrow packing test — production Inbox/My Work no longer uses master–detail (see A1 #2).
8. **`BeaconActivityEventVisibilityBits`** — move to test support (T1 #4.1).
9. **`UserSubscribe` GraphQL** — unused in `lib/`; either delete or promote to a repository used by prod + e2e.
10. **Sample unused l10n cluster `beaconHud*`** (~40 keys, 0 lib hits) — batch delete after UI sign-off.
11. **Sample unused l10n `beaconClosurePanel*`** — same.
12. **Unused l10n `buttonMakeLive` / `buttonPublish` / `beaconCreateSuccess`** — stale create/publish flow copy.
13. **`latlong2`** direct deps on client/server pubspecs (after `pub get` verify).
14. **`actionHide`** and other zero-hit action labels (quick ARB prune).
15. **Review `web/.well-known/assetlinks.json`** — unreferenced in repo; delete or add deploy docs.

---

## Appendix: cross-check with A1 / A2 / T1

| Prior claim | A3 result |
| :--- | :--- |
| A1 `myWorkMasterDetailSeparatorWidth` deprecated, no prod callers | **Confirmed** — only packing test references it outside the deprecated definition. |
| A1 master–detail helpers in `tentura_responsive_scope.dart` | **Confirmed** — geometry APIs are test-only externally. |
| T1 `BeaconActivityEventVisibilityBits` dead in prod | **Confirmed** — `lib/` declaration only; tests reference. |
| T1 mocks in `lib/data/repository/mock/` | **Confirmed** zero prod callers; **keep** for `@Injectable(env: test)` (not a delete-first item). |
| T1 implied `UpdatesScreen` / `TimestamptzSerializer` “dead” (codegen caveat) | **Refuted** — `UpdatesRoute` in `root_router.dart:173`; `TimestamptzSerializer` registered in `packages/client/build.yaml:161`. |
| A2 feature-pair duplication | **No new unused symbols** beyond strings already counted in §1. |

---

## Verification notes

- `flutter analyze` on `packages/client` after codegen: **3572** issues (pre-existing baseline; no source edits this round).
- Dormant item-thread plumbing (`DORMANT(item-threads)`) was not flagged as unused per ADR 0013.
