# Capability Non-ML Overhaul Journal

## How to use

- Read this file in full **before** starting any phase.
- Append a dated section after each meaningful step.
- Record decisions, rejected alternatives, unexpected findings, and follow-up TODOs.

## Decisions locked in (Phase 0)

- Plan depth: full 4 phases (0–4), sub-phases re-grilled before start.
- Messenger scope: row tap only; chat code preserved with `// DISABLED: capability-rework` markers.
- Taxonomy: client-hardcoded enum + slug text on server.
- Self-declared chips: REMOVED from scope. `CapabilityEventSource` has no `selfDeclared` value.
- Profile editor (`ProfileEditScreen`) is NOT modified by this workstream.
- `ChatPeerListTile` is retained for the chat list; `NetworkPersonCard` replaces it on the Network/Friends surface only.
- `showChatWith` is retained on `ScreenCubit` for deep-link (`tentura://chat/<id>`) routing; it is no longer reachable from the Network tab.
- All capability ops route through V2 GraphQL and must be registered in `_tenturaDirectOperationNames`.
- Unified `person_capability_event` table with 4 sources: private_label, forward_reason, commit_role, close_acknowledgement.
- Hasura is bypassed for capability reads; visibility enforced in `CapabilityCase`.

## Phase 0 — Disable messenger entry — 2026-04-30

**What changed:**
- Created `docs/capability-non-ml-overhaul-journal.md` (this file).
- Created `docs/adr/0001-capability-event-storage.md`.
- Created `packages/client/lib/features/capability/ui/widget/network_person_card.dart` widget shell (avatar + title + profile-only tap; capability cue strip slot left empty for Phase 1+).
- Replaced `ChatPeerListTile` usage in `friends_screen.dart` with `NetworkPersonCard` in `_FriendsTabBody`.
- Added `// DISABLED: capability-rework` marker block to `chat_peer_list_tile.dart`.
- Added comment above `showChatWith` in `screen_cubit.dart`.
- Bumped `packages/client` minor version (1.24.0 → 1.25.0).

**Why:**
- Per grilling decision `row_only`: Network tab row tap → profile only; chat code preserved for deep links.

**Unexpected findings:**
- `ChatPeerListTile` already split avatar and row ink wells — no gesture-arena conflict, clean replacement.
- `SelfAwareAvatar.small` factory suffices for `NetworkPersonCard`; no new avatar variant needed.

**Follow-ups (Phase 1):**
- Create `person_capability_event` table migration (`m0048`).
- Create `CapabilityCase`, `CapabilityRepositoryPort`, server repository.
- Create client `capability_tag.dart`, `capability_group.dart`, `capability_event_source.dart`, `person_capability_cues.dart`.
- Register V2 op names: `CapabilityPrivateLabelSet`, `MyPrivateLabelsForUser`, `PersonCapabilityCues`.
- Add l10n keys `capabilityTag_*`, `capabilityGroup_*`, `capabilityEditPrivateLabels`, `capabilityCueMyLabels`.
- Extend `NetworkPersonCard` with private-label cue strip.

**Status:** Phase 0 complete.

---

## Phase 1 — Private labels + server table bootstrap — 2026-04-30

**What changed:**

Server:
- Migration `m0048_person_capability_event`: creates table, indexes, `pce_private_label_uq` unique index (soft-delete aware), `pce_notify` trigger, and **replaces** `notify_entity_change()` to handle the new `person_capability_event` entity branch (entity_id = subject_user_id; fan-out to subject + observer).
- Drift table `PersonCapabilityEvents` added to `TenturaDb`.
- Domain enums: `CapabilityEventSource` (4 values, no self-declared), `CapabilityEventVisibility`, server `capability_tag.dart` (`kAllowedCapabilitySlugs` constant set).
- Port `PersonCapabilityEventRepositoryPort` with 5 operations.
- Repository `PersonCapabilityEventRepository` using Drift `customSelect`/`customStatement` for complex aggregation queries.
- Use case `CapabilityCase` with slug validation + self-label guard.
- Exception codes 1600 (`CapabilityExceptionCode`).
- GraphQL: `MutationCapability` (`capabilityPrivateLabelSet`), `QueryCapability` (`myPrivateLabelsForUser`, `personCapabilityCues`), GQL types (`v2_TagCount`, `v2_TagBeaconRef`, `v2_PersonCapabilityCuesPayload`).
- Wired into `_mutations_all.dart`, `_queries_all.dart`, `custom_types.dart`.
- Bumped server minor to 0.21.0.

