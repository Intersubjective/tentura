# People tags, Field arrangement and semantic zoom — implementation plan

**Status:** rev 1 (2026-10-23), draft.
**Baseline:** `main` @ `777680fca` (latest migration `m0260`; the post-lifetime epic `tentura-lkkq`
adds `m0261+` — always take the next free number). Client `7.49.0`.
**For:** an implementer (human or model) who follows units literally, test-first, one unit at a time.

**Sources of truth (read before any unit):**
1. GitHub issue #699 — product spec ("Spec §N"), mockups A/B/C (branch `claude/project-thread-rsrtg6`,
   `docs/design/people-tags/`). Read with `gh issue view 699`.
2. [`people-tags-plan.md`](people-tags-plan.md) — spec↔code reconciliation (§1), plan defaults P1–P12
   (§2), architecture (§3). **Where the plan's §1 "Plan uses" column differs from the spec, the plan
   wins.**
3. [`post-implementation-steps.md`](post-implementation-steps.md) **§0 applies verbatim** (conventions,
   one migration per unit, transactions, exceptions, V2 pattern, Hasura two-test rule, client schema,
   design system, l10n, mocks, wrapped serial tests §0.2, definition of done §0.3).

If a step contradicts the spec or the plan, stop and report. Line numbers are from 2026-10-23; if a
quoted line drifted, search for the symbol; if it is gone, stop.

---

## 0. Deltas to the shared rules

- **Paths.** `S/` = `packages/server/lib/`, `M/` = `S/data/database/migration/`,
  `C/` = `packages/client/lib/`, `F/` = `C/features/constellation/`, `R/` = root `lib/`.
- **No permanent Alloy gate tests.** Behavioural tests only; no counts, SHAs, plan text, migration
  numbers.
- **Privacy rule for every unit.** Tag names, glyphs and membership appear only in the owner's own V2
  responses. Server log lines carry ids only. No unit adds tag data to notifications, push, email,
  attention, analytics or another user's response.
- **Owner-only tables** are never tracked by Hasura and are reached only through V2 resolvers with
  `owner_id = getCredentials(args).sub`. Pattern: `offer_accepted_dismissal` (m0252,
  `S/data/repository/offer_accepted_dismissal_repository.dart`,
  `S/api/controllers/graphql/{mutation,query}/…offer_accepted_dismissal.dart`).
- **Idempotency** by `clientOpId` mirrors `constellation_anchor_op_log`: `(owner_id, client_op_id)`
  + SHA-256 fingerprint of the normalised input; same fingerprint → stored result; different →
  `opIdReused`.
- **New transaction roots** go into `packages/server/test/architecture/transaction_entry_inventory.txt`.
- **Exceptions:** code space 1900 `PeopleTagsExceptionCode`; client mirror in
  `C/features/people_tags/domain/people_tags_exception.dart` (pattern
  `F/domain/exception.dart`).
- **UI:** `material-3-flutter` skill; design-system tokens only; every menu reachable by visible
  button + long press (touch) + secondary tap (mouse); every drag action has a menu alternative;
  reduced motion = instant.
- **Gestures on the Field:** never change the meaning of existing canvas long press / secondary tap
  (composer create).
- **Feature gate.** `C/consts.dart`: `kPeopleTagsEnabled = false` (unit B1) hides every new tag entry
  point; `kFieldArrangeV2Enabled = false` (unit D2) hides the Arrange menu; `kFieldSemanticZoomEnabled = false`
  (unit E1) keeps today's levels. The ship units R1/R2/R3 flip them. Server units are not gated
  (additive).
- **Wrapped tests, serially** (shared §0.2). Server pg tests in REQUIRED mode.

### Copy (RU / EN)

Spec §14 is binding for the keys it lists. Additional keys:

| Key | RU | EN |
|---|---|---|
| `peopleTagsOffField` | {n} вне поля | {n} off the field |
| `peopleTagsShowInFilters` | Показывать в фильтрах | Show in filters |
| `peopleTagsMakeMine` | Сделать своим тегом | Make it my tag |
| `peopleTagsDelete` | Удалить тег | Delete tag |
| `peopleTagsDeleted` | Тег «{name}» удалён | Tag “{name}” deleted |
| `peopleTagsUndo` | Отменить | Undo |
| `peopleTagsAddPeople` | Добавить людей… | Add people… |
| `peopleTagsDontSuggest` | Больше не предлагать | Don't suggest again |
| `peopleTagsSuggestEnable` | Предлагать теги | Suggest tags |
| `peopleTagsLensResult` | {tags}: {n} чел. | {tags}: {n} people |
| `peopleTagsOpenView` | Открыть вид тега | Open tag view |
| `peopleTagsForwardRequest` | Переслать запрос… | Forward a request… |
| `peopleTagsWorkingTogether` | Вместе в запросе «{title}» | Working together on “{title}” |
| `peopleTagsGroupByTags` | По тегам | Group by tags |
| `peopleTagsWithoutOwn` | Без своих тегов | Without own tags |
| `peopleTagsDroppedOnChip` | {name} → {tag} | {name} → {tag} |
| `peopleTagsNameTaken` | Такой тег уже есть | You already have this tag |
| `peopleTagsLimit` | Не больше 50 тегов | Up to 50 tags |
| `constellationArrange` | Расставить | Arrange |
| `constellationUndo` / `constellationRedo` | Отменить / Повторить | Undo / Redo |
| `constellationTidied` | Причёсано: сдвинуто {n} | Tidied up: {n} people moved |
| `constellationRearrangeAll` | Переставить всех, включая закреплённых | Rearrange everyone, including pinned |
| `constellationRearrangePreview` | Сдвинется {n} чел. · текущая расстановка сохранится в истории | {n} people will move · your current layout is saved to history |
| `constellationApply` / `constellationCancel` | Применить / Отмена | Apply / Cancel |
| `constellationRestoreThis` | Вернуть эту | Restore this |
| `constellationTagViewOthers` | Остальные: скрыть / точками / как есть | Others: hide / as dots / as is |
| `constellationTagViewAuto` | Расставлено автоматически. Здесь ничего не закрепляется; основное поле не меняется. | Laid out automatically. Nothing is pinned here; the main Field does not change. |
| `constellationFindInTag` | Найти в теге | Find in tag |
| `constellationOverviewCount` | {n} чел. · обзор | {n} people · overview |
| `constellationClusterPeople` | {n} чел. | {n} people |

Automatic tag names: spec §14 last line.

---

## 1. Unit map

