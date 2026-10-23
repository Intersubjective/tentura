# People tags, Field arrangement and semantic zoom — plan

**Status:** rev 1 (2026-10-23), draft.
**Source of truth for product behaviour:** GitHub issue
[#699](https://github.com/Intersubjective/tentura/issues/699) — the summary, the owner decisions of
2026-10-23 and the collapsed "Full specification (EN)" (§0–§17). Mockups A/B/C live on branch
`claude/project-thread-rsrtg6` under `docs/design/people-tags/` and are linked from the issue.
"Spec §N" below points into that specification.
**Detailed work plan:** [`people-tags-implementation-plan.md`](people-tags-implementation-plan.md).
**Closes (via the implementing commits):** #254, #595, #640. Related: #253, #251, #246, #642, #644, #698.

This document does not restate the spec. It records how the spec maps onto the code as it is on
2026-10-23 (`main` @ `777680fca`, latest migration `m0260`, possibly `m0261+` from the post-lifetime
epic by the time this starts), the places where the spec and the code disagree, the technical
decisions the spec leaves open, and the order of work.

---

## 1. Spec ↔ code reconciliation

The spec was written against `0275957`. These statements do not match the code; the plan uses the
right-hand column.

| Spec says | Code reality | Plan uses |
|---|---|---|
| "member (level ≤ 1)" of a Request (§5, §3.1 B) | no participant "level" exists; membership is the `beacon_member` view (`m0193.dart:~5233`): published author, stewards, participants with `role = 1 OR room_access = 3` | `beacon_member` on Requests (`kind = 0`). "Not author" = `beacon_member` minus `beacon.user_id`. |
| Rule D9 is a client rule in `holderIds` | correct, but enforced by `resolveConstellationPaths` (`lib/domain/constellation/constellation_path_resolution.dart`) + `resolveAndCapConstellation`; the server already ships every visible peer up to the cap | Drop D9 by making every V ∪ B ∪ T person a holder in `composeConstellationPresentation` (`constellation_anchor_composition.dart:279-287`). |
| `kConstellationSectorMaxPeople` = 64 | real constant is `kConstellationSectorMaxItems = 256` (`constellation_multi_selection.dart:12`); the **64** caps are `kConstellationPlacementBatchCap` (client) and the server `ConstellationAnchorCase` (`ops.length > 64`) | Raise both 64s to 400; leave 256 as is (it is a sector-arrangement item cap, not a batch cap). |
| Snapshot anchor field `csv` | no such field; anchors carry `coordinate_space_version` (= 1) and a decimal revision | `csv` = `coordinate_space_version`. |
| Detail levels: add a third level to `ConstellationDetailLevel` | it already has three: `normal / overview / bare`, thresholds 0.85 / 0.70 / 0.3 with hysteresis (`constellation_presentation_frame.dart:10-20`), duplicated state in `constellation_viewport_overlay.dart:62` and `constellation_body.dart:93` | Replace with `close / district / overview` at 0.85 / 0.45, one owner of the level; the settled level is a pure function of scale. |
| Capability "Labels" block (#134) "stays above" in the person panel | it is only on the profile page (`_ProfileCapabilitySection`, `profile_view_body.dart:~450`); the Field / graph panel has none | Profile: tags block directly below the capability section. Panel: tags block only (no labels block is added). |
| Person menu "Add to tag…" on the Field (long press) | the Field has no person menu; long press / secondary tap on canvas = composer create; a node tap opens `GraphPersonContextPanel` | Field and trust graph: an "Add to tag…" action in the panel. Other surfaces per §4.4. |
| Ineligible reason "already saw this request" | no such string; reasons come from `CandidateInvolvement` + `forwardRecipientRelationLabel` | Reuse the existing reason labels. |
| Undo snackbar pattern | only the inbox Dismiss-all has one; `showSnackBar` auto-dismisses even with an action (#470) | One shared `UndoSnackBar` helper (§4.6). |
| Realtime `RealtimeEntityKind.personTag` | server has no enum: wire strings via `emit_realtime_entity_change_strict`; client enum `RealtimeEntityKind`; contract manifest `docs/contracts/realtime-entity-contract.json` + server and client contract tests | New wire kind `person_tag`, publisher trigger like `notify_constellation_anchor_change` (m0229). |

## 2. Decisions the spec leaves open (plan defaults)

Defaults the implementer follows unless the owner overrides them. **P4, P5 and P6 change visible
behaviour and are listed for owner review in the handoff.**

| # | Question | Plan default | Why |
|---|---|---|---|
| P1 | "Helped me" / "I helped": "reached `reviewOpen` or `closed`" — current status or ever? | current `status IN (5, 6)` | No status-history read at query time; a reopened Request (review → open) loses the tag until it closes again. Cancelled never qualifies. |
| P2 | "Worked together": "any status except deleted" | `beacon_member` on Requests with `status <> 2`; drafts have no members | — |
| P3 | Where "first seen" is written (the snapshot runs `REPEATABLE READ READ ONLY`) | after the snapshot read, a separate short mutating transaction `INSERT … ON CONFLICT DO NOTHING` for the people in the returned snapshot | Same pattern as the visibility-cache fill before the snapshot (`constellation_field_repository.dart:110`). A first ever read marks everyone as seen now; "New" then appears only for people who arrive later — acceptable. |
| P4 | Client render cap 120 → 400 in phase 1? | **No.** Phase 1 raises the server cap to 400 and applies the spec's priority order client-side to pick the 120 rendered; the render cap goes to 400 in phase 3 together with semantic zoom | Spec §3.4 itself: "without zoom 120 is the readability ceiling". |
| P5 | Tidy up moves unpinned people — are results pins? | **No.** Tidy up writes layout prior hints (client-local, like `rearrangeFreeNodes`), not pins; it is undoable in-session. Gather pins (spec says so). | Spec §8.2 scopes Tidy up to "unpinned"; pinning them would silently turn auto people into pinned ones. |
| P6 | "Rearrange everyone, including pinned" — what is written? | one history snapshot, then a single batch that upserts every currently pinned target to its new position; unpinned people are re-laid out locally | Keeps pins pinned (they move, they do not become auto). |
| P7 | Suggestion frequency state (3× "Not now" → 30 days, "Don't suggest again") | server-side, per owner (`person_tag_suggestion_state`) | Survives devices; re-enable lives on the People tags screen. |
| P8 | Ordering of the 400 server peers "by path depth" | BFS depth from the viewer over the already-memoised trust edges of the visible graph (`_allTrustEdges`), ties by id | Server has the edges; no MeritRank calls. |
| P9 | Undo of a tag delete | client keeps the deleted tag + member list; Undo calls `personTagRestore(snapshot)` which recreates the tag with the **same id** | Field glyphs and filters keep working without a refetch race. |
| P10 | Tag colours | new ThemeExtension `TenturaTagColors` with 8 light/dark swatches, contrast-tested like `TenturaCapabilityColors` | Spec: design-system tokens, never literals. |
| P11 | Auto-tag kinds as wire values | smallint enum shared in the root package (`lib/domain/entity/person_auto_tag_kind.dart`); "Invited me / I invited" is one kind with a direction field | Spec §5 shows it as one tag with the actual direction in the panel. |
| P12 | "Trusts me" discloses `vote_user(p → ego)` | allowed — the spec lists it and the profile already shows mutual / one-way trust lines | Recorded so a reviewer does not flag it as a leak. |

Open questions Q1–Q4 of the spec keep their defaults (T = Requests only; caps 400/400/400; keep the
"Outside the tag" hint; trust graph = panel only in phase 1).

## 3. Architecture

### 3.1 Server

- **Tables (phase 1 migration):** `person_tag`, `person_tag_member`, `person_auto_tag_pref`,
  `person_field_first_seen`, `person_tag_suggestion_state`, `person_tag_op_log` (clientOpId
  idempotency, same shape as `constellation_anchor_op_log`: `(owner_id, client_op_id)` + SHA-256
  fingerprint + stored result). Phase 2: `constellation_layout_snapshot`. Phase 3:
  `constellation_tag_magnet`. Every FK to `"user"` is `ON DELETE CASCADE` (owner and person), so
  account erasure and "p deleted → removed from all tags" need no code (`UserErasureCase` relies on
  cascades). None of these tables is tracked by Hasura; an architecture test asserts it (the
  existing `hasura_metadata_closure_tables_untracked_test.dart` only covers closure tables).
- **Ids:** `generateId('PT')` for tags, `generateId('LS')` for snapshots, `generateId('TM')` for
  magnets (`S/utils/id.dart`).
- **Exceptions:** new code space **1900** `PeopleTagsExceptionCode`
  (`tagNameTaken, tagLimitReached, memberLimitReached, tagNotFound, snapshotNotFound, invalidTag, opIdReused`)
  in `domain/exception_codes.dart`, mirrored on the client.
- **Use cases:** `PeopleTagsCase` (own tags + membership + prefs + suggestion state),
  `PersonAutoTagsCase` (read side), `ConstellationLayoutSnapshotCase` (phase 2). All writes through
  `MutatingUnitOfWorkPort` with `actorUserId = sub`; every new transaction root added to
  `test/architecture/transaction_entry_inventory.txt`.
- **Automatic tags:** one set-based SQL function
  `person_auto_tags(p_viewer text, p_peers text[] DEFAULT NULL) RETURNS TABLE(peer_id text, kind smallint, n integer, direction smallint)`.
  Facts: `vote_user`, `beacon_member` + `beacon.status`, accepted `invitation`, `beacon_forward_edge`,
  `person_field_first_seen`. **No MeritRank calls**; every row filtered by `NOT block_hides`.
  Counts for the People tags screen call it with `p_peers = NULL`.
- **Field membership:** `person_temporary_forward_visible(viewer, peer)` + a set function used by
  the snapshot reader; the reader adds B (`person_bond_peers`) and T to the people set, computes
  `presence`, attaches `ownTagIds` / `autoTagKinds` / `firstSeenAt` per person, raises
  `kConstellationPeerCap` to 400 and orders over-cap candidates per spec §3.4 / P8.
  Visibility stays the closed form (`person_visible_peer_ids_tx`); **never** add per-row MR calls
  (see `docs/plans/server-db-concurrency-architecture-review.md` and the 2026-10-05 perf rework).
- **Realtime:** wire kind `person_tag`, owner-only recipients, payload `{revision}` only (no names),
  emitted by a deferred constraint trigger once per transaction per owner (pattern m0229), added to
  `kRealtimeAlwaysEchoKinds` (other devices of the same user must refresh) and to the contract
  manifest + both contract tests. Snapshot restore reaches other devices through the existing
  `constellation_anchor` kind.
- **Privacy:** tag names never leave the owner's own V2 responses. Enforced by: owner-scoped queries
  only (`owner_id = sub`), no Hasura tracking, realtime payload without names, log lines with ids
  only, and a behavioural test suite (unit A9) that drives tagging and then inspects other users'
  responses, `notification_outbox`, `attention_occurrence`, and captured realtime payloads.

### 3.2 Client

- **New feature `features/people_tags/`** (Clean Architecture): entities `PersonTag`,
  `PersonAutoTagKind` (root), `PersonTagsOf`; port + remote repository (ferry documents);
  `PeopleTagsCase` singleton store: own tags, membership index `personId → tagIds`, auto-tag counts and
  prefs, suggestion state; subscribes to `RealtimeSyncCase.changesFor({personTag})`.
- **Design system:** `TenturaTagColors` ThemeExtension (P10); components `PersonTagChip` (own,
  filled, glyph circle, optional ×), `AutoTagChip` (outline + ✦, dashed when off), `TagGlyph`.
- **Shared sheet:** `AddToTagSheet` (checkbox per own tag + "+ New tag" inline) used by every
  surface; `TagEditorDialog` (name / glyph / colour).
- **Field:** the field entity gains `presence`, `ownTagIds`, `autoTagKinds`, `firstSeenAt` per person;
  `ConstellationTagFilter` lives next to `ConstellationFilters` (Requests) and combines by "and";
  lens = opacity dim (reuse the trust-chain dim path) + a hull layer between edges and nodes; the tag
  view is a separate `SceneLayoutAlgorithm` run by `ConstellationCubit` in a `viewMode`; the undo
  stack lives beside `ConstellationPlacementCase` (`ConstellationArrangementHistory`).
- **Undo model (phase 2):** an entry is either an anchor batch with its inverse (previous positions /
  unpin) or a local-layout entry (previous prior hints). One user action = one entry, however many
  64/400-op server batches it needs. Bulk actions also write a server history snapshot first.
- **Semantic zoom (phase 3):** one `ConstellationZoomLevelController` owns the level; overlay, body
  and frame read it. Overview geometry (community layout) is a `SceneLayoutAlgorithm` selected by
  level; it never leaves the client.

## 4. Surfaces for "Add to tag…" and tag blocks

1. Field and trust graph: `GraphPersonContextPanel` — tags block + "Add to tag…" action.
2. Other person's profile: `profileViewPopupMenuEntries` item + tags block under the capability
   section.
3. Friends list (`NetworkPersonCard`), Request People tab rows (`HelpOfferTile`,
   `_ObserverActiveHelperTile`), Post participants (`_PersonRow`), forward recipient rows
   (`ForwardRecipientRow`), chat author (avatar): a person menu opened by a visible overflow button,
   long press on touch and secondary tap on mouse (never long press alone), via
   `showAnchoredPopupMenu`.
4. People tags screen: Settings → Account group, and the Field app-bar menu.
5. Suggestions (spec §7): closure author view, `OfferAcceptedEventSubcard` (author side), the forward
   sent message (action "Add to tag…"), the other profile after the trust write makes it mutual
   (`Profile.isMutualFriend` false → true inside `ProfileViewCubit._setRelationship`), and "Tag from
   participants" on the Request People tab.
6. Undo snackbar helper (`UndoSnackBar`) for tag delete, drag-onto-chip and every bulk arrange action.

## 5. Phases, lanes and order

The spec's phases are kept; inside them work runs in lanes that only meet where data is needed.

| Lane | Units (implementation plan) | Can start |
|---|---|---|
| Server tags | A1 schema → A2 tag CRUD → A3 membership → A4 realtime; A5 auto tags; A6 create-from; A8 suggestion state; A9 privacy suite | A1 at once |
| Server Field | A7a T + B presence → A7b caps, priority, tags-in-snapshot, first seen | A7a at once; A7b after A3, A5 |
| Client foundation | B2 tag colours + chips (no server dependency) | at once |
| Client tags | B1 store → B3 sheet/editor → B4 panel/profile, B5a/b menus, B6a/b People tags screen, B12 suggestions | after A2–A5, A8 |
| Client Field | B7 membership + presence → B8a tag row + lens → B8b hull + bottom panel, B9 node glyphs, B10 list grouping | after A7b, B1 |
| Forward / compose | B11 tag chips in pickers | after B1, B2 |
| Arrangement | C2 batch cap → C1 snapshots → D1 undo → D2 Arrange menu, D3 Tidy up, D5 preview, D6 history | C2 at once |
| Tag view | D7a layout → D7b mode + animations | after B8a |
| Zoom & scale | E8 search 200 (independent), E1 level owner → E2a overview dots/hits, E2b cluster labels, E3 district, E6 minimap → E4 render cap 400 → E5a/b community layout; E7a/b bulk + cluster drag; E9a/b magnets | E1 and E8 at once |

**Order optimisation for a one-at-a-time scheduler (Alloy):**
1. Front-load the long dependency chain and the risky server work: A1, A5, A7a, A2, A3 (P1).
2. Fill gaps with independent leaves that unblock later lanes or close existing issues early: B2,
   C2, E1, E8 (E1 + E2a close #595 / #640 without any tag work).
3. Phase 1 client after its server inputs; phase 2 interleaves because it depends only on C1/C2/D1.
4. Phase 3 rendering last; manual performance gates (server snapshot at 400 on `tentura_perfsynth`,
   client wasm bench at N = 400) sit before the render-cap raise is considered done.

Critical path: A1 → A2 → A3 → A7b → B7 → B8a → D7a → D7b (tag view), with B1 → B3 → B12 a close
second.

## 6. Risks

| Risk | Mitigation |
|---|---|
| Snapshot cost at 400 people (edges, auto tags, T) | Auto tags restricted to `p_peers`; no MR calls; manual perf gate on `tentura_perfsynth` (local only, never on dev). |
| Client frame budget at 400 nodes (I4: no main-thread task > 50 ms) | Render cap stays 120 until phase 3 (P4); wasm bench gate before E4 is done; layouts are frame-sliced. |
| Privacy regression (tag names leaking) | A9 behavioural suite; payloads id-only; Hasura untracked test. |
| Undo across 64/400-op batches and partial failures | One history entry per user action; a failed batch marks the entry non-undoable and shows the existing retry. |
| Spec drift vs. code (§1) | Implementers follow the "Plan uses" column; stop and report on new mismatches. |