Client:
- Domain: `CapabilityTag` enum (33 entries with slugs + group + isCommitRoleEligible flag), `CapabilityGroup` enum (7 groups), `CapabilityEventSource` enum (no self-declared), `PersonCapabilityCues` Freezed entity (+ `TagCount`, `TagBeaconRef`).
- Port `CapabilityRepositoryPort` with `changes` stream + `dispose`.
- 3 GraphQL operations: `capability_private_label_set.graphql`, `my_private_labels_for_user.graphql`, `person_capability_cues_fetch.graphql`.
- Schema updated with V2 types and query/mutation declarations.
- Ferry codegen ran successfully — all `_g/` files generated.
- `CapabilityRepository` (LazySingleton) with invalidation subscription.
- `InvalidationService` extended with `capabilityInvalidations` stream and `person_capability_event` switch case.
- 3 new op names registered in `_tenturaDirectOperationNames`.
- `CapabilityChipSet` widget (grouped FilterChip, all 7 groups, 33 tags).
- `CapabilityCueStrip` widget (compact "My labels: ...").
- `EditPrivateLabelsDialog` (DraggableScrollableSheet bottom sheet, imperatively opened).
- `ProfileViewState` extended with `PersonCapabilityCues cues`.
- `ProfileViewCubit` now injects `CapabilityRepositoryPort`, fetches cues alongside profile, subscribes to `changes` stream for live refresh.
- `ProfileViewBody` shows private-label cue strip + "Edit my labels" button (when viewer ≠ subject AND viewer is friend).
- `NetworkPersonCard` extended with optional `privateLabels` parameter + `CapabilityCueStrip` below name.
- l10n: 44 new keys in app_en.arb + app_ru.arb (group labels, tag labels, `capabilityEditPrivateLabels`, `capabilityCueMyLabels`).
- `flutter gen-l10n`, `dart run build_runner build -d`, `flutter analyze --fatal-infos`, `dart run custom_lint`, `dart analyze --fatal-infos` all green.
- Bumped client minor to 1.26.0.

**Why:**
- Per plan: Phase 1 bootstraps the `person_capability_event` table and the private-label flow (observer-only, never self-declared).

**Unexpected findings:**
- `notify_entity_change` must be fully replaced in each migration that extends it (no partial ELSIF injection possible) — confirmed by reading m0041.
- Drift `customSelect`/`customStatement` uses `?` placeholders (converted to `$N` for Postgres internally) — not raw Postgres `$1` syntax.
- DI container (`@LazySingleton(as: CapabilityRepositoryPort)`) calls `dispose()` on the declared type, so `dispose()` must exist on the port interface.
- `flutter gen-l10n` silently succeeds (no confirmation output) when using `l10n.yaml`.

**Confirmed untouched:**
- `ProfileEditScreen` diff is empty — intentionally not modified.
- `CapabilityEventSource` has exactly 4 values; no self-declared.

**Follow-ups (Phase 2):**
- Extend `beaconForward` with `reasons`/`recipientReasons` (server + client).
- `ForwardCase.forward` calls `CapabilityCase.recordForwardReasons` per recipient×slug.
- Add "Why?" chip selector per recipient in `ForwardBeaconScreen`.
- Extend `NetworkPersonCard` with "Often forwarded for" line from `forwardReasonsByMe`.
- New l10n keys: `forwardReasonPrompt`, `forwardReasonApplyToAll`, `capabilityCueForwardedFor`.

**Status:** Phase 1 complete.

---

## Phase 2 — Forward reasons — 2026-05-01

**What changed:**

