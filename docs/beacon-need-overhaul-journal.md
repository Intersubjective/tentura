# Beacon need-first overhaul — implementation journal

## Locked decisions

- **Header NeedBrief:** one line under author row when `beacon.hasNeedSummary`; `Need:` prefix is l10n; ellipsis on overflow.
- **Backfill:** migration adds nullable `need_summary` / `success_criteria`; existing rows stay NULL; UI uses single "Need & context" card until author edits.
- **No separate `needs` table.**

## Field bounds

- `need_summary`: hard max 280; publish (fresh, non-draft) min 16 trimmed chars; drafts may omit.
- `success_criteria`: optional; hard max 240.

## Log

<!-- Append dated sections below during implementation -->

## Summary

- **Scope:** `need_summary` / `success_criteria` end-to-end (Postgres → Drift → domain → GraphQL → client entity/model → create flow → beacon view header + overview). Legacy beacons (`need_summary` null) keep a single **Need & context** overview card until edited.
- **Server:** `m0035` migration; `BeaconEntity` + `BeaconCase` validation (trim, max lengths, min 16 on non-draft create / non-empty update paths); `BeaconNeedSummaryTooShortException`; `mutation_beacon` create/update/updateDraft args; repository + mapper + mock; Hasura `beacon` user `select_permissions` columns for the new fields.
- **Client:** Ferry fragment/mutations + `schema.graphql` sync; `Beacon` / `BeaconCreateState` / cubit + `info_tab` fields; `BeaconNeedBrief` in header; `BeaconOverviewTab` need-first vs legacy layout + `BeaconOverviewSectionCard.collapsible`; l10n + `BeaconNeedSummaryTooShortException` mapping.
- **Codegen:** `dart run build_runner build -d` on client and server after schema/Freezed changes.
- **Tests:** `test/features/beacon_view/beacon_overview_need_test.dart` (legacy + need-first + NeedBrief); golden `typography_overhaul_test.dart` “beacon view header” updated for NeedBrief (`--update-goldens` on that test name only).
- **Verification:** `flutter analyze --fatal-infos` + `dart run custom_lint` on `packages/client` and `packages/server` (clean after lint fixes in overview test, `info_tab` cascades, `hasNeedSummary`, overview `initState` / children).
- **Deviations:** None material; `publishDraft` still uses Hasura lifecycle-only update — need length enforced in cubit + on V2 `beaconCreate` / `beaconUpdate` / `beaconUpdateDraft`, not on that Hasura hop.
- **Follow-ups:** Audit duplication between **Coordination** overview card and any top-of-screen coordination status strip; optional second golden with `needSummary == null` to lock legacy header (fixture currently stresses need-first header).
- **Versioning:** No semver bump in this change set (per plan).