Complexity: **S** simple, **M** medium, **C** complex. "Prio" is the scheduling priority used for the
beads (P1 first): critical path and risk first, then unblockers, then the rest.

| Unit | Title | Size | Depends on | Prio |
|---|---|---|---|---|
| **Phase 1 — server** |
| A1 | Schema: tags, members, prefs, first seen, suggestion state, op log | M | — | P1 |
| A2 | Own tag CRUD + restore (V2) | C | A1 | P1 |
| A3 | Membership apply + `personTagsOf` own part (V2) | M | A2 | P1 |
| A4 | Realtime kind `person_tag` | M | A1 | P2 |
| A5 | Automatic tags SQL + V2 (`personAutoTags`, prefs, `personTagsOf` auto part) | C | A1 | P1 |
| A6 | Tag creation from an automatic tag / from a Request | M | A3, A5 | P2 |
| A7a | Field membership: T predicate, B and T in the snapshot, `presence` | C | — | P1 |
| A7b | Field caps 400, priority order, tags + first seen in the snapshot | C | A3, A5, A7a | P1 |
| A8 | Suggestion state (V2) | M | A1 | P2 |
| A9 | Privacy behaviour suite | M | A4, A6, A7b, A8 | P2 |
| G1 | Manual: server snapshot perf at 400 on `tentura_perfsynth` | manual | A7b | P2 |
| **Phase 1 — client** |
| B2 | Tag colour tokens + chip components | M | — | P2 |
| B1 | `people_tags` data layer + store + realtime + gate | C | A3, A4, A5, A8 | P1 |
| B3 | "Add to tag…" sheet + tag editor + Undo snackbar helper | M | B1, B2 | P1 |
| B4 | Tags block in the person panel and the profile | M | B3 | P2 |
| B5a | Person menus: profile, Friends, trust graph | M | B3 | P2 |
| B5b | Person menus: Request People, Post participants, forward rows, chat author | M | B3 | P3 |
| B6a | People tags screen: lists, reorder, delete + Undo, auto switches | C | B3 | P2 |
| B6b | Tag detail and automatic-tag detail screens | M | B6a, A6 | P2 |
| B7 | Field: membership without D9, presence rendering, field tag data | C | A7b, B1 | P1 |
| B8a | Field tag row + filter + lens dim | C | B7, B2 | P1 |
| B8b | Lens hull + bottom panel + drag node onto chip | M | B8a, B3 | P2 |
| B9 | Own-tag glyphs on nodes + screen-reader label | M | B7, B2 | P2 |
| B10 | List view grouped by tags | M | B7 | P3 |
| B11 | Tag chips in forward and compose pickers | C | B1, B2 | P2 |
| B12 | "Tag them?" suggestions | C | B3, A6, A8 | P2 |
| R1 | Ship phase 1 | S | B4–B12, A9 | P2 |
| M1 | Manual: phase 1 local-stack check | manual | R1 | P2 |
| **Phase 2 — arrangement** |
| C2 | Anchor batch cap 64 → 400 (server + client) | M | — | P2 |
| C1 | Layout snapshots: table + V2 save/list/restore | C | C2 | P2 |
| D1 | Arrangement history (undo/redo) | C | C2 | P2 |
| D2 | Arrange menu; undoable reset; shortcuts; gate | M | D1, C1 | P2 |
| D3 | Tidy up + move trails | C | D1 | P2 |
| D5 | Rearrange everyone incl. pinned (preview) | M | D2 | P3 |
| D6 | Layout history sheet + favourite + auto history | C | D2 | P3 |
| D7a | Tag view layout algorithm | C | B8a | P2 |
| D7b | Tag view mode, others mode, animations, search, forward | C | D7a, B8b | P2 |
| R2 | Ship phase 2 | S | D3, D5, D6, D7b | P3 |
| **Phase 3 — scale and magnets** |
| E8 | Person search 200 + focus highlight | S | — | P2 |
| E1 | One zoom-level owner: close / district / overview | C | — | P2 |
| E2a | Overview: dots, no labels or chips, hit targets (#595, #640) | C | E1 | P2 |
| E2b | Overview: grid cluster labels + edge bundles | C | E2a | P3 |
| E3 | District level: initials, tag rings, label budget | M | E1, B9 | P3 |
| E6 | Minimap | M | E1 | P3 |
| E5a | Community detection + overview placement (pure) | C | — | P3 |
| E5b | Community layout integration + level transitions | C | E5a, E2a | P3 |
| E7a | Gather + selection actions at every level | M | D1, D3, B3 | P3 |
| E7b | Drag a cluster at Overview | M | E7a, E2b | P3 |
| E4 | Render cap 400 | M | E2b, E3, E5b | P3 |
| G2 | Manual: wasm bench at N = 400 (I4) | manual | E4 | P3 |
| E9a | Magnets: server | M | A2, C2 | P4 |
| E9b | Magnets: client | C | E9a, E4 | P4 |
| R3 | Ship phase 3 | S | E4, E6, E7b, E9b, G2 | P3 |

Critical path: A1 → A2 → A3 → A7b → B7 → B8a → D7a → D7b. Independent early leaves: A7a, B2, C2,
E1, E8, E5a.

---

## 2. Phase 1 — server

### A1 — Schema

**Goal:** plan §3.1 tables.

**Files:** new migration (next free number) in `M/`, registered in `_migrations.dart`; Drift table
classes are **not** added (raw SQL, like `post_first_response`); test
`packages/server/test/data/database/people_tags_schema_pg_test.dart`; extend the Hasura-untracked
architecture test (or add `test/architecture/hasura_metadata_people_tags_untracked_test.dart`).

**SQL (one statement per entry):**
- `person_tag(id text PK, owner_id text NOT NULL REFERENCES "user"(id) ON DELETE CASCADE, name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 32), glyph text NOT NULL CHECK (char_length(glyph) BETWEEN 1 AND 8), color smallint NOT NULL CHECK (color BETWEEN 0 AND 7), ord integer NOT NULL, created_at, updated_at timestamptz NOT NULL DEFAULT now())`;
  `CREATE UNIQUE INDEX person_tag_owner_name_uq ON person_tag (owner_id, lower(name))`;
  index `(owner_id, ord)`.
- `person_tag_member(tag_id text REFERENCES person_tag ON DELETE CASCADE, owner_id text NOT NULL REFERENCES "user" ON DELETE CASCADE, person_id text NOT NULL REFERENCES "user" ON DELETE CASCADE, source smallint NOT NULL CHECK (source BETWEEN 0 AND 4), added_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY (tag_id, person_id))`;
  index `(owner_id, person_id)`; CHECK `owner_id <> person_id`.
- `person_auto_tag_pref(owner_id … CASCADE, kind smallint, show_in_filters boolean NOT NULL, PRIMARY KEY (owner_id, kind))`.
- `person_field_first_seen(viewer_id … CASCADE, peer_id … CASCADE, first_seen_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY (viewer_id, peer_id))`.
- `person_tag_suggestion_state(owner_id PK … CASCADE, consecutive_skips smallint NOT NULL DEFAULT 0, silenced_until timestamptz, disabled boolean NOT NULL DEFAULT false, updated_at)`.
- `person_tag_op_log(owner_id … CASCADE, client_op_id text, fingerprint text NOT NULL, result jsonb NOT NULL, created_at, PRIMARY KEY (owner_id, client_op_id))`.
- `person_tag_revision(owner_id PK … CASCADE, revision bigint NOT NULL DEFAULT 0)` — bumped by A4.

**Tests (write first, pg, upgrade path from the previous version):** each CHECK rejects a bad row;
duplicate name differing only in case → unique violation; deleting the owner removes all owner rows;
deleting a tagged person removes their member rows; deleting a tag removes its members; Hasura
metadata tracks none of the new tables.

**Done when:** tests green.

### A2 — Own tag CRUD + restore

**Goal:** spec §4.1–4.2 (tag-level actions), §11.3 `personTags`, `personTagCreate/Update/Delete/Restore`.

**Files:** `S/domain/entity/person_tag.dart`; `S/domain/port/people_tags_repository_port.dart`;
`S/data/repository/people_tags_repository.dart`; `S/domain/use_case/people_tags_case.dart`;
`S/api/controllers/graphql/{query,mutation}/…people_tags.dart` registered in the aggregators;
GraphQL types `PersonTag {id name glyph color ord count countOffField}` (count fields filled in A3);
exception code space 1900 in `S/domain/exception_codes.dart` + classes in `S/domain/exception.dart`;
tests `test/domain/use_case/people_tags_case_pg_test.dart`,
`test/api/controllers/graphql/people_tags_graphql_pg_test.dart`.

**Rules:** name trimmed, 1–32 chars, unique per owner case-insensitive → `tagNameTaken`; 50 tags →
`tagLimitReached`; glyph = exactly one grapheme cluster that is a letter or an emoji (default: first
grapheme of the name, upper-cased); colour 0–7 (default: `count(own tags) % 8`); new tag `ord = max + 1`;
`ord` updates renumber densely; delete returns the deleted snapshot `{tag, memberIds, sources}`;
restore recreates with the **same id** (P9) and fails with `tagNameTaken` if the name was reused;
all four mutations idempotent by `clientOpId` (§0).

**Tests (write first):** create / rename / recolour / reorder / delete / restore round trip; limits and
validation errors; idempotent replay returns the stored result, a changed payload with the same
`clientOpId` → `opIdReused`; another user's `personTags` never includes the tag; updating someone
else's tag id → `tagNotFound`.

**Done when:** tests green.

### A3 — Membership apply + `personTagsOf` own part

**Goal:** spec §4.2 people actions, §11.3 `personTagMembersApply`, `personTagsOf(personId)` (own).

**Files:** same feature files as A2; new resolver fields; tests extend A2's.

**Rules:** ops `{tagId, personId, op: add|remove, source}` ≤ 400 per call, applied in one
transaction, tag ownership checked per op; add is a no-op if present; 1000 people per tag →
`memberLimitReached` (whole call fails); the person must exist; tagging yourself is refused
(`invalidTag`); a person currently blocked either way (`block_hides`) can be removed but not added;
`PersonTag.count` = members not hidden by `block_hides`; `countOffField` = members not in
`person_visible_peer_ids_tx(owner)` and not bond / contact / pinned (use the same membership sets the
snapshot reader uses — expose a small SQL helper, no MR call beyond the memoised visible set).
`personTagsOf(personId)` returns `own: [tag ids]` (auto part in A5).

**Tests (write first):** add/remove/batch; idempotency; limit; blocked person excluded from counts
and from `personTagsOf`; off-field count for a member who lost visibility; another user's id in ops
→ `tagNotFound`, nothing written.

**Done when:** tests green.

### A4 — Realtime kind `person_tag`

**Goal:** spec §11.4.

**Files:** new migration: `person_tag_revision` bump + deferred constraint trigger
`notify_person_tag_change` on `person_tag`, `person_tag_member`, `person_auto_tag_pref`,
`person_tag_suggestion_state` (pattern `notify_constellation_anchor_change`, m0229: at most once per
owner per transaction, `emit_realtime_entity_change_strict('person_tag', owner, 'update', ARRAY[owner], jsonb_build_object('revision', …))`);
`S/consts/realtime_consts.dart` (`kRealtimeAlwaysEchoKinds` += `person_tag`);
`websocket_path_entity_changes.dart` `_forwardedExtrasByKind` (`'person_tag': {'revision'}`);
`docs/contracts/realtime-entity-contract.json`; `test/architecture/realtime_entity_contract_test.dart`
(publisher list). Client enum mirror is B1's.

**Tests (write first, pg):** one membership batch → exactly one notification for the owner only,
payload has `revision` and no tag name / glyph; a transaction touching two owners notifies each once;
the contract test passes.

**Done when:** tests green.

### A5 — Automatic tags

**Goal:** spec §5, §11.2 `person_auto_tags`, §11.3 `personAutoTags`, `personAutoTagPrefSet`,
`personTagsOf` auto part; plan P1, P2, P11, P12.

**Files:** `R/domain/entity/person_auto_tag_kind.dart` (enum with stable wire values:
`mutualContact 0, iTrust 1, trustsMe 2, helpedMe 3, iHelped 4, workedTogether 5, invited 6, forwarded 7, newOnField 8`;
`defaultShowInFilters`); new migration with
`public.person_auto_tags(p_viewer text, p_peers text[] DEFAULT NULL) RETURNS TABLE(peer_id text, kind smallint, n integer, direction smallint)`
(`direction` for `invited`: 1 = invited me, 2 = I invited, 3 = both; else 0), `STABLE`, set-based, no
`mr_*` calls, every row `NOT block_hides(p_viewer, peer)`, deleted Requests never count;
`S/domain/use_case/person_auto_tags_case.dart` + repository + resolvers; tests
`test/data/database/person_auto_tags_pg_test.dart`, resolver test.

**Facts:** spec §5 table with the plan's §1 mapping (`beacon_member`, current status P1); "New" =
`person_field_first_seen.first_seen_at > now() - 7 days` (rows come from A7b); "Mutual contact" /
"I trust" / "Trusts me" from `vote_user.amount > 0` (mutually exclusive by construction).
`personAutoTags` = `[{kind, count, showInFilters}]` over `p_peers = NULL`; `personAutoTagPrefSet`
upserts `person_auto_tag_pref`; `personTagsOf.auto = [{kind, n, direction}]`.

**Tests (write first):** one fixture per kind (positive + nearest negative): reciprocal vs one-way
trust; helper of a Request in review (status 5) → "Helped me" for the author and "I helped" for the
helper; same Request cancelled → neither; reopened (5 → 0) → neither (P1); co-members of two Requests
→ `workedTogether` n = 2; deleted Request not counted; accepted invitation both directions →
direction 3; forward edge either way; first seen 3 days ago → New, 8 days → not; blocked peer → no
rows; `p_peers` restricts output; there is no mutation that removes an automatic tag (assert the
schema has none and the membership mutation rejects auto kinds — it only takes own tag ids).

**Done when:** tests green.

### A6 — Tag creation from an automatic tag / from a Request

**Goal:** spec §4.2 "from an automatic tag ("Make it my tag")" and "from a Request (Tag from participants)".

**Files:** A2/A3 files: `personTagCreate(…, fromAutoKind?, fromBeaconId?)`.

**Rules:** `fromAutoKind` copies the current people of that automatic tag (snapshot, `source = 2`);
`fromBeaconId` requires the viewer to be a `beacon_member` of the Request and copies the other
members (`source = 3`), skipping blocked people; both respect the 1000 limit; both in the creating
transaction.

**Tests (write first):** make-mine snapshot equals the auto-tag set at that moment and does not follow
later fact changes; from-Request by a member copies members minus self; by a non-member → refused;
blocked member skipped.

**Done when:** tests green.

### A7a — Field membership: T, B, presence

**Goal:** spec §3.1–3.3 (server side), plan §1 D9 row.

**Files:** new migration: `public.person_temporary_forward_visible(p_viewer text, p_peer text)` and
`public.person_temporary_forward_peers(p_viewer text) RETURNS TABLE(peer_id text, beacon_id text)`:
R authored by peer, `kind = 0`, `status IN (0, 7, 8)`, a `beacon_forward_edge` to the viewer for R
with `cancelled_at IS NULL`, and (the viewer's `inbox_item` for R has `status IN (0, 1)` **or** an
active `beacon_help_offer` (status 0) by the viewer on R), `NOT block_hides`;
`S/data/repository/constellation_field_snapshot_reader.dart` (`read()` :31): add B
(`person_bond_peers`) and T to the people set (inside the reserved-or-graph split, see A7b for caps);
`ConstellationPeerRecord` (`S/domain/entity/constellation_field.dart:83`) + GQL `ConstellationPeer`
(`custom_types.dart:934`) gain `presence` (`visible | bond | temporary | contactOnly | pinnedOnly`) and
`temporaryBeaconId` / `bondBeaconIds` (ids only, for the panel lines); tests
`test/data/database/person_temporary_forward_visible_pg_test.dart`, extend the snapshot reader pg test.

**Tests (write first):** T true while the viewer holds R (needs_me, watching, active offer); false
after reject (status 2), after R closes / is cancelled / deleted, after the forward edge is cancelled,
for a Post (Q1 default), and when blocked; snapshot contains a mutually visible peer with no Requests
(acceptance 1); a bond peer has `presence = bond`; a T peer has `presence = temporary` and
`temporaryBeaconId`; T grants nothing else (the author's other Requests stay absent from the snapshot).

**Done when:** tests green; existing constellation snapshot tests green.

### A7b — Caps 400, priority, tags and first seen in the snapshot

**Goal:** spec §3.4, §11.2 snapshot fields; plan P3, P8.

**Files:** `S/consts/constellation_consts.dart` (`kConstellationPeerCap = 400`); snapshot reader:
over-cap ordering — reserved (pinned, contact-only, support) outside the cap as today → people with
own tags → direct contacts → B and T → BFS depth over the memoised trust edges from the viewer → id;
per person `ownTagIds` (owner = viewer) and `autoTagKinds` (from `person_auto_tags(viewer, people)`),
`firstSeenAt`; after the read-only snapshot, one short mutating transaction inserts
`person_field_first_seen` rows for the returned people (`ON CONFLICT DO NOTHING`), registered as a
transaction root; GQL `ConstellationPeer` fields; tests extend the reader pg test.

**Tests (write first):** with 450 visible candidates the 400 kept follow the priority order (tagged
ones survive over untagged deeper ones); `ownTagIds` only ever contains the viewer's own tags
(another user's tags on the same person never appear); `autoTagKinds` matches A5 for those people;
first read inserts first-seen rows, second read inserts none; the snapshot transaction is still
`REPEATABLE READ READ ONLY`.

**Done when:** tests green; G1 can run.

### A8 — Suggestion state

**Goal:** spec §7 frequency rules; plan P7.

**Files:** `people_tags_case.dart` + resolvers: query `personTagSuggestionState {canSuggest silencedUntil disabled}`;
mutation `personTagSuggestionRecord(outcome: accepted|skipped|disabled|enabled, clientOpId)`.

**Rules:** `skipped` increments `consecutive_skips`; at 3 set `silenced_until = now() + 30 days` and
reset the counter; `accepted` resets the counter; `disabled` sets `disabled = true`; `enabled` clears
`disabled` and `silenced_until`; `canSuggest = NOT disabled AND (silenced_until IS NULL OR silenced_until <= now())`.

**Tests (write first):** 3 skips → `canSuggest` false for 30 days (move `silenced_until` in SQL to
test expiry); accept between skips resets; disable / enable.

**Done when:** tests green.

### A9 — Privacy behaviour suite

**Goal:** spec §12, acceptance 4.

**Files:** `test/domain/people_tags_privacy_pg_test.dart` (+ fixes where it fails).

**Tests (write first):** A tags B ("Secret-Name-123"), adds, removes, renames, deletes, restores,
creates from a Request where B is a member, and B is on A's Field. Then as B: `personTags`,
`personTagsOf(A)`, `personAutoTags`, `constellationField`, profile and Request queries contain no tag
id or name of A; no `notification_outbox`, `attention_occurrence` or `beacon_activity_event` row
created during the run contains the name; every captured `entity_changes` payload of kind
`person_tag` goes to A only and has no name / glyph; the server log capture (if the test harness
exposes one; otherwise skip that assertion and say so) has no tag name.

**Done when:** tests green.

### G1 — Manual: server snapshot perf at 400

Host-only (never on dev): run the server against `tentura_perfsynth` (`scripts/perf/run_server_db.sh`),
bench `constellationField` FULL with `scripts/perf/constellation_gql_bench.py` before and after A7b;
record p50/p95 in `docs/plans/people-tags-implementation-journal.md`. Acceptance: p95 within 1.5× of
the pre-A7b baseline, no `mr_*` call count increase. Owner decides on a miss.

---

## 3. Phase 1 — client

### B2 — Tag colour tokens + chips

**Files:** `C/design_system/tentura_tag_colors.dart` (ThemeExtension, 8 light/dark swatches
`{container, onContainer, accent}`, registered in both themes, accessor `context.tagColors`);
`C/design_system/components/person_tag_chip.dart` (`PersonTagChip`, `AutoTagChip`, `TagGlyph`);
tests `test/design_system/tentura_tag_colors_test.dart` (contrast like
`capability_group_palette_test.dart`), widget tests for the chips.

**Tests (write first):** every swatch passes the same contrast threshold in light and dark; own chip
shows glyph circle + name + × only when `onRemove != null`; auto chip shows ✦, never ×, dashed border
when `enabled == false`; semantics labels "Neighbour, tag" / "Mutual contact, automatic tag".

### B1 — `people_tags` data layer, store, realtime, gate

**Files:** `C/consts.dart` (`kPeopleTagsEnabled = false`); `C/features/people_tags/` domain (entities,
port, `PeopleTagsCase` singleton store with streams: tags, membership index `personId → Set<tagId>`,
auto counts + prefs, suggestion state), data (`.graphql` documents for every A2–A8 operation,
repository, mappers), exception mirror; `C/domain/entity/realtime/realtime_entity_change.dart`
(`RealtimeEntityKind.personTag`, `fromWire('person_tag')`); `invalidation_service.dart` revision parse;
client realtime contract tests; schema per shared §0.

**Tests (write first):** mapper round trips; store applies optimistic add/remove and rolls back on
error; a `personTag` change triggers one refetch (debounced) and ignores stale revisions;
`clientOpId` is stable across a retry; contract tests pass.

### B3 — "Add to tag…" sheet, tag editor, Undo snackbar helper

**Files:** `C/features/people_tags/ui/widget/add_to_tag_sheet.dart` (checkbox per own tag in `ord`,
"+ New tag" inline → editor → created tag pre-checked; applies one `personTagMembersApply` on close;
"Only you see tags" footer), `tag_editor_dialog.dart` (name, glyph = letter or emoji picker of the
platform keyboard, 8 colour swatches with names for screen readers), `C/ui/widget/undo_snack_bar.dart`
(`showUndoSnackBar(context, text, onUndo)`, persists ≥ 8 s, used by later units).

**Tests (write first):** toggling two tags then closing sends one batch with two ops; creating a tag
from the sheet adds the person to it; name-taken error shown inline; Undo invokes the callback once.

### B4 — Tags block in the person panel and the profile

**Files:** `C/features/people_tags/ui/widget/person_tags_block.dart` ("Your tags" with ×, "+ Tag" →
B3 sheet, "Automatic" with counts/direction, "Only you see tags"); inserted in
`C/features/graph/ui/widget/graph_person_context_panel.dart` (after `_VisibilitySection`, before
`_DiscoverableRequestsSection`; used by both Field and trust graph) and in
`C/features/profile_view/ui/widget/profile_view_body.dart` right after `_ProfileCapabilitySection`
(other people only). B-presence lines ("Working together on «…»", temporary) are B7's.

**Tests (write first):** block lists own tags with × and auto tags without ×; × removes; the word
"tag"/«тег» never appears inside the capability section; hidden when `kPeopleTagsEnabled` is false;
not shown on your own profile.

### B5a — Person menus: profile, Friends, trust graph

**Files:** `profileViewPopupMenuEntries` (`profile_view_app_bar.dart:20`) + "Add to tag…";
`NetworkPersonCard` (`C/features/capability/ui/widget/network_person_card.dart`) gains an overflow
button + long press + secondary tap menu with "Add to tag…" (via `showAnchoredPopupMenu`); trust graph
panel action button "Add to tag…" in `_buildActions` (Field shares the panel).

**Tests (write first):** each entry opens the sheet for the right person; the Friends card menu opens
on overflow tap, long press (touch) and secondary tap (mouse).

### B5b — Person menus: Request People, Post participants, forward rows, chat author

**Files:** `beacon_people_tab_body.dart` rows (`HelpOfferTile`, `_ObserverActiveHelperTile`),
`post_participants_list.dart` `_PersonRow`, `forward_recipient_row.dart`, chat author avatar in
`room_message_tile.dart` (long press / secondary tap on the avatar → small menu: Profile, Add to tag…).
Same three-way trigger as B5a. Self rows show no "Add to tag…".

**Tests (write first):** one widget test per surface: menu reachable, opens the sheet with the right
person id, absent for self and when the gate is off.

### B6a — People tags screen

**Files:** route `/settings/people-tags` (`kPathPeopleTags`, `@RoutePage` `people_tags_screen.dart`,
`RootRouter` entry like `RoutingMuteRoute`); Settings Account group tile; Field app-bar menu item;
screen: "Yours" (glyph, name, count, "N off the field", drag handle **and** move up/down menu items),
"+ New tag", "Automatic" (✦, name, count, "Show in filters" switch); delete from a tag row menu →
`personTagDelete` + Undo snackbar → `personTagRestore`; "Suggest tags" switch when disabled (A8
`enabled`).

**Tests (write first):** reorder by menu sends one update with new `ord`s; delete shows Undo and
restore brings the same id back; switch calls `personAutoTagPrefSet`; no "untagged" counter anywhere.

### B6b — Tag detail and automatic-tag detail

**Files:** `people_tag_screen.dart` (rename/glyph/colour via B3 editor, people list with ×,
"Add people…" picker over field people + search, "Delete tag"); `people_auto_tag_screen.dart` (people
list, "Make it my tag" → A6 `fromAutoKind`).

**Tests (write first):** removing a person updates the count; Add people adds the picked set in one
batch; Make it my tag creates a tag with those people and navigates to it.

### B7 — Field: membership without D9, presence

**Files:** `F/domain/entity/constellation_field.dart` (`ConstellationPerson.presence`, `ownTagIds`,
`autoTagKinds`, `firstSeenAt`, `temporaryBeaconId`, `bondBeaconIds`) + mapper + `constellation_field_fetch.graphql`;
`F/domain/constellation_anchor_composition.dart:279-287` — every person with presence `visible`,
`bond` or `temporary` joins `holderIds`; client priority for the 120 rendered (P4): pinned / contact
(exempt as today) → own-tagged → direct contacts → bond/temporary → path depth;
`F/ui/widget/…` node: dashed outline for `temporary` (new `constellationDashedCirclePath` next to
`constellationEdgeDashPath`), thin dashed link to the Request; panel lines (B: "Working together on
«…»", T: `peopleTagsTemporary`) via the panel's `subtitle` slot.

**Tests (write first):** a visible person with no Requests is kept (acceptance 1) — update the
existing "[D9]" test in `constellation_cap_policy_test.dart` to the new rule rather than deleting it;
temporary person drawn dashed with a link and disappears when the field no longer has them
(acceptance 2); with 300 candidates the 120 kept follow the priority; existing positional-stability
tests (A3) green.

### B8a — Field tag row, filter, lens dim

**Files:** `F/domain/constellation_tag_filter.dart` (`selectedOwn`, `selectedAuto`, `mode: or|and`;
`matches(person)`; combined with `ConstellationFilters` by "and"); `F/ui/widget/constellation_tag_row.dart`
(row 1 own tags + "More N", row 2 auto tags with `showInFilters`, and/or toggle when ≥ 2 selected,
result line `peopleTagsLensResult`, quiet "+ Tag" when there are no own tags); cubit holds the filter
(no recompose, no camera move); dim people outside the selection and their Requests/Posts to 25 %
(reuse the `isDimmedByTrustChain` opacity path, new constant 0.25).

**Tests (write first):** "Neighbour and Helped me" leaves exactly the intersection bright, "or" the
union (acceptance 6); positions and camera unchanged after selecting (compare node positions and
camera before/after); Request filter + tag filter combine by "and"; no row 1 counters when untagged.

### B8b — Lens hull, bottom panel, drag onto chip

**Files:** `F/ui/widget/constellation_tag_hull_layer.dart` (soft hull per selected tag: padded convex
hull / union of node circles in the tag colour, painted between edges and nodes); bottom panel
("{tags} · N people · M Requests", "Open tag view" — hidden until D7b, "Forward a request…" → pick one
of the viewer's open Requests → forward screen with the tag preselected via B11); dropping a dragged
person node on a tag chip adds the tag (snackbar `peopleTagsDroppedOnChip` + Undo) instead of pinning.

**Tests (write first):** hull present only for selected own tags; panel counts; drop on chip calls
apply with `source = 0` and does not pin; Undo removes it.

### B9 — Own-tag glyphs on nodes

**Files:** `_ConstellationMapNode` (`constellation_body.dart:~1453`): up to 2 own-tag glyphs in tag
order at the top-end corner + "+N"; the existing pin badge moves to sit left of the glyph cluster
(keep its key); semantics label "Lena, tags: Neighbour, Workshop; automatic: Mutual contact".

**Tests (write first):** 0/1/2/3 tags render 0/1/2 glyphs + "+1"; automatic tags never drawn; pin
badge still findable by its key; semantics label text.

### B10 — List view grouped by tags

**Files:** `F/ui/widget/constellation_text_view.dart`: "Group by tags" toggle; sections per own tag
(ord) with counts, a person in each of their sections, "Without own tags" last; automatic tags act
as the B8a filter, not sections.

**Tests (write first):** a person with two tags appears in both sections; section counts; filter row
selections narrow the list.

### B11 — Tag chips in forward and compose

**Files:** `F/domain/radius_recipient_selection.dart` (`addByTag(tagId, ids)` recording
`addedByTag[tagId]`; `removeByTag(tagId)` removes only ids it added that were not added individually);
`C/features/forward/ui/widget/forward_recipient_picker.dart` (chip row above the list: own tags, then
auto `helpedMe`, `workedTogether`; ineligible members greyed with the existing reason labels;
"Outside the tag, could help" up to 3 eligible non-members ranked by matching capability labels of
the Request; note `peopleTagsForwardNote` under the button); composer path through
`ConstellationComposerCubit` / `recipients_tab.dart`.

**Tests (write first):** tapping a tag selects only eligible members (acceptance 7); tapping again
removes only tag-added ones, keeping an individually added member; hint shows ≤ 3 non-members; the
note is visible; the sent forward payload contains no tag data.

### B12 — "Tag them?" suggestions

**Files:** `C/features/people_tags/ui/widget/tag_suggestion_card.dart` (people avatars, own tag chips,
"+ New tag", primary "Add to «X»" when one tag is picked, "Not now", menu "Don't suggest again";
"Only you see tags. They won't be notified."); placements: closure author view (members without own
tags), `OfferAcceptedEventSubcard` author side (the helper), forward sent message action
"Add to tag…" when ≥ 2 recipients, other profile after the trust write turns `isMutualFriend` true,
"Tag from participants" button on the Request People tab (always; A6 `fromBeaconId`). Every card
checks `canSuggest` (A8) and records `accepted / skipped / disabled`.

**Tests (write first):** card shown once per event and only when `canSuggest`; Not now records
`skipped`; after 3 skips (server state) no card (acceptance 8); never creates a badge, dot or
notification (assert no attention / inbox calls).

### R1 — Ship phase 1

Flip `kPeopleTagsEnabled`; client version bump (pubspec + `web/index.html`); update
`docs/features/constellation.md` (membership, D9 gone) and `docs/plans/constellation-edge-semantics.md`
(D9 superseded); full wrapped suites serially + custom lints. Commit body `Closes #254`.

### M1 — Manual: phase 1 local-stack check

`local-debug` skill, two QA users: tag on device 1 appears on device 2 without reload (acceptance 3);
lens, tag row, People tags screen, forward chips, a suggestion after closing a Request; B sees nothing
of A's tags.

---

## 4. Phase 2 — arrangement

### C2 — Anchor batch cap 64 → 400

**Files:** `S/domain/use_case/constellation_anchor_case.dart` (`ops.length > 64` → 400, named
constant), `F/domain/use_case/constellation_placement_case.dart:21` (`kConstellationPlacementBatchCap = 400`);
tests: 400-op batch applies atomically within the existing retry budget (pg), 401 → refused; client
splits only above 400.

### C1 — Layout snapshots

**Files:** new migration `constellation_layout_snapshot(id PK 'LS…', viewer_id … CASCADE, kind smallint CHECK (kind IN (0,1)), reason smallint, anchors jsonb NOT NULL, anchor_count integer NOT NULL, created_at)`;
partial unique `(viewer_id) WHERE kind = 0`; `S/domain/use_case/constellation_layout_snapshot_case.dart`
+ repository + resolvers `constellationLayoutSnapshots`, `constellationLayoutSnapshotSave(kind, reason, clientOpId)`
(reads the viewer's current anchors server-side: `{targetKind, targetId, x, y, coordinateSpaceVersion}`;
history keeps the newest 20 — delete older in the same transaction; favourite overwrites),
`constellationLayoutSnapshotRestore(snapshotId, clientOpId)` (one transaction through the existing
anchor apply path: upsert snapshot anchors whose target still exists, unpin current anchors absent
from the snapshot, writes a `restore` history snapshot first; emits the existing `constellation_anchor`
realtime once); exceptions `snapshotNotFound`; Hasura-untracked test.

**Tests (write first):** save → list; 21st history drops the oldest; favourite single; restore result
equals the snapshot for present targets, keeps stored positions for absent people (they return when
visible), leaves people newer than the snapshot unpinned; another viewer's snapshot id →
`snapshotNotFound`; idempotent replay.

### D1 — Arrangement history (undo / redo)

**Files:** `F/domain/use_case/constellation_arrangement_history.dart` (screen-session stack, 50
entries; entry = `AnchorBatchEntry(forward ops, inverse ops)` or `LocalLayoutEntry(before hints, after hints)`);
wired into `ConstellationPlacementCase.place/unpin/resetAll` and `ConstellationCubit`
(`_dropNode`, `placeArrangement`, `rearrangeFreeNodes`); a user action spanning several server
batches is one entry; a failed batch marks its entry non-undoable.

**Tests (write first):** drag → undo restores the previous anchor (or unpins a new one) → redo
re-applies; sector arrangement of 30 people = one entry; rearrange free nodes undo restores prior
hints; 51st entry drops the oldest; redo cleared by a new action.

### D2 — Arrange menu, undoable reset, shortcuts, gate

**Files:** `C/consts.dart` `kFieldArrangeV2Enabled = false`; `F/ui/widget/constellation_arrange_sheet.dart`
(mockup B1: undo/redo always visible, Tidy up (D3), Rearrange, Arrange in sector (disabled without
selection), Restore favourite / Save as favourite / Layout history (D6), Reset positions); replaces
the Rearrange/Reset buttons in `constellation_camera_controls.dart` when the gate is on; Reset: no
confirm dialog, writes a `reset` history snapshot (C1) then resets; Undo = restore that snapshot;
`constellationResetPositionsBody` loses "This can't be undone"; desktop shortcuts Ctrl/Cmd+Z,
Ctrl/Cmd+Shift+Z; not shown in the tag view.

**Tests (write first):** reset then undo restores every anchor (acceptance 10); shortcuts call
undo/redo; sheet hidden in tag view mode.

### D3 — Tidy up + move trails

**Files:** `F/domain/constellation_tidy_up.dart` (pure: input = positions, radii, label boxes, pinned
set, ego, optional selection or visible rect; output = moves; resolves node and label overlaps with
minimal moves, keeps each person's ring and angular order, max move 1.5 node diameters, never moves
pinned, deterministic; frame-sliced if > 16 ms at 400); result applied as local prior hints (P5) +
history entry + `constellationTidied` Undo snackbar; move trails layer fading over 1.5 s (reduced
motion: trails only).

**Tests (write first):** overlapping fixture → no overlaps after, every move ≤ 1.5 diameters, pinned
unchanged, ring index and angular order unchanged (acceptance 11); same input → same output; only
the visible rect / the selection is touched; 400-node fixture under the budget (bench test, not a
gate assertion on timing in CI).

### D5 — Rearrange everyone including pinned (preview)

**Files:** preview mode in the cubit: compute full re-layout ignoring pins, draw ghosts + dashed
arrows, sheet "{n} people will move" with Apply / Cancel; Apply = history snapshot (`rebuild`) + one
history entry + batch upsert of every pinned target (P6).

**Tests (write first):** preview writes nothing; Cancel restores; Apply writes one snapshot and one
batch; undo restores all.

### D6 — Layout history sheet, favourite, automatic history

**Files:** `constellation_layout_history_sheet.dart` (favourite on top, then history newest first;
thumbnail painter from snapshot anchors; tap = preview on the field; "Restore this" → C1 restore,
undoable); automatic `save(history, reason)` before Tidy up, Rearrange, Arrange in sector, Gather,
Restore favourite, Reset, restore; during manual drags at most once per 10 min (`manual`);
"Save as favourite" undoable (undo restores the previous favourite).

**Tests (write first):** each bulk action triggers exactly one save before it applies; drags save at
most once per 10 min (fake clock); preview then restore on "device 2" (second cubit) gives the same
anchors (acceptance 13).

### D7a — Tag view layout algorithm

**Files:** `F/domain/layout/constellation_tag_view_layout.dart` (pure, deterministic): input = tag
members with their Field angle from ego and trust depth; ≤ 30 people: keep each person's direction,
collapse radial gaps to dense rings; > 30: rings by trust steps; union of several tags: one cluster
per tag around ego by the tags' mean directions, people with several tags placed between their
clusters; wrapped as a `SceneLayoutAlgorithm` without pins.

**Tests (write first):** same data → same positions; directions preserved within tolerance for ≤ 30;
> 30 uses rings by depth; a two-tag person lies between both cluster centres; no anchor writes.

### D7b — Tag view mode

**Files:** `ConstellationCubit` `viewMode.tagView(tagIds)`; header in the tag colour "Neighbour · 5"
+ Exit; others switch hide / as dots / as is (default dots); dragging does not pin (drop = no-op
snap back); tap opens the panel; "Find in tag"; "Forward a request…" (B8b flow); no Arrange menu;
enter/exit animation 400–500 ms from/to Field places (reduced motion: instant); B8b's "Open tag view"
becomes visible.

**Tests (write first):** entering and leaving changes no main-Field position and writes no anchors;
re-entering gives the same layout (acceptance 12); drag in tag view writes nothing; others modes.

### R2 — Ship phase 2

Flip `kFieldArrangeV2Enabled`; version bump; docs (`docs/features/constellation.md` arrangement
section); suites + lints. Commit body references #251 (reset now undoable).

---

## 5. Phase 3 — scale and magnets

### E8 — Person search 200 + focus highlight

`kConstellationPersonSearchLimit = 200` (`constellation_person_search.dart:12`); `focusPerson` moves
the camera and highlights the node for 2 s. Tests: 200 results; highlight clears after 2 s (fake
clock).

### E1 — One zoom-level owner

**Files:** `C/consts.dart` `kFieldSemanticZoomEnabled = false`; `F/ui/utils/constellation_presentation_frame.dart`:
`ConstellationDetailLevel { close, district, overview }`, thresholds 0.85 / 0.45, settled level =
pure function of scale (hysteresis only while a gesture is active); new
`F/ui/scene/constellation_zoom_level_controller.dart` (ValueListenable) owned by the screen;
`constellation_viewport_overlay.dart:62` and `constellation_body.dart:93` read it instead of keeping
`_detail`; with the gate off map `close/district/overview` onto today's behaviour.

**Tests (write first):** extend `test/features/constellation/constellation_presentation_frame_test.dart`
with #595's criteria: labels monotonic between the cut-off and 0.85; same scale → same labels
regardless of zoom direction; overlay and body always agree on the level.

### E2a — Overview: dots, no labels, hit targets

**Files:** frame + node builder: at overview (gate on) 5 pt dots coloured by the first own tag (grey
without tags), no person / Request labels, no "+N" chips, no forced labels; tap targets ≥
`kMinInteractiveDimension`, overlapping targets resolve to the nearest node
(`resolveConstellationTap`). Commit body `Closes #595`, `Closes #640` (when R3 ships; mention in R3
if the gate is still off).

**Tests (write first):** at 0.4 with 400 people no label and no chip in the frame; a tap between two
dots selects the nearer; dot colour = first own tag.

### E2b — Overview: grid cluster labels + edge bundles

**Files:** `F/domain/constellation_grid_clusters.dart` (screen-space grid, cell ≈ 72 pt, label = most
frequent own tag "Workshop · 42" else "55 people"); label layer at overview; edges at overview drawn
as bundles ego → cluster with width ∝ count; district: faint edges, bright for the selection.

**Tests (write first):** clustering is a pure function of screen positions; label text rules; bundle
widths.

### E3 — District level

20 pt circles with initials and a ring in the first own-tag colour; names within the existing label
budget (UX5) with priority selected → pinned → people of the selected tag → nearest by path. Tests:
priority order under a tight budget.

### E6 — Minimap

Collapsible 104×104 pt at overview and district: all people as dots, viewport frame, tap moves the
camera. Tests: frame matches the camera; tap converts minimap → world coordinates.

### E5a — Community detection + overview placement (pure)

**Files:** `F/domain/layout/constellation_communities.dart`: Louvain (Leiden refinement optional)
over trust edges among Field people, fixed seed, deterministic; partition matching to the previous
partition (max overlap) so clusters keep sectors; placement: each community a compact cluster in the
sector of its members' mean Field direction, pulled towards its pinned members; pinned people stay.

**Tests (write first):** same graph → same partition and positions; adding one edge keeps unaffected
communities' sectors; communities never exposed outside the function's return value (no entity
field, no persistence API).

### E5b — Community layout integration + transitions

**Files:** overview `SceneLayoutAlgorithm` selected by the zoom level; recompute only when Field
membership or edges change; leaving overview dots travel to their normal places (400–600 ms, staged
by community), entering the reverse; reduced motion instant; dragging a dot at overview pins it and
takes it out of the community layout.

**Tests (write first):** zooming in/out without data change does not recompute; transition ends at
the normal positions; drag at overview writes one pin.

### E7a — Gather + selection actions at every level

**Files:** `F/domain/constellation_gather.dart` (compact cluster at the selection centroid, pins
everyone, one batch, one history entry); selection bar actions: Add to tag… (B3 for many people: one
batch), Tidy up (D3 on selection), Arrange in sector, Gather, Unpin; box/lasso selection usable at
overview and district (#642).

**Tests (write first):** Gather of 40 people = one batch + one undo; Add to tag on a selection = one
apply call; selection works at overview.

### E7b — Drag a cluster at Overview

Dragging a grid cluster label moves the whole cluster as one group and pins everyone in it (one
batch, one undo). Tests: acceptance 16.

### E4 — Render cap 400

`kConstellationRenderPeerCap = 400` when `kFieldSemanticZoomEnabled`; staged bulk animations by
cluster (not 400 tweens). Tests: 400 people composed; existing cap-policy tests adjusted. Done after
G2.

### G2 — Manual: wasm bench at N = 400

Host only: `scripts/run_client_profile_web_bench_local.sh` (`--wasm` default) at N = 400 with zoom on:
no main-thread task > 50 ms across drop → ack → reflow, drag frame < 8 ms UI time (I4). Record in the
journal; root-cause misses as new beads.

### E9a — Magnets: server

Table `constellation_tag_magnet(viewer_id, tag_id → person_tag CASCADE, x_units, y_units, revision, PK (viewer_id, tag_id))`,
V2 list/upsert/remove (owner-only, clientOpId), realtime through `person_tag`. Tests: CRUD,
cascade on tag delete, privacy.

### E9b — Magnets: client

Drop an own tag chip on the Field → magnet label; unpinned tagged people drift towards it (soft
force in the layout, two magnets → between); magnet menu Remove; never moves pinned; inactive in the
tag view; menu alternative "Place as magnet". Tests: drift direction, pinned unchanged, tag view
unaffected.

### R3 — Ship phase 3

Flip `kFieldSemanticZoomEnabled`; version bump; docs; suites + lints; commit body `Closes #595`,
`Closes #640`.

---

## 6. Acceptance → unit map

| Spec acceptance | Units |
|---|---|
| 1 person without Requests on the Field | A7a, B7 |
| 2 temporary author, disappears after close | A7a, B7 |
| 3 cross-device tag sync | A4, B1, M1 |
| 4 no leak to the tagged person | A9 |
| 5 "I helped" on review, never on cancel | A5 |
| 6 and/or lens, camera fixed | B8a |
| 7 tag in forwarding selects eligible only | B11 |
| 8 3× Not now → 30 days | A8, B12 |
| 9 automatic tags not removable; hiding keeps them in panels | A5, B4, B6a |
| 10 one Undo per bulk action incl. reset | D1, D2, D5, D6, E7a |
| 11 Tidy up ≤ 1.5 diameters, pinned fixed | D3 |
| 12 tag view changes nothing, deterministic, no pins | D7a, D7b |
| 13 favourite restore cross-device | C1, D6 |
| 14 overview: no labels/chips, hit targets, #595 criteria | E1, E2a, E2b |
| 15 community layout deterministic, no trace | E5a, E5b |
| 16 cluster drag = one batch, one undo | E7b |