Server:
- `mutation_forward.dart`: `beaconForward` extended with optional `reasons: [String!]` (shared uniform slugs) and `recipientReasons: [ForwardRecipientReasonInput!]` (per-recipient override). `InputFieldForwardRecipientReasons` InputType defined in `input_field_forward_recipient_reason.dart`.
- `ForwardCase.forward`: after each forward-edge batch, loops over recipients and calls `CapabilityCase.recordForwardReasons` per recipient×slug. Per-recipient map overrides shared slugs; errors are logged but do not abort the forward (non-fatal).
- `CapabilityCase.recordForwardReasons`: validates slugs, delegates to `PersonCapabilityEventRepository.insertForwardReasons`.
- `PersonCapabilityEventRepository.insertForwardReasons`: inserts one `forward_reason` event per slug (source_type=1).
- `PersonCapabilityCuesPayload.forwardReasonsByMe`: aggregation returns `[{slug, count, lastSeenAt}]` grouped by slug for forward reasons the viewer authored about the subject.
- Server bumped to 0.22.0.

Client:
- `forward_beacon.graphql`: added `$reasons: [String!]` and `$recipientReasons: [ForwardRecipientReasonInput!]` args.
- `ForwardState`: new field `recipientReasons: Map<String, List<String>>` (Freezed, persists across list scroll).
- `ForwardCubit.setRecipientReasons`: updates per-recipient slug map in state.
- `ForwardBeaconScreen`: per-recipient `[Why?]` icon button opens `CapabilityChipSet` modal (DraggableScrollableSheet). Icon colored `tt.info` when reasons are set.
- `ForwardRecipientRow`: accepts `reasonSlugs` + `onEditReasons`; renders label icon.
- `NetworkPersonCard`: `forwardedForSlugs` parameter renders "Often forwarded for: ..." line via `capabilityCueForwardedFor` l10n key.
- `ForwardRepository`: converts `List<String>` → `BuiltList<String>` when building `GForwardRecipientReasonInput`.
- l10n: 3 new keys (`forwardReasonPrompt`, `forwardReasonApplyToAll`, `capabilityCueForwardedFor`) in app_en.arb + app_ru.arb.
- `dart run build_runner build -d`, `flutter analyze --fatal-infos`, `dart run custom_lint` all green.
- Client bumped to 1.27.0.

Tests:
- `capability_case_test.dart`: covers `upsertPrivateLabel` (self-label rejection, invalid slug, empty set, valid slugs) + `recordForwardReasons` (empty no-op, invalid slug, valid delegation, note passthrough).
- `forward_case_test.dart`: covers reason-routing in `ForwardCase.forward` — no reasons, shared fan-out, per-recipient override, empty per-recipient skips event.
- `forward_beacon_page_test.dart`: chip selection persists after list scroll (state preserved in cubit across widget rebuilds).

**Why:**
- Per plan: Phase 2 adds the forward-reason capability signal (source_type=1); private to the forwarder; surfaced as "Often forwarded for" in NetworkPersonCard.

**Unexpected findings:**
- `GraphQLInputObjectType<Map<String, dynamic>>` triggers `wrong_number_of_type_arguments` — this version of the library takes 0 type params; raw `GraphQLInputObjectType(...)` is the correct form.
- `ForwardState.recipientReasons` field was added to the Freezed class but the `.freezed.dart` file was stale — required `build_runner` to regenerate before tests could compile.
- `GForwardRecipientReasonInput.create(slugs:)` expects `BuiltList<String>?` not `List<String>` — needed a `BuiltList.from()` conversion in `ForwardRepository`.

**Confirmed untouched:**
- `ProfileEditScreen` diff is empty.
- `CapabilityEventSource` still has exactly 4 values; no self-declared.

**Follow-ups (Phase 3):**
- Extend `kAllowedHelpTypeKeys` and `CommitHelpType` with new slugs; deprecate `skill`.
- Migration `m00YY_help_type_taxonomy_align`: rewrite `beacon_commitment.help_type = 'skill'` → `'other'`.
- `CommitmentCase.commit` writes a `commit_role` capability event after the existing `beacon_commitment` upsert.
- Commit dialog adds ChoiceChip row of commit-role-eligible slugs.
- `NetworkPersonCard` + `ProfileViewBody` render `commitRoles` cues.
- l10n: `commitRolePrompt`, `capabilityCueCommitted`.

**Status:** Phase 2 complete.

---

## Phase 3 — Commit role chips — 2026-05-01

**What changed:**

Server:
- `packages/server/lib/domain/coordination/help_type.dart`: `kAllowedHelpTypeKeys` extended with `'documents'`, `'physical_help'`, `'tools'`, `'housing'`, `'workspace'`, `'introductions'`. Legacy `'skill'` retained in the set for backward compatibility with old clients still in flight.
- `packages/server/lib/data/database/migration/m0049.dart` (new): single `UPDATE beacon_commitment SET help_type = 'other' WHERE help_type = 'skill'` — retires `skill` at the data layer.
- `_migrations.dart`: `part 'm0049.dart';` added; `m0049` registered in the migrations list.
- `packages/server/lib/domain/use_case/commitment_case.dart`: injected `CapabilityCase _capabilityCase` (5th positional constructor param, mirroring `ForwardCase` pattern); after each of the two `_commitmentRepository.upsert(...)` calls (hasActive branch + new-commit branch), calls `_capabilityCase.recordCommitRole(observerId: userId, subjectId: userId, beaconId: beaconId, slug: helpType)` guarded by null/empty check and wrapped in try/catch (non-fatal, logs warnings). Call placed before `_coordinationRepository.recompute...`.
- `di.config.dart`: injectable DI config updated — `gh<CapabilityCase>()` wired as the 5th argument to `CommitmentCase`.
- `test/domain/use_case/commitment_case_mocks.dart`: `PersonCapabilityEventRepositoryPort` added to `@GenerateMocks`; `capability_case.dart` + `capabilityCase` field added to test setUp.
- Server bumped to 0.23.0.
- `dart analyze --fatal-infos`: no issues.

Client:
- `packages/client/lib/domain/entity/help_type.dart`: removed `skill` entry; added `documents`, `physicalHelp`, `tools`, `housing`, `workspace`, `introductions`; updated `wireKey` + `tryParse`; mapped `'skill'` → `CommitHelpType.other` in `tryParse` for backward compat.
- `packages/client/lib/features/beacon_view/ui/dialog/commitment_message_dialog.dart`: section label changed from `labelHelpTypeOptional` → `commitRolePrompt`; `_helpTypeLabel` updated — removed `skill` case, added 6 new entries using `capabilityTag*` l10n keys.
- `packages/client/l10n/app_en.arb` + `app_ru.arb`: added `commitRolePrompt` and `capabilityCueCommitted` (with `{tags}` placeholder).
- `packages/client/lib/features/capability/ui/widget/network_person_card.dart`: added `commitRoleSlugs` parameter; renders "Committed: ..." line when non-empty.
- `packages/client/lib/features/profile_view/ui/widget/profile_view_body.dart`: added `commitRoles` `BlocSelector` strip after private-label section; beacon-scoped, visible to all viewers.
- Client bumped to 1.28.0.
- `dart run build_runner build -d`, `flutter analyze --fatal-infos`, `dart analyze --fatal-infos`, `dart run custom_lint` all green.

**Why:**
- Per plan: Phase 3 adds commit-role capability signal (source_type=2, beacon_scoped); stored in both `beacon_commitment.help_type` (legacy) and `person_capability_event` (new).

**Unexpected findings:**
- `di.config.dart` needed manual update (injectable does not auto-detect new positional args without running `build_runner`).
- `commitment_case_mocks.mocks.dart` required manual edit since `build_runner` was not run mid-session.

**Confirmed untouched:**
- `ProfileEditScreen` diff is empty — intentionally not modified.
- `CapabilityEventSource` still has exactly 4 values; no self-declared.

**Follow-ups (Phase 4):**
- Extend `evaluationSubmit` mutation with optional `acknowledgedHelpTags: [String!]`.
- `EvaluationCase.evaluationSubmit` calls `CapabilityCase.recordCloseAcknowledgement` after evaluation write.
- Add `CapabilityChipSet` per participant in `ReviewContributionsScreen`.
- Extend `PersonCapabilityCuesPayload` with `closeAckByMe` + `closeAckAboutMe`.
- Update `NetworkPersonCard` + `ProfileViewBody` for signal-strength ordering: closeAck > commitRole > forwardReason > privateLabel.
- l10n: `closeAckPrompt`, `capabilityCueAcknowledged`.

**Status:** Phase 3 complete.

---

## Phase 4 — Close acknowledgements — 2026-05-01

**What changed:**

Server (already wired from prior session):
- `mutation_evaluation.dart`: `evaluationSubmit` extended with optional `acknowledgedHelpTags: [String!]` field. Resolver extracts the list and passes it to `EvaluationCase.evaluationSubmit`.
- `evaluation_case.dart`: `evaluationSubmit` accepts `List<String>? acknowledgedHelpTags`; calls `CapabilityCase.recordCloseAcknowledgement` after the existing `upsertEvaluation` write (non-fatal, wrapped in try/catch).
- `capability_case.dart`: `recordCloseAcknowledgement` validates slugs and delegates to `PersonCapabilityEventRepository.insertCloseAcknowledgements`.
- `query_capability.dart`: `personCapabilityCues` resolver maps `closeAckByMe` and `closeAckAboutMe` from the repository row.
- `PersonCapabilityCuesPayload` in `custom_types.dart` and `schema.graphql`: `closeAckByMe`/`closeAckAboutMe` fields declared.
- Server bumped to 0.25.0.

Client:
- `evaluation_submit.graphql`: added `$acknowledgedHelpTags: [String!]` variable and mutation argument.
- `EvaluationRepository.submit`: added optional `acknowledgedHelpTags` parameter; sets `ListBuilder` on `GEvaluationSubmitReq.vars.acknowledgedHelpTags` (null when empty, preserving backward compatibility).
- `EvaluationCase` (client): `submit` threaded `acknowledgedHelpTags` through to repository.
- `EvaluationCubit.submitOne`: threaded `acknowledgedHelpTags` through to use case.
- `evaluation_detail_sheet.dart`: added `CapabilityChipSet` section under the rating chips (prompt: `closeAckPrompt`). The `onSave` callback signature extended to include `List<String> acknowledgedHelpTags` as 4th argument. Internal ack-tag state is a `Set<String>`.
- `review_contributions_screen.dart`: `onSave` callback updated to pass `ackTags.isEmpty ? null : ackTags` to `submitOne`.
- `NetworkPersonCard`: added `closeAckSlugs` parameter. Cue strip now shows the strongest non-empty signal only — order: `closeAck > commitRole > forwardReason > privateLabel`.
- `ProfileViewBody`: replaced the separate commit-roles selector with a combined `(closeAckAboutMe, commitRoles)` selector that shows `closeAckAboutMe` when non-empty, otherwise `commitRoles` (signal-strength ordering).
- `person_capability_cues_fetch.graphql`: `closeAckByMe` / `closeAckAboutMe` fields already present.
- `capability_repository.dart`: `closeAckByMe` / `closeAckAboutMe` mapping already present.
- `PersonCapabilityCues` entity: `closeAckByMe` / `closeAckAboutMe` fields already present.
- l10n: 2 new keys in app_en.arb + app_ru.arb: `closeAckPrompt`, `capabilityCueAcknowledged`.
- `flutter gen-l10n`, `dart run build_runner build -d`, `flutter analyze --fatal-infos`, `dart run custom_lint`, `dart analyze --fatal-infos` all green.
- Client bumped to 1.29.0; web/manifest.json updated to 1.29.0.

**Why:**
- Per plan: Phase 4 adds the close-acknowledgement capability signal (source_type=3); strongest signal in the cue hierarchy; stored after evaluation submission.

**Unexpected findings:**
- Much of the server implementation (mutation, evaluation case, capability case, query resolver, schema types, GQL query fields, entity fields, repository mapping) was already complete from a prior session. Phase 4 client changes were isolated to the evaluation flow (GQL mutation arg, repo/case/cubit threading, detail sheet chip set) and the cue display ordering.
- `CapabilityChipSet` uses `selectedSlugs: Set<String>` not `List<String>` — the internal `ackTags` in the detail sheet must be a `Set`.

**Confirmed untouched:**
- `ProfileEditScreen` diff is empty — intentionally not modified.
- `CapabilityEventSource` still has exactly 4 values; no self-declared.
- No l10n keys starting with `capabilitySection*` or `capabilityCueSelfListed`.
- `PersonCapabilityCuesPayload` has no `selfDeclared` field.
- `MIN_CLIENT_VERSION` not bumped (all additions are nullable/additive).

**Decisions confirmed (cross-cutting check):**
- Self-declared chips: still absent from codebase and schema. ✅
- All V2 op names registered in `_tenturaDirectOperationNames`: `CapabilityPrivateLabelSet`, `MyPrivateLabelsForUser`, `PersonCapabilityCues` already registered from Phase 1. `EvaluationSubmit` is an existing Hasura op — not a V2 op; no registration needed. ✅
- Signal ordering: closeAck > commitRole > forwardReason > privateLabel — enforced in both `NetworkPersonCard` and `ProfileViewBody`. ✅

**Status:** Phase 4 complete. All four phases of the non-ML capability overhaul are done.

---

## Phase 5 — Taxonomy unification — 2026-05-03

**What changed:**

Client:
- `packages/client/lib/domain/entity/help_type.dart`: **deleted**. `CommitHelpType` enum was a redundant subset of `CapabilityTag`; its 12 values mapped 1:1 to the `isCommitRoleEligible: true` subset.
- `packages/client/lib/domain/capability/capability_tag.dart`: removed `isCommitRoleEligible` field and all `isCommitRoleEligible: true` annotations. All 33 tags are now valid commit roles.
- `packages/client/lib/features/beacon_view/ui/dialog/commitment_message_dialog.dart`: replaced `CommitHelpType` with `CapabilityTag`. Chip loop now iterates all 33 `CapabilityTag.values`; labels via `tag.labelOf(l10n)`; wire key via `tag.slug`. Removed `_helpTypeLabel` static switch.
- `packages/client/lib/features/beacon/ui/widget/coordination_ui.dart`: replaced stale 7-case `helpTypeLabel()` switch with `CapabilityTag.fromSlug(wireKey)?.labelOf(l10n) ?? wireKey`. This also fixes the Phase 3 bug where `documents`, `physical_help`, `tools`, `housing`, `workspace`, `introductions` fell through to raw wire-key display.
- `packages/client/l10n/app_en.arb` + `app_ru.arb`: removed 7 `helpType*` keys (`helpTypeMoney`, `helpTypeTime`, `helpTypeSkill`, `helpTypeVerification`, `helpTypeContact`, `helpTypeTransport`, `helpTypeOther`). All labels now use `capabilityTag*` keys. `'skill'` (migrated to `other` by m0049) falls through to raw key via `fromSlug` null fallback — acceptable since no live data has this slug.
- `packages/client/test/features/beacon_view/commitment_chip_roundtrip_test.dart`: updated to use `CapabilityTag.values.length`, `CapabilityTag.slug` round-trip test.

Server:
- `packages/server/lib/domain/coordination/help_type.dart`: replaced `kAllowedHelpTypeKeys` constant with a thin `isAllowedHelpType` wrapper delegating to `kAllowedCapabilitySlugs`. Server now accepts all 33 capability slugs as valid help types (previously only 13).

**Why:**
- `CommitHelpType` was a historical artifact (Phase 1 had 7 types; Phase 3 added 6 more). The two parallel enum/label systems caused: (a) a display bug for Phase 3 additions in `helpTypeLabel()`, (b) mixed l10n usage in `_helpTypeLabel()`, (c) artificial restriction forcing contributors (e.g. offering childcare, food, translation) into `other`.
- Social design rationale: commitment vocabulary should match capability vocabulary. The repair loop (NEED → RELAY → COMMIT → VERIFY → CLOSE) needs a shared lexicon across all steps.

**Verified:**
- `dart analyze --fatal-infos`: no issues (client). Pre-existing `unnecessary_parenthesis` info in server unrelated to these changes.
- `flutter analyze --fatal-infos`: no issues.
- `dart run custom_lint`: no issues.
- `dart test commitment_case_test.dart capability_case_test.dart`: all 21 tests passed.
- No remaining references to `CommitHelpType`, `kAllowedHelpTypeKeys`, `isCommitRoleEligible`, or `helpType*` l10n keys.

**Confirmed untouched:**
- `ProfileEditScreen` — intentionally not modified.
- `CapabilityEventSource` — still 4 values; no self-declared.
- `UncommitReason` — separate taxonomy, unrelated.

**Status:** Phase 5 complete.
