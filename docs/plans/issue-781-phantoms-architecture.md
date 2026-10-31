# #781 Phantoms — "map of my people" architecture

Status: **rev 9 (2026-10-31)** — design walk-through with the owner done
(D1–D27); rev 7 applied adversarial review round 1 (R1–R37), rev 8 round 2
(R38–R58) and rev 9 round 3 (R59–R72), both with reviewer Muse Wonder and
critics Gemini 4 Argon + GPT-5.6-Sol. Change log §14.
Source: GitHub #781 (body + owner comments 2026-10-25, decisions comment
2026-10-31), mockups `docs/design/phantoms/phantoms-{a,b}.png`.

Scope: all of #781 — Phase 1 (private placeholders + invites), private notes
and avatars on anyone, forwarding a Request to a placeholder, selective contact
import, the "already on Tentura" check, and Phase 2 (suggested ties, joiner
review, shared visibility, clusters). Delivered as separate epics run in
blocks (§12).

---

## 0. Vocabulary

| Term | Meaning |
|---|---|
| **phantom** | Internal/code name for a placeholder node. "Placeholder" is already taken in code: unreadable pinned Requests (`request.isPlaceholder`) and tombstoned pins (`ConstellationPinPlaceholderSheet`). |
| owner | The user who created the phantom. |
| merge | Binding a phantom to a real account `U`. The phantom row survives with `merged_user_id = U`, together with its own private rows (tags, note, avatar), so Undo/Unlink can restore it. |
| orphaned | A merged phantom whose `merged_user_id` became NULL because `U` erased their account. Hidden everywhere; cannot be unmerged. |
| claim | Phase 2 view of a phantom: "owner X says they know someone called Anna". |
| cluster | Phase 2: phantoms of different owners confirmed to be the same person. |
| tie | Phase 2: a suggested relation drawn by an owner. Never trust (D20). |

User-facing copy: **«Not on Tentura yet» / «Ещё не в Tentura»**; Field filter
chip «Not here yet · N». Never "phantom" in UI.

---

## 1. Decisions

All decisions below are binding. D1–D27 are the owner's (walk-through
2026-10-25 / 2026-10-31); P1–P5 are technical choices of this plan.

- **D1 No MeritRank presence.** Phantoms never appear in `user`, `vote_user`,
  `trust_evidence`, `user_trust_edge`, or pgmer2. Not even owner→phantom.
  Supersedes the 2026-10-25 "owner→placeholder is an ordinary MR edge"
  comment and the A3 mockup footer line.
- **D2 Owner-derived visibility.** Viewer `v` sees phantom `h` iff `v` is an
  owner of `h`, or some owner `o` of `h` satisfies
  `o = ANY(person_visible_peer_ids_tx(v, ''))` and `NOT block_hides(v, o)`.
  Rationale: for a leaf with a single in-edge `o→h`, MeritRank gives
  `S_v(h) > 0 ⟺ S_v(o) > 0`, so this *is* "visible like a regular node in that
  place of the graph", minus Monte Carlo noise. Rejected alternative (phantoms
  as MR nodes): the symmetric rule fails for them anyway (`S_h(v) = 0`), the
  owner's outflow gets diluted (moves real people's scores), every MR consumer
  would have to filter phantoms out (fail-open), trust tables FK to `user`
  which Hasura exposes by id, and MR has no rename.
  Phase 1 uses only the "`v` is an owner" branch.
- **D3** Phantoms never expire. Owner can delete at any time.
- **D4** Cap **200 active phantoms per owner** — enforced on every path that
  makes a phantom active (create, batch create, unmerge).
- **D5** Phantoms **count toward Field caps** (#699 §3.4).
- **D6** Same-name hint card (A4) is on; the owner confirms; never automatic.
- **D7** Private notes, private avatars: any user, on any person (real or
  phantom); visible only to the author; never in merges for others,
  notifications, logs or MR; author-only export.
- **D8** Ties must start at the author or one of the author's own phantoms
  (a creation rule; ties keep referencing phantom ids after merge, §10.1).
- **D9** "Already on Tentura" check via keyed HMAC, behind a per-user
  setting (default ON, explicit at signup), rate-limited, boolean answer. A
  match against *another owner's* phantom is shown only if that phantom is
  visible to the asker (D2).
- **D10** Shared phantoms carry name + ties only; photo/note/tags/contact
  points stay with each owner. Always attributed ("added by Vadim").
- **D11** Removal paths: owner deletes; "Ask Vadim to remove this
  placeholder" (B2, D22); "Remove me from everyone's maps" (B4, D21); non-user
  deletion request via the privacy email address (D26). The D26 runbook must
  exist before shared visibility (M8).
- **D12 Separate tables.** Phantom data lives in its own tables (§3), not
  tracked in Hasura. Exceptions where an existing structure must learn
  phantoms: `constellation_anchor` (already polymorphic), the people-tags
  repository (mixed member lists, §3.2), and `invitation.phantom_id` (§4).
- **D13 Merge rules:** if the phantom has a pin it wins over U's pin, tags
  union, notes shown appended (display-time, nothing copied), an existing
  private avatar on U wins (§5.2).
- **D14 Same-name hint:** first-token casefold match + "newly seen" (§5.4).
- **D15 Request invites never block joining.** Applies to *all* Request
  invites, not only phantoms: if the Request is closed/expired/unreadable, the
  issuer can no longer forward, or the parent forward chain was cancelled, the
  invite falls back to an ordinary user-to-user invite (consumed; mutual
  connection with the issuer) and the invite screens say so: *"Vadim invited
  you to «Request», but it has already closed. You're still welcome on
  Tentura, and you're now connected with Vadim."* Landing preview (before
  signup), in-app accept screen, and a card after joining. Lands in M0.
  **Existing accounts:** a Request invite accepted by an existing account is
  admission-only (§2), and so is its fallback: the invite is consumed, no
  friendship is created, and the screen says *"Vadim invited you to
  «Request», but it has already closed."* Only signups get the connection
  (the owner's decision was about joining); otherwise a Request closing would
  upgrade admission into mutual trust.
- **D16 Phantom look.** Violet accent token + ghost badge fixed now; exact
  stroke chosen in the first M1 UI bead (material-3 skill, screenshots for
  owner review). **Phantom nodes render semi-transparent when not selected**,
  full opacity when selected/hovered.
- **D17 Email only.** Contact matching and contact points handle email only.
  Phones from imports are kept (if the owner opts in) as plain private text,
  never hashed or matched, until phone auth exists.
- **D18 Export deferred to #780.** Repositories expose owner-scoped readers;
  the export UI ships with #780.
- **D19 Owner surfaces:** Field map + list, a "Not on Tentura yet" section on
  the People screen (with invite status), people-tag member views (tag
  manager, Field tag view), the forward picker (M3), and People → Invites →
  Pending (phantom invites listed there too, labelled with the phantom's name,
  never expiring).
- **D20 Ties never become trust.** A tie exists only while at least one end
  is an *active* phantom. When a merge makes both ends real, the tie is
  **deleted** and is not restored by unmerge. A third party can never tie two
  real people; a tie can't be created between two real people.
  Supersedes the 2026-10-25 "suggested edges … become real trust when
  confirmed" and the B4 ties section.
- **D21 "Remove me from everyone's maps":** rejects all pending "Is this
  you?" proposals about me and takes me out of every shared cluster; owners
  keep their private pin/tags/note on me. Each affected phantom gets a mark
  visible only to its owner: *"Someone asked to remove it."*
- **D22 "Ask Vadim to remove this placeholder" shows who asked:** the owner
  gets a card "Ivan asked you to remove «Anna K.» from your map";
  rate-limited.
- **D23 Unmerge withdraws the owner's trust.** Undo/Unlink of an
  invite-origin merge always removes `vote_user(owner → U)` and re-projects
  the pair, even if that edge existed before the merge. `U`'s edge to the
  owner stays — it is `U`'s own outflow. Delivered Request forwards stay.
- **D24 Others' phantoms get a separate small budget on my Field.**
  `kConstellationForeignPhantomCap` (start at 50), outside the 400-peer cap.
  My own phantoms stay reserved + counted in the peer budget (D5).
- **D25 Phase 2 manual link: owner-side now, shared after confirm.**
- **D26 Non-user deletion = privacy email address.** The landing shows a
  privacy contact address; the operator handles requests by hand with a
  documented runbook and a Dart admin command (find phantoms by email HMAC or
  by name + owner; delete; log the erasure). No public form, no queue.
- **D27 GDPR checked by the owner — no gate.** Fine as long as the data stays
  semi-closed: nothing public, reach limited by MeritRank and personal trust,
  a shared phantom carries only a name (plus ties). Shared projections never
  grow beyond name + ties + attribution (D10); any change that does, or that
  makes phantoms reachable outside the MR/trust neighbourhood, reopens it.

Technical choices:

- **P1 Additive reads.** Outside the D12 exceptions no existing query learns
  to *exclude* phantoms; new reads *add* them.
- **P2 One live invite per phantom**, non-expiring, rotated by "New link"
  (§4).
- **P3 Merge keeps the phantom row and its private rows**, plus a
  `phantom_merge` record; Undo and Unlink are the same "unmerge" (§5).
- **P4 Request delivery is post-commit**, revalidated, and never blocks
  joining (§7).
- **P5 Id prefix `PH`** (`generateId('PH')` → **14 chars**). Every GraphQL
  input that may carry a phantom id uses a target-aware string input (like
  `MutationPeopleTags`' `InputFieldString`), never `InputFieldId` (exactly 13).

---

## 2. What exists today (relevant facts)

- **Invitations** (`m0193.dart:5580`): `id 'I'+12`, `user_id`, `invited_id`,
  `beacon_id`, `addressee_name ≤128`, `parent_forward_edge_id`,
  `invite_origin`, `accepted_at`. Expiry = `created_at + INVITATION_TTL`
  (7 d): `InvitationEntity.isExpired` (`invitation_entity.dart:32`, used by
  preview and `acceptAsExisting`) and raw checks at
  `user_repository.dart:232,412,939`. No renew endpoint. Hasura: role `user`
  selects own rows through a column allowlist (`hasura/metadata.json:707`);
  the client lists invites via Hasura with a `created_at_gt` filter.
  `invitationById` (`query_invitation.dart:49`) returns `asMapWithIssuer`
  — **including `addressee_name` — to any authenticated code holder.**
- **Accept paths**:
  - signup `createInvited` / `createInvitedWithCredential`
    (`user_repository.dart:217,394`): claim invite, mutual `vote_user`, trust
    projection, `_upsertInviteContact` (overwrites the issuer's contact name),
    and for Request invites `_materializeBeaconInviteForward`;
  - existing account: `InvitationCase.acceptAsExisting` (`:349`; preview
    returns `alreadyFriends` for mutual friends and the client then stops,
    `accept_invite_cubit.dart:145`) and the separate GraphQL
    `invitationAccept` → `InvitationCase.accept` (`:311`, no `isExpired`
    check, still wired in the client `invitation_repository.dart:205`). Both
    reach `bindMutual` (`user_repository.dart:926`). A Request invite accepted
    by an existing account is *admission only*: `_acceptBeaconInviteOnly`
    passes `bindFriendship: false, emitInviteAccepted: false`
    (`invitation_case.dart:451–475`).
  - **Defect A:** lock order differs — signup claims the invitation, projects
    trust (`trust_pair_lock`s), then locks the parent forward chain
    (`user_repository.dart:289–312`); `bindMutual` locks the chain, claims,
    locks the chain again, then projects trust (`:945–996`).
  - **Defect D:** `invitationAccept` → `InvitationCase.accept` binds
    friendship even for Request invites (`invitation_case.dart:336–345`),
    unlike `acceptAsExisting`'s admission-only path.
  - All accept paths run in `withMutatingUser` (READ COMMITTED, no retry,
    `tentura_db.dart:388`). `lockConstellationViewerBatch` throws
    `PostgresSnapshotUnavailableException` whenever it had to wait
    (`constellation_viewer_tx.dart:10–30`); only `withMutatingRepeatableRead`
    retries that, and it refuses to nest.
  - **Defect B:** `acceptAsExisting` on already-mutual friends with a
    non-Request invite returns `true` without consuming the invite.
  - **Defect C (several gates):** `_requireInviteIssuerMayForward`
    (`:153`) throws on a closed/expired Request or lost forward right;
    `_materializeBeaconInviteForward` → `_lockActiveInviteParentChain`
    (`:115,196`) throws on a cancelled ancestor *after* the user row is
    created; `bindMutual` returns `false` before claiming on a broken chain
    (`:945`); `_acceptBeaconInviteOnly` throws on unreadable /
    non-forwardable Requests.
- **Private per-viewer data**: `user_contact(viewer, subject, contact_name)`
  (names 3–32 chars, `kTitleMinLength`/`kTitleMaxLength`,
  `user_contacts.dart:17–21`, `ContactCase.normalizeName`); people tags
  (`m0261`, V2-only, owner-scoped SQL, realtime trigger
  `notify_person_tag_change` m0262). Tag mutations take the
  `person_tags:<owner>` advisory lock first (`people_tags_repository.dart:573–600`);
  restore re-inserts members as new rows (`:250–266`); `_counts` derives
  `off_field_count` from visible peers and person anchors (`:623–685`).
- **Forwards**: `ForwardCase.forward` runs in `_attention.runAction(actor =
  sender)` and around `createBatch` upserts the sender's watching, records
  attribution and `relayReceived` (`forward_case.dart:332–422`); `createBatch`
  silently skips a recipient who already has an active edge or is paused
  (`forward_edge_repository.dart:148–178`).
- **Landing**: `packages/landing/main.js` carries only the code across the
  open-in-app, recovery and Google sign-in transitions (`:142–153,232–255`).
- **Field**: V2 `constellationField` → `ConstellationFieldSnapshotReader`
  (snapshot read first; `person_field_first_seen` rows written afterwards,
  with `-infinity` on the viewer's first backfill read, where "first" means
  the viewer has no first-seen rows yet,
  `constellation_field_repository.dart:124–152`,
  `constellation_field_snapshot_reader.dart:758–769`). Caps
  `kConstellationPeerCap = 400`, reserved set outside the cap.
- **Pins**: `constellation_anchor` (kinds PERSON/BEACON; typed FK columns;
  tombstones; unique `(viewer, target_kind, target_id)` incl. tombstones,
  `m0236.dart:62`). Mutations take `lockConstellationViewerBatch` →
  `lockConstellationViewerCursor` inside `withMutatingRepeatableRead`, which
  refuses to nest (`tentura_db.dart:421`). The BEFORE trigger
  `bump_constellation_anchor_revision` derives identity only from
  `person_id`/`beacon_id`, and on UPDATE tombstones any row with
  `num_nonnulls(person_id, beacon_id) = 0` (`m0236.dart:84–98`);
  `constellation_anchor_apply_ops` treats every non-PERSON target as BEACON
  (`:158–185`). Conditional writes compare per-target watermarks
  (`constellation_anchor_repository.dart:135,382`). Layout snapshots store
  anchors as jsonb; restore does not dedupe targets
  (`constellation_layout_snapshot_repository.dart:324–367`). Dart/GraphQL
  target kinds are closed over PERSON/BEACON
  (`lib/domain/constellation/constellation_anchor.dart:6`,
  `custom_types.dart:1112`; snapshot decode `values.byName`). Tombstones arise
  only from target deletion (FK SET NULL). `applyBatch` retries FK violations
  only for the person/beacon fkeys (`constellation_anchor_repository.dart:170–180`);
  `shownAnchors` checks every non-person target against beacons
  (`constellation_anchor_projection_reader.dart:368–374`).
- **Client Field**: `NodeDetails` sealed (`FieldPersonNode`,
  `FieldBeaconNode`, `FieldDraftNode`). Canvas long-press/secondary tap opens
  the create menu (`constellation_create_entry.dart`); app-bar "+" menu typed
  by `BeaconKind`. **Dashed outline already means "temporary person".**
  `ConstellationFieldStoreCase` refreshes on `constellationAnchor` and, lazily
  (non-urgent, 5 min), on `constellationField`; its anchors refresh fetches
  anchors only (`constellation_field_store_case.dart:91–105,221–238,590–605`).
- **Images**: objects under `images/<authorId>/<id>.jpg`; the storage adapter
  attaches `x-amz-acl: public-read` to every upload by default
  (`remote_storage.dart:37`, `env.dart:1077`), room attachments included.
  `ImageObjectGcRepository` is keyed by image UUID and rebuilds
  `images/…` keys (`image_object_gc_repository.dart:26`).
- **Complaints**: server `complaintCreate` takes `InputFieldId` (13 chars,
  `mutation_complaint.dart:20`); client `ComplaintCase.fetchReportedItem`
  branches on `startsWith('U')`
  (`packages/client/lib/features/complaint/domain/use_case/complaint_case.dart:31`).
- **Visibility**: `person_visible_peer_ids_tx(v, ctx)` (m0235) — memoized,
  epoch-stamped, fails closed. Same shape as `beacon_readable_ids` (m0242).
- **Not existing**: self-service data export (#780), About page, contacts
  plugin / vCard parsing, any per-person note or private avatar.

---

## 3. Data model (Phase 1)

All new tables: **not tracked in Hasura**; read/written by V2 resolvers with
`WHERE owner_id = $viewer`.

**Delete actions** — every FK states one, so deletes and account erasure never
stall on `NO ACTION` or violate a check:

| FK | On delete |
|---|---|
| every `owner_id` / `author_id` / `sender_id` → `user` | CASCADE |
| `phantom.merged_user_id` → `user` | SET NULL (→ orphaned) |
| `phantom.current_merge_id` → `phantom_merge` | SET NULL |
| `phantom_merge.phantom_id` → `phantom`; `phantom_merge.user_id` → `user` | CASCADE (an erased `U` takes the undo record along; the phantom is orphaned and can't be unmerged anyway) |
| `person_note` / `person_private_avatar` subject (user or phantom) | CASCADE (SET NULL would break exactly-one) |
| `phantom_tag_member`, `phantom_contact_point`, `invitation.phantom_id`, `constellation_anchor.phantom_id` → `phantom` | CASCADE |
| `phantom_pending_forward.phantom_id` / `.beacon_id` | CASCADE |
| `phantom_pending_forward.merge_id` / `.recipient_id` / `.forward_edge_id` | SET NULL |
| `phantom_tie` ends (user or phantom) | CASCADE |
| `phantom_tag_member (tag_id, owner_id)` → `person_tag` | CASCADE |
| `phantom.cluster_id` → `phantom_cluster` | SET NULL |
| `phantom_cluster_link` ends → `phantom` | CASCADE |
| `person_field_first_seen_init.viewer_id`, `phantom_link_hint_dismissal` (phantom, user), `contact_check_usage.user_id` | CASCADE |

pg test: erasing a merged `U` leaves the phantom orphaned with
`merged_user_id` and `current_merge_id` both NULL.

### 3.1 `phantom`

| column | notes |
|---|---|
| `id text PK` | `PH` + 12 hex (14 chars, P5) |
| `owner_id` | FK user CASCADE |
| `display_name text` | 3–32 after trim — the contact-name contract it is mirrored into (§4) |
| `emoji text NULL` | ≤ 8 (A2 "Photo / emoji") |
| `created_at`, `updated_at` | |
| `merged_user_id text NULL` | FK user **ON DELETE SET NULL** |
| `merged_at timestamptz NULL`, `merge_origin smallint NULL` | 1 invite-new, 2 invite-existing, 3 manual link, 4 cluster (M8) |
| `current_merge_id text NULL` | → `phantom_merge.id` of the live merge (SET NULL) |
| `revision bigint` | realtime / optimistic concurrency |

- States: **active** (`merged_at IS NULL`), **merged** (`merged_at` and
  `merged_user_id` set), **orphaned** (`merged_at` set, `merged_user_id` and
  `current_merge_id` NULL — hidden everywhere, unmerge refused, snapshot
  restore drops it).
- **Cap (D4):** every activation path (create, batch create, unmerge) takes
  the owner lock `phantoms:<owner>` (advisory xact lock) and checks
  `count(active) < 200`; unmerge over the cap fails with
  `phantom_cap_reached` (UI: "Remove someone not on Tentura yet first").

### 3.2 Tag membership

- New table `phantom_tag_member(tag_id, owner_id, phantom_id, source,
  added_at, membership_id uuid DEFAULT gen_random_uuid())`, PK
  `(tag_id, phantom_id)`, composite FK `(tag_id, owner_id) → person_tag`, FK
  phantom CASCADE, `source` with the same domain as `person_tag_member.source`
  (0–4; phantoms only ever get manual sources).
- `person_tag_member` gains `membership_id uuid NOT NULL DEFAULT
  gen_random_uuid()` — a re-added pair gets a new id, which lets unmerge tell
  a merge-created membership from a later deliberate one (§5.3).
- **The people-tags repository learns mixed members** (D12 exception), all
  under the existing `person_tags:<owner>` lock. **Lock rule:** a statement
  that inserts `phantom_tag_member` rows (apply, restore) first locks the
  referenced phantom rows `FOR SHARE` in id order, *before*
  `person_tags:<owner>` (§5.2 steps 6 → 9), and re-checks their state
  (apply: active; restore: not orphaned);
  otherwise the FK's implicit KEY SHARE on the phantom would come after the
  tag lock and deadlock with merge. `applyMembers` / `restore` open
  `withMutatingUser(owner)` themselves, lock the phantoms, then call
  `_idempotent`, which joins that transaction (same-actor re-entry,
  `tentura_db.dart:392–400`), so its advisory lock follows the phantom
  locks.
  - `applyMembers` accepts `PH` ids: validated against `phantom` (owner =
    caller, active) instead of `"user"`, written to `phantom_tag_member`;
  - `memberships`, member counts and the 1000-per-tag limit read/count both
    tables, **phantom rows only while the phantom is active**
    (`merged_at IS NULL`; a merged phantom keeps its rows,
    hidden, §5.2). Phantom members never count toward `off_field_count` (own
    active phantoms are always on the owner's Field, D5), and a tag with no
    person members skips `person_visible_peer_ids_tx`;
  - tag delete snapshot and its restore carry `{kind, id, membership_id}`;
    the snapshot captures every phantom row, merged ones included; restore
    re-inserts each row **with its old `membership_id`** (so §5.3 still
    recognises merge-created rows), re-inserts merged phantoms' rows too
    (hidden while merged, back after unmerge), and skips only deleted and
    orphaned phantoms;
  - `notify_person_tag_change` is attached to `phantom_tag_member` too.
- Automatic tags (`autoTagKinds`) never apply to phantoms.

### 3.3 Pins — `constellation_anchor` gains PHANTOM

Database (one migration):
- column `phantom_id text NULL → phantom ON DELETE CASCADE`; the exactly-one
  check becomes `num_nonnulls(person_id, beacon_id, phantom_id) = 1` for live
  rows;
- `bump_constellation_anchor_revision` rewritten: identity derived from all
  three columns on INSERT; the tombstone branch tests
  `num_nonnulls(person_id, beacon_id, phantom_id) = 0` (otherwise every
  PHANTOM update would tombstone itself);
- `constellation_anchor_apply_ops` gets an explicit PHANTOM branch for update
  and insert (today every non-PERSON op is treated as BEACON).

Tombstones exist only after target deletion (FK SET NULL), so a live `U`
never has a tombstone pin; PHANTOM anchors are deleted with their phantom
(CASCADE), never tombstoned.

Application (shared + server + client):
- `ConstellationAnchorTargetKind.phantom`, a sealed phantom target, wire
  parsing, the GraphQL enum, `_existingUpsertTargets` / `_storedAnchors`,
  `ConstellationAnchorProjectionReader`, snapshot capture/list/decode/restore
  and client adapters — with round-trip tests for PHANTOM *and* the existing
  kinds;
- upsert validation for PHANTOM joins `phantom` (owner = viewer, active);
- `applyBatch`'s FK-retry filter adds `constellation_anchor_phantom_id_fkey`
  (a concurrent phantom delete retries instead of surfacing `23503`);
- `ConstellationAnchorProjectionReader.shownAnchors` gets a phantom branch
  (owner = viewer, active) instead of falling into the beacon check;
- client `ConstellationFieldStoreCase.settle` / `_runAnchorsRefresh` handle
  PHANTOM targets, and the anchors refresh returns PHANTOM anchors.

Layout snapshots are not rewritten on merge. **Restore resolves then dedupes:**
`PHANTOM:h` → `PHANTOM:h` (active), `PERSON:U` (merged), dropped (orphaned or
deleted); if two entries resolve to the same target, the one that came from a
phantom wins (D13); deduplication happens before any write.

### 3.4 Notes and private avatars (any person) — M2

- `person_note(owner_id, subject_user_id NULL, subject_phantom_id NULL,
  body text, updated_at, revision)`; exactly-one subject; unique per
  `(owner, subject)`; `owner ≠ subject_user_id`. **Length:** 4000 chars, API
  and DB check alike; merge never copies note text (§5.2 step 5), so no row
  grows past it.
- **Search (M2):** owner-scoped V2 query `personNoteSearch(q)` → subject ids
  (user or phantom) whose note matches (`ILIKE`, `owner_id = viewer`, ≤ 50);
  the client intersects them with the loaded Field population and lists them
  in the Field name search. No other surface reads notes.
- `person_private_avatar(owner_id, subject_user_id NULL, subject_phantom_id
  NULL, object_key, blurhash, width, height, created_at)`; same uniqueness.
  Several rows may reference one `object_key` (merge copies, §5.2).
- **Storage:** prefix `private/<ownerId>/<uuid>.jpg`, uploaded with an
  explicit **private ACL** (the adapter's default public-read metadata is
  overridden), served only by an authenticated controller that checks
  `owner_id = viewer`. Test: anonymous direct GET of a private object → 403.
  Counts against `UPLOAD_DAILY_CAP_MB`; `kMaxImageUploadBytes` applies.
- **GC:** queue `private_object_gc(object_key PK, enqueued_at, attempts,
  lease_owner, lease_until, next_attempt_at, last_error)` with `ImageObjectGcRepository`'s lease/retry
  semantics; enqueue is `ON CONFLICT DO NOTHING`. A row trigger
  `BEFORE DELETE OR UPDATE OF object_key` on `person_private_avatar` enqueues
  `OLD.object_key`, so every path — replacement (delete + insert or upsert),
  phantom deletion, owner erasure, subject erasure, FK cascades — is covered.
  Upload follows `ImageRepository.put`: row first, object second, row deleted
  on upload failure (which enqueues the key). The worker deletes the object
  only when no `person_private_avatar` row references the key any more.

### 3.5 Phantom contact points — M4/M5

`phantom_contact_point(phantom_id, kind email|phone, value text NULL,
match_hmac bytea NULL, hmac_key_version smallint NULL)`. `value` is stored
only if the owner chose to keep it (import default OFF); `match_hmac` is
computed for every email (D17) at write time, from M4 on (the key ring lands
with M4, §9). Owner-private, CASCADE with phantom. Index on `match_hmac`.
Key versions: §9.

---

## 4. Invites (Phase 1)

- **Schema:** `invitation.phantom_id text NULL → phantom ON DELETE CASCADE`,
  unique partial index `WHERE invited_id IS NULL` (one live token per
  phantom). Carried through the Drift table, `InvitationMapper` and
  `InvitationEntity.phantomId`.
- **One expiry rule:** `InvitationEntity.isExpired` returns `false` when
  `phantomId != null`; the raw checks in `user_repository.dart` use the same
  rule. Test matrix: an 8-day-old phantom invite and an 8-day-old ordinary
  invite through anonymous preview, `invitationById`, both signup methods,
  `acceptAsExisting` and `invitationAccept`.
- **Privacy of `invitationById`:** `addressee_name` and `phantom_id` are
  returned only when the caller is the issuer; everyone else gets the
  invitee-safe projection. In the §11 privacy suite.
- **Hasura list:** add `phantom_id` to the role-`user` select allowlist on
  `invitation` (owner filter unchanged; phantom tables stay untracked). The
  client fragment reads it and the pending predicate becomes
  `_or: [{created_at: {_gt: $cutoff}}, {phantom_id: {_is_null: false}}]` for
  both the list and the aggregate.
- **Name mirror:** `addressee_name` = `phantom.display_name`. Renaming goes
  only through `phantomUpdate`, which locks the live invitation row
  (`FOR UPDATE … WHERE phantom_id = h AND invited_id IS NULL`), then the
  phantom row — the §5.2 order — and updates both; `invitationUpdate`
  rejects phantom invites. Names follow the contact-name contract (3–32,
  §3.1), so the mirror into `user_contact` always validates.
  So the existing `_upsertInviteContact` makes the phantom's name the owner's
  private contact name for the joined account (answers #781 Q2).
- **Minting:** a phantom has no invite until the owner takes one: Copy
  invite link / Share… (A2, A3) call `phantomInviteEnsure`, which returns the
  live invite or creates it, under the phantom `FOR UPDATE` (§5.2), so two
  concurrent calls return the same invite. "Save without inviting", batch create and import
  mint nothing, so People → Invites → Pending lists only invites the owner
  actually took; `inviteState` is `none` until then.
- **"New link"** (A3 "Renew") — active phantoms only: delete the unaccepted
  row, insert a new one. Old links then say "invalid".
- **Remove phantom** deletes the live invite (CASCADE). **Manual link**
  deletes it too (§5.2). A merged phantom has no live invite; unmerge never
  revives an old token — the owner mints one with "New link".
- **Invites tab (D19):** phantom invites listed in Pending with the
  phantom's name and no expiry caption; tapping opens the phantom panel.
  Delete there = remove the invite only (the phantom stays).
- **Link:** `/invite/<code>`; with a Request context `/invite/<code>?r=<beaconId>`
  — `r` only feeds the preview (§7). `InvitePreviewController` reads `r` and
  passes it to `InvitationCase.preview`; the landing carries `r` across the
  open-in-app, recovery and Google sign-in transitions exactly like the code,
  and the app route carries it too (`/accept-invite/<code>?r=…`,
  `AcceptInviteScreen` query param → `AcceptInviteCubit`).
- **Share UI:** A2/A3 "Copy invite link" + "Share…" with a prefilled personal
  line ("Hi Anna, I put you on my map in Tentura — join so we can ask each
  other for a hand."). Extend `ShareCodeDialog` / `SharePlus` with `text`.
- **Preview** (`InvitationCase.preview`, landing) exposes nothing about the
  phantom (no name, tags, note, emoji); inviter as today.
- **Already friends:** for a phantom invite the preview never returns the
  terminal `alreadyFriends`; it returns `existingUser` with
  `phantomInvite: true`, and the client calls accept (merge) and shows
  "You're on Vadim's map". Touchpoints: `InvitePreviewResult.phantomInvite`
  (server `toJson`), client `InvitePreview.phantomInvite`, and
  `AcceptInviteCubit` routing `existingUser + phantomInvite` to accept and
  that confirmation. The client path is covered end to end.

---

## 5. Merge, Undo, Unlink (Phase 1)

### 5.1 Triggers

| Trigger | Origin | Trust effect | Pending forwards (§7) |
|---|---|---|---|
| Signup through the phantom's invite | invite-new | mutual `vote_user` (existing `createInvited*`) | delivered |
| Existing account accepts the phantom's invite (`acceptAsExisting` or `invitationAccept`) | invite-existing | `bindMutual(bindFriendship: true)`; **Defect B fixed**: phantom invites always consume + merge, even if already mutual | delivered |
| Owner "This is someone already on Tentura…" → picks a person the owner sees on the Field | manual link | **none** | **not delivered**; offered to the owner as ordinary forwards |
| Same-name hint "Link them" (A4) | manual link | none | as manual link |

### 5.2 Merge transaction (`PhantomMergeRepository.merge`)

Runs inside the accept transaction (invite origins) or its own (manual link),
through **tx-scoped repository methods** (`…InTx`) — never the public anchor /
tag methods, which open their own `withMutatingRepeatableRead`.

**Global lock order** — every path that touches these resources acquires
them in this order, skipping what it doesn't need. A path may skip a step
only if nothing it runs takes that lock *implicitly* (FK checks, cascades,
triggers); where something does, the path takes the lock explicitly at its
position first.

0. pair lock `user_pair:<min(a,b)>:<max(a,b)>` (advisory xact) on
   (owner, `U`): merges into an existing `U`, unmerge, and block / unblock
   of that pair (so the block guard can't race a block);
1. Post lock (`PostLockRepository`; Request invites, forwards, delivery);
2. invitation rows: the claim (`UPDATE … WHERE invited_id IS NULL`) or
   `FOR UPDATE … WHERE phantom_id = h` (rename, New link, delete, manual
   link); a cluster merge locks the claimed invite and every other member's
   live invite here, in id order;
3. parent forward chain `FOR UPDATE` (Request invites, forwards, delivery);
4. cluster row `FOR UPDATE` (M8, clustered phantoms only);
5. per owner, in owner-id order: viewer batch lock → viewer cursor
   (upserting a missing row) → `phantoms:<owner>` advisory lock;
6. phantom rows in id order — `FOR UPDATE` to change one or its invite
   (merge, unmerge, delete, rename, New link, `phantomInviteEnsure`),
   `FOR SHARE` to rely on one (tag inserts, tie creation, forward recording,
   delivery); state is re-checked after the lock;
7. `phantom_pending_forward` rows of those phantoms, then `phantom_tie` rows
   (M6+);
8. anchor rows (and their target watermarks);
9. `person_tags:<owner>` advisory lock → tag memberships;
10. `trust_pair_lock`s (sorted, as `_applyReciprocalTrustEdges` does).
    Unmerge's trust removal takes `trust_pair_lock(o, U)` *before* deleting
    `vote_user`, whose statement trigger bumps the global
    `visibility_trust_generation` row (m0235), as every `trust_project_pair`
    caller does.

**Accept bodies follow it.** M0 restructures them: signup (`createInvited`,
`createInvitedWithCredential`) = Post lock → create user → claim → chain lock
and D15 decision → trust projection → contact; `bindMutual` = claim → chain
lock (its pre-claim chain lock becomes a plain read) → trust. M1 hooks merge
(steps 4–9) in between the chain lock and trust projection. This fixes
Defect A. For a phantom invite the merge owns the contact write (step 7): it
records U's prior contact name and writes `addressee_name` itself, and the
body skips its own `_upsertInviteContact` (today signup writes it after
trust, `user_repository.dart:288–300`, and `bindMutual` right after the
claim, `:967–971`). The data-layer bodies return the merged phantom id; the
case layers (`auth_case`, `credential_auth_case`, `invitation_case`), which
hold the `AttentionTransaction`, record `phantomMerged` and schedule
post-commit delivery (§7).

**Batch lock inside accept.** Accept transactions are READ COMMITTED and not
retried, so the try-lock-then-throw `lockConstellationViewerBatch` must not
run there. Merge in an accept uses a waiting variant,
`lockConstellationViewerBatchWait` (`pg_advisory_xact_lock`, never throws) —
safe under READ COMMITTED, where every later statement sees what the
previous holder committed. RR paths (anchor batches, phantom CRUD) keep the
try-lock as their first statement and retry through
`withMutatingRepeatableRead`. **Every merge-family path — invite merge,
manual link, unmerge — runs READ COMMITTED with the waiting variant:** one
code path, fresh reads after each lock (so the step-1 guards see concurrent
commits), and no 40001 from the global `visibility_trust_generation` row
that unmerge's trust removal bumps. An owner moving pins on another device
can delay a signup, never abort it.

| Path | Steps |
|---|---|
| plain anchor batch | 5 → 8 |
| tag apply / restore with phantom members | 6 (`FOR SHARE`) → 9 |
| phantom create / batch create | 5 (cap) → 8 (pin) → 9 (tags) |
| rename | 2 → 6 |
| New link / `phantomInviteEnsure` | 2 → 6 (`FOR UPDATE`; re-check the live invite, then insert) |
| phantom delete | 2 → 5 → 6 → 7 → delete (cascades anchors, tag rows, invite) |
| invite merge | (0, existing account) → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 |
| manual link | 0 → 2 (h's live invite) → 5 → 6 → 7 → 8 → 9 |
| unmerge | 0 → 5 → 6 → 7 → 8 → 9 → 10 (trust removal) |
| block / unblock | 0 → existing body |
| tie creation (M6) | 6 (`FOR SHARE`, ends re-checked active) → 7 |
| pending-forward recording | 1 → 3 → 6 (`FOR SHARE`) → 7 |
| delivery (§7) | 1 → 3 → 6 (`FOR SHARE`) → 7 → forward edge |
| erasure of account `U` | `U`'s live invitations (2) → cursors of `U` and of every viewer with an anchor on `U`, viewer-id order (5) → `U`'s own phantoms and phantoms merged into `U`, id order (6) → delete; READ COMMITTED, cursor row locks only (no batch advisory lock) |

The erasure pre-lock covers the final `DELETE` of the user, which locks
anchors through FK SET NULL and then the cursor through the trigger
(`m0236.dart:55–59,86–95`) — the inverse of anchor batches' cursor → anchor.
Earlier erasure chunks only scrub published Requests (UPDATE) and delete
`U`'s drafts (`user_erasure_repository.dart:51–69,131–150`), whose anchors
can only be `U`'s own (drafts are author-only).

**M1 ships pg deadlock tests** for merge × anchor batch (same owner), merge ×
tag apply naming the phantom, merge × phantom delete, rename × accept,
delivery × unmerge, erasure of `U` × merge into `U`, manual link × New
link, block × manual link, tie creation × merge (M6), unmerge × concurrent
vote writes (no 40001), and signup × existing-account accept of the same
Request invite; plus a contention test
in which the owner holds the batch lock while the invitee signs up (the
signup waits, then succeeds).

Steps for owner `o`, phantom `h`, user `U`:

1. **Guards:** `h` active; `U ≠ o`; `NOT block_hides(o, U)` — evaluated
   after the locks (READ COMMITTED + pair lock), so a concurrently committed
   block is seen.
2. **Record** `phantom_merge(id, phantom_id, owner_id, user_id, origin,
   created_at, undo jsonb, undone_at)`; `undo` gets everything below.
3. **Pin** (case table; `h` anchors are never tombstoned and a live `U` has
   no tombstone pin, §3.3 — the merge asserts both):

   | `h` anchor | U anchor | Action | `undo` records |
   |---|---|---|---|
   | none | any | keep U as is | nothing |
   | live | none | delete `PHANTOM:h`, insert `PERSON:U` at h's position | h position; "U had none" |
   | live | live | set U's position to h's, delete `PHANTOM:h` | h position; U's prior position |

   Inserts/updates set `target_kind`/`target_id` explicitly. Bump the target
   watermarks of **both** `PHANTOM:h` and `PERSON:U` (stale pre-merge
   conditional writes then fail), and record U's watermark after the merge.
4. **Tags:** for each `phantom_tag_member(T, h)`: insert `(T, U)` into
   `person_tag_member` unless it exists (skip if `block_hides`); record in
   `undo` the *full* original phantom membership list and the
   `membership_id` of every row the merge inserted. Phantom memberships are
   **kept** on `h`, hidden by the active-only reads (§3.2).
5. **Note:** nothing is copied. `h`'s note row stays on `h`; U's panel shows
   `o`'s note on U followed by the notes of `o`'s phantoms merged into U
   (merge order), each under `— «<h name>»`, and each section edits its own
   row (4000 chars each, §3.4). Chained merges therefore never overflow, and
   unmerge needs no note bookkeeping.
6. **Avatar:** `h`'s avatar row stays on `h`. If U has no private avatar from
   `o`, insert a row for U referencing the same `object_key` (record it);
   otherwise U's wins (D13).
7. **Contact name:** record U's prior contact name/absence, then write:
   invite origins write `addressee_name` (the accept body skips its own
   upsert, above); manual link upserts only if `o` has none. Record the
   value written.
8. **Invite:** invite origins: the claimed invite is the phantom's; manual
   link: delete `h`'s live invite (locked at step 2).
9. **Ties (M6+):** delete ties whose ends would both be real (§10.1).
10. Set `merged_user_id, merged_at, merge_origin, current_merge_id`; bump
    revisions (the phantom update fires the owner-only realtime event,
    §6.1); emit attention event `phantomMerged` to `o` only.

### 5.3 Undo / Unlink = unmerge

Owner-only; refused for orphaned phantoms; subject to the cap (D4). Inside
one transaction with the §5.2 lock order:

- **Tags:** delete U's memberships whose `membership_id` matches one recorded
  as merge-inserted (a later removal + re-add has a new id and stays);
  `h`'s own memberships were never removed (tags deleted since simply drop
  out via CASCADE).
- **Pin:** if U's target watermark still equals the recorded post-merge
  value, restore U's prior state (none / position) and re-create
  `PHANTOM:h` at the recorded position; otherwise leave U's pin and give `h`
  no pin. Bump both watermarks.
- **Contact name:** restore U's prior value only if the current value equals
  what the merge wrote. Notes need nothing (§5.2 step 5).
- **Avatar:** delete the U row the merge inserted, if still present (the
  object survives — `h` still references it).
- **Trust (D23):** invite origins: take `trust_pair_lock(o, U)`, remove `vote_user(o → U)` and re-project
  the pair (`trust_project_pair`), regardless of whether the edge predated
  the merge. `U → o` stays. Delivered forwards stay.
- **Pending forwards:** claimed-but-undelivered rows for this merge go back
  to `pending` (§7).
- Clear `merged_*`, set `phantom_merge.undone_at`. The phantom has no invite
  until "New link".

Snackbar UNDO (A4) calls it immediately; "Unlink" in the merged person's panel
calls it later (covers "invite link forwarded and someone else accepted it").

### 5.4 Same-name hint (A4)

- Candidate pairs: active phantom `h`, person `p` in the owner's Field
  population, `first_token(casefold(h.display_name)) =
  first_token(casefold(p.display_name or o's contact name for p))`, both ≥ 2
  chars, no row in `phantom_link_hint_dismissal(phantom_id, user_id)`.
- "Newly seen" = `p`'s `first_seen_at > h.created_at`, where a peer not yet
  recorded (first sighting in this very read) counts as seen *now*.
- **First-seen initialization:** "first backfill" is decided by a per-viewer
  marker `person_field_first_seen_init(viewer_id PK, at)`, not by "the viewer
  has no first-seen rows" — a viewer with 0 peers would otherwise backfill
  (and stamp `-infinity` on) the first person seen after their first
  phantom. The first backfill read writes the marker; phantom creation runs
  the backfill first (same transaction) when the marker is absent; the
  migration inserts it for every viewer that already has rows. So
  `-infinity` only ever marks people seen before the first phantom existed.
  Implementation: a tx-scoped SQL helper `firstSeenInitInTx` inserts the
  marker and `person_visible_peer_ids_tx(owner, '')` at `-infinity`
  (`ON CONFLICT DO NOTHING`); `phantomCreate` and `phantomCreateBatch` call
  it inside their transaction (the snapshot read and `withMutatingSystem`
  can't nest there). The Field read's post-snapshot write runs whenever the
  marker is absent, even with no unseen peers, and writes marker + rows in
  one transaction; the reader's backfill test reads the marker.
- "Not her" writes the dismissal (D14).

---

## 6. Field and client (Phase 1)

### 6.1 Server

- `ConstellationFieldSnapshotReader` adds `phantoms: [PhantomRecord]` for
  `owner = viewer` (Phase 1): `id, displayName, emoji, hasPrivateAvatar,
  ownTagIds, pinState, inviteState (none | live), createdAt, linkHint?,
  removalRequested?` (M7).
- **Caps (D5):** own active phantoms join the reserved set and reduce the
  remaining budget: `peerBudget = max(0, 400 − |own active phantoms|)` (D4
  bounds it at 200).
- `constellationFieldHasNoContacts` (#252) stays "no real contacts"; the empty
  banner gains a "+ Person" action.
- **Realtime:** a `notify_phantom_change` trigger on `phantom` (the tag
  trigger already covers `phantom_tag_member`, §3.2) publishes a new
  `RealtimeEntityKind.phantom` to the owner only, shaped like m0262.
  `ConstellationFieldStoreCase` refreshes phantoms and anchors **urgently**
  on it, so merges, unmerges, manual links and People-screen edits reach an
  open Field without waiting for the 5-min lazy `constellationField`
  refresh.

### 6.2 Client (`features/phantoms/`, clean architecture)

- Entity `Phantom`; repository over new V2 ops: `phantomCreate`,
  `phantomUpdate`, `phantomDelete`, `phantomInviteEnsure`,
  `phantomInviteRotate`, `phantomLink`, `phantomUnmerge`,
  `phantomHintDismiss`; reads ride on the Field snapshot.
- `NodeDetails.FieldPhantomNode`, graph id `fh:<id>`; rows in the List view
  (#253) and name search (plus note search from M2, §3.4).
- **Look (D16):** violet phantom accent (new design-system token, light/dark)
  + ghost badge + a stroke distinguishable from the temporary dashed outline,
  semi-transparent unless selected/hovered.
- **Other owner surfaces (D19):** People screen section "Not on Tentura yet"
  (name, tags, invite status, Copy link); phantoms as members in the tag
  manager and Field tag view.
- **Create:** canvas long-press / secondary tap menu gains "Add someone not on
  Tentura yet" (A1) — the menu entry type stops being `BeaconKind` only; the
  app-bar "+" menu gets "+ Person". Sheet A2: name, photo/emoji, tags, note
  (note/photo only after M2), invite text, Copy link / Share…, "Save without
  inviting"; position = the long-press point (creates the PHANTOM anchor).
- **Panel A3:** name, «Not on Tentura yet · invite sent N days ago», tags,
  note, Copy invite link, New link, This is someone already on Tentura…,
  Remove from my map (confirm).
- **Filter chip** «Not here yet · N» in `ConstellationVisibilityBar`.
- **Merge snackbar** on `phantomMerged` (A4) with UNDO.
- **Report (M8):** `ComplaintCase.fetchReportedItem` and `ComplaintScreen`
  (its `startsWith('U')` tab choice, `complaint_screen.dart:112`) get a `PH`
  branch; the phantom lookup port is visibility-scoped (D2) and answers
  not-found for a phantom the reporter can't see.
- Cross-platform: every long-press path has secondary-tap + visible button.

---

## 7. Forwarding a Request to a phantom — M3

- Table `phantom_pending_forward(id, phantom_id, sender_id, beacon_id,
  parent_forward_edge_id NULL, note, created_at, state, merge_id NULL,
  recipient_id NULL, forward_edge_id NULL, lapse_reason NULL,
  resolved_at)`; states
  `pending | claimed | delivered | lapsed | offered`; unique
  `(phantom_id, beacon_id) WHERE state IN ('pending','claimed')`.
  Phase 1: `sender_id = owner`.
- **Recording:** forward sheet "Invite a new person" bar gains **"Pick from my
  placeholders"** (owner-only candidates). Picking runs the ordinary forward
  checks (`ForwardCase` policy, readability, blocks, under the Post lock) and
  records a pending row, keeping the note; then offers Copy/Share of
  `/invite/<phantomCode>?r=<beaconId>`. A2 "Attach a request" does the same.
- **Display:** Request → People tab → Forwards (sender's view only): "Vasya
  (not on Tentura yet)", pending/lapsed. Lapse is computed (Request
  closed/expired, sender lost readability or forward right).
- **Preview with `r`:** the landing passes `r`; `InvitationCase.preview`
  shows the Request excerpt only if the code's invite has a phantom with a
  `pending` row for `beacon_id = r` and the sender may still forward it
  (same gate as `BeaconVisibility.canPreviewInvite`); otherwise `r` is
  ignored. A bare query parameter never grants access.
- **Delivery (P4), invite origins only:**
  1. merge transaction: atomically claim
     `UPDATE … SET state='claimed', merge_id=:m, recipient_id=:U WHERE
     phantom_id=:h AND state='pending'`;
  2. after commit, `PhantomForwardDeliveryCase` handles each claimed row
     through **`ForwardCase.deliverPending`**, a new entry point sharing
     `ForwardCase.forward`'s single-recipient body. It runs its own
     `_attention.runAction(actor = sender)` transaction (post-commit, so no
     nested-actor mismatch), takes the Post lock and chain lock, then the
     phantom `FOR SHARE` and the row `FOR UPDATE` (§5.2), checks the row
     still belongs to the phantom's `current_merge_id`, **re-runs the full
     forward checks** (Request status, sender readability and forward right,
     policy, blocks between sender and U, recipient eligibility, parent chain
     alive) and performs an ordinary forward's side effects (sender
     watching, attribution, `relayReceived`) with the stored note. Outcomes:
     edge inserted → `delivered` + `forward_edge_id`; an active sender → U
     edge already exists → `delivered` + that edge's id; recipient paused or
     any check failed → `lapsed` + `lapse_reason`. Terminal; never throws.
     The already-active edge is unique (`bfe_active_unique`, `m0193.dart:6651`);
     `createBatch`'s result gains the already-active edge ids. The shared
     body's own conditions apply (watching only without an active help
     offer; reason/band inputs are absent for pending forwards);
  3. a retry sweep processes `claimed` rows. One whose merge is gone
     (`merge_id` NULL or ≠ `current_merge_id` — only when `U` erased the
     account, since unmerge resets its rows in its own transaction) becomes
     `lapsed` (`recipient_gone`), freeing the `(phantom_id, beacon_id)` slot.
     Terminal rows are never re-delivered, so a forward the sender later
     cancelled is not resurrected.
  4. lapsed rows produce the joiner card *"Vadim sent you a request; it has
     since closed. You're connected with Vadim."* — the connection clause only
     when the merge created the connection (invite origins do).
- **Manual link:** pending rows become `offered`: the owner sees "Forward
  «Request» to Anna now?" and confirming runs an ordinary forward to U. Never
  delivered automatically; no joiner card.
- **Unmerge:** `claimed` rows of that merge return to `pending`.
- Link opened after merge → "You're already on Tentura, log in"; the app
  then opens `r` through ordinary readability — it works once the forward is
  delivered (the edge grants it) and otherwise lands on the usual not-found.
  No consumed-invite authorization path exists.
- **Joining never fails because of a Request** (D15; M0 does the same for
  plain Request invites).

---

## 8. Selective contact import — M4

- Web-first (the client is web-only): **.vcf (vCard 3/4) and Google Contacts
  CSV** via `file_picker`, parsed on the client by a pure-Dart parser. Contact
  Picker API (Android Chrome) optional later; native address-book plugin and
  Google People API: out of scope.
- Flow: + Person → Import from contacts → searchable checklist, **nothing
  preselected, no "select all"**; rows already on my map (phantom name or
  contact name match, client-side) marked. Options: "Use their photo as my
  private picture" (default ON), "Keep phone/email privately" (default OFF).
- `phantomCreateBatch` (atomic, ≤ remaining cap under `phantoms:<owner>`) →
  phantoms land unpinned, with no invite (§4 Minting), tagged with an own tag
  **"Imported"** (created if absent; the tag magnet clusters them). Photos
  then upload one by one as private avatars.
- Names are trimmed and cut to 32 chars; a row whose name is under 3 chars is
  marked and must be edited in the checklist before import (§3.1).
- Every imported email gets `match_hmac` under the newest key (§9 — the key
  ring lands with M4); the plaintext only if "Keep" is on.
- Only ticked rows leave the device. No invites are sent by import.

---

## 9. "Already on Tentura" check — M5

- **Email only (D17).** Normalization `trim().toLowerCase()` (as
  `email_auth_util.dart`).
- **Key ring (lands with M4, which writes the first hashes):**
  `CONTACT_MATCH_HMAC_KEYS` (versioned). Writes use the newest version. Matching computes the candidate hash under every version still
  referenced by any stored row. `account_verified_contact` keeps plaintext,
  so its hashes are re-keyed by a background job; hash-only phantom rows
  can't be, so their key version stays in the ring until those rows are gone.
  A version is retired only when no row references it; the server refuses
  to start while a stored row references a version missing from the ring
  (checked in `App.run` after migrations).
  `match_hmac` is indexed on both tables.
- `account_verified_contact.match_hmac` + `hmac_key_version` written by both
  writers (`_insertAuthoritativeContacts`, `addVerifiedContacts`) + a one-shot
  Dart backfill.
- Setting **"People who have my email can see I'm on Tentura"**: new
  `user_privacy_setting` row (outside Hasura-readable `user` columns). An
  absent row means ON (`COALESCE(…, true)`), so existing accounts match too;
  when M5 ships, existing users get a one-time card explaining the setting
  with the toggle inline. New users choose explicitly at signup (native
  register screen + landing name step); toggle in Settings → Account.
- `contactCheck(kind, value)` → `{alreadyOnTentura: bool}`; also run on
  phantom contact save/import. Only users with the setting ON match.
  **200 checks/day/account**, counter table `contact_check_usage(user_id,
  day, count)` + log alert on bulk patterns.
- UI: "Already on Tentura — send them an invite yourself." Existing user is
  never notified.

---

## 10. Phase 2

### 10.1 Suggested ties — M6

- `phantom_tie(id, author_id, from_user_id NULL, from_phantom_id NULL,
  to_user_id NULL, to_phantom_id NULL, kind, created_at)`. At creation:
  `from` = author or author's own active phantom (D8); `to` = any person or
  phantom visible to the author; at least one end a phantom (D20). Kinds:
  `know_each_other`, `from_vouches_to`, `to_vouches_from` (B1).
- **Ties keep their phantom ids for life.** Reads resolve a merged phantom
  end to its `merged_user_id`; nothing is re-pointed, so D8 provenance and
  unmerge need no tie bookkeeping. A tie with an orphaned end resolves to
  nothing and every read skips it.
- **Creation lock:** lock the phantom end(s) `FOR SHARE` (§5.2 step 6) and
  re-check they are active before inserting; merge's `FOR UPDATE` serializes
  with it, so no tie appears after a merge made both ends real.
- **On merge (D20):** in the merge transaction, delete every tie for which,
  after this merge, neither end is an active phantom. Not restored by
  unmerge. Cluster merges apply the same rule to all members at once.
- Drawn on the author's Field as dotted "suggested" edges. Private to the
  author in M6, shared in M8. Zero MR effect, ever.

### 10.2 Confirmation flow + joiner review — M7

- **Joiner review (B4)** after signup or on first merge of an existing user:
  "N people already had you on their map" (owners' real names, owners who
  merged a phantom into me), "Is this you?" link proposals with That's me /
  Not me, Continue, "Remove me from everyone's maps" (D21). No ties section
  (D20). Nothing accepted by default.
- **Manual link becomes a proposal** (D25): the owner's private merge happens
  immediately (§5); anything visible to `U` or to others (attribution,
  cluster membership) waits for `U`'s "That's me".
- "Remove me from everyone's maps" (D21): rejects link proposals about me,
  removes me from all clusters' shared view (M8), sets
  `removal_requested_at` on each affected phantom (shown to its owner as
  "Someone asked to remove it"); owners' private data is unaffected.

### 10.3 Shared visibility, clusters, safeguards — M8

- **Read (D2):** others' phantoms enter my Field snapshot when an owner is in
  my visible set (minus blocks and my per-viewer hides). Projection = display
  name (the owner's name for it), attribution ("added by Vadim and 2 others"
  — owners visible to me + count of the rest). Never note, avatar, emoji,
  tags, contact points. Placed near visible owners. **Budget (D24):** at most
  `kConstellationForeignPhantomCap` (50), outside the peer cap, ranked by
  number of visible owners then recency.
- **Shared ties:** a tie is returned only if its author is visible to me
  **and both resolved endpoints are in my permitted node set** (real people
  on my Field, or phantoms visible to me under D2), with blocks and hides
  applied, before projection and dedup-counting — the same rule the Field
  applies to graph edges.
- **B2 actions:** "I know Anna too — add to my map" (creates my own phantom
  with the name + a cluster proposal), "Invite her", "Ask Vadim to remove this
  placeholder" (D22).
- **Clusters (B3):** `phantom_cluster(id)` + `phantom.cluster_id` +
  `phantom_cluster_link(a, b, proposed_by, confirmed_at)`; cluster =
  connected component over confirmed links; link/leave operations lock the
  cluster row. **Cluster merge:** accepting any member's invite runs one
  transaction in the §5.2 lock order (cluster row → owners in id order →
  member phantoms in id order); the accepted member merges with its invite
  origin, every other member with origin 4 (cluster, no trust effect); all
  other members' live invites (locked at step 2 with the claim, in id order)
  are deleted. Members that fail the §5.2
  guards (already merged — to `U` or anyone else —, owned by `U`, or
  blocked) are skipped, leave the cluster, and stay as they are: accepting
  never fails because of another member (D15). Shared effects of origin-4 merges
  wait for U's confirmation in B4 (D25). Each owner's pending forwards are
  delivered only for the accepted member's owner; the others become
  `offered`.
- **Cross-owner contact match (D9):** shown only if the matched phantom is
  visible to me.
- **Report / hide:** `complaintCreate` takes a target-aware id input (13-char
  ids as today, plus `PH` ids, P5); client `ComplaintCase` and
  `ComplaintScreen` get the `PH` branch with a visibility-scoped lookup port
  (§6.2); per-viewer hide table.
- **Non-user deletion (D26):** privacy contact address on the landing,
  runbook, Dart admin command (find by email HMAC across key versions, or by
  name + owner; delete; log). Needed before M8 ships.
- **Axiom amendment:** `docs/Tentura_current_status_quo.md` §2 "no dossier
  machine" → explicit amendment (owner-authored, attributed list of people the
  owner vouches for, not a compiled profile).

---

## 11. Privacy guarantees and how they are tested

1. **No Hasura exposure:** phantom tables are not in `hasura/metadata.json`
   (test asserts it); `invitation.phantom_id` is visible only through the
   issuer-filtered select permission.
2. **Phase 1 two-user pg suite:** owner A creates phantoms with names, tags,
   notes, avatars, pending forwards; user B (mutually visible to A, sharing a
   Request, **holding A's phantom invite code**) calls every read that carries
   person ids — Field snapshot, people tags, forward candidates, Request
   forwards, `invitationById`, invite preview (with and without `r`),
   attention feed, `graph()` — and no phantom id, name or note appears.
3. **Private objects:** anonymous and non-owner GET of a private avatar → 403.
4. **Logs:** phantom names/notes never logged; Sentry breadcrumbs scrub V2
   phantom ops' variables.
5. **Export (#780, D18):** phantoms, notes, private avatars and contact points
   join the export when #780 lands.
6. **Deletion:** owner deletion cascades every phantom table and enqueues
   private objects (§3.4); merged user's deletion orphans the phantom (delete
   actions §3, erasure lock order §5.2).

---

## 12. Milestones (one epic each, run in blocks, in this order)

| M | Epic | Depends on | Notes |
|---|---|---|---|
| M0 | Invite accept hardening | — | accept bodies restructured to the §5.2 order (claim → chain → trust; Defect A); Defect B; Defect C → D15 fallback across every gate (both signup methods, `acceptAsExisting`, `invitationAccept`; consumes the invite; signup → friendship + invite-accepted event with a "Request lapsed" outcome, existing account → admission-only); Defect D; landing preview + accept screen + post-join card; `invitationAccept` gets the same expiry check |
| M1 | Phase 1 phantoms | M0, #699 | storage + delete actions (§3) + PHANTOM anchors (§3.3) + mixed tags (§3.2) + invites (§4) + merge/undo/unlink (§5) + hint + Field/client + realtime (§6) + privacy suite (§11) + deadlock/contention tests |
| M2 | Private notes + private avatars on anyone (+ note search) | M1 | §3.4; merge avatar copy, display-time notes (§5.2) |
| M3 | Forward a Request to a phantom | M1 | §7 |
| M4 | Selective contact import | M1, M2 (avatars) | §8 + HMAC key ring (§9) |
| M5 | "Already on Tentura" check + setting | M4 | §9 account side, check, setting |
| M6 | Suggested ties (private) | M1 | §10.1 |
| M7 | Joiner review + confirmation flow | M6 | §10.2 |
| M8 | Shared visibility + clusters + safeguards | M7, M5, D26 runbook | §10.3 |

Each epic ends with a ship bead (next minor above current; raise
`kDefaultMinClientVersion` — no legacy-client support).

### #781 acceptance mapped

- "5 people placed, tagged, invite copied in < 2 min" → M1 widget/integration
  test of the A2 sheet flow (count of taps), manual QA timing.
- "Signs up via invite, keeps place and tags" → M1 pg test on both signup
  methods and both existing-account entrypoints.
- "Manual link + undoable merge" → M1 pg + widget test, including the §5.2
  pin case table and the §5.3 later-re-added-tag case.
- "No API response/notification/log exposes a phantom" → §11 suite.

---

## 13. Open questions

None. Q1–Q11 of the walk-through are decided (D12–D22).

---

## 14. Change log

- **rev 9 (2026-10-31), adversarial review round 3** (same roles). R59 tag
  ops lock phantoms, then join `_idempotent`'s transaction (§3.2). R60 merge
  owns the contact write; case layers record `phantomMerged` (§5.2). R61
  erasure pre-lock scoped to the final delete, cursor row locks only (§5.2).
  R62 first-seen helper in create / batch create; marker written even with
  no unseen peers (§5.4). R63 tag restore keeps merged phantoms' rows; the
  delete snapshot captures them (§3.2). R64 `phantomInviteEnsure` under the
  phantom `FOR UPDATE` (§4, §5.2). R65 already-active edge id via
  `bfe_active_unique`; shared body's conditions (§7). R66 tie creation locks
  phantoms `FOR SHARE`; ties in the order (§5.2, §10.1). R67 GC lease
  columns (§3.4). R68 `r` in the app route; post-merge `r` via ordinary
  readability (§4, §7). R69 remaining FK actions, check counter table,
  startup check site (§3, §9). R70 manual link and cluster merge lock
  invitations at step 2 (§5.2, §10.3). R71 pair lock for the block guard
  (§5.2). R72 merge-family paths run READ COMMITTED; unmerge takes
  `trust_pair_lock` before `vote_user` (§5.2, §5.3). Rejected with evidence:
  the `_idempotent` inversion as a blocker (same-actor re-entry,
  `tentura_db.dart:392–400`); erasure deleting published Requests (they're
  scrubbed); several active edges per pair (`bfe_active_unique`).
- **rev 8 (2026-10-31), adversarial review round 2** (reviewer Muse Wonder;
  critics Gemini 4 Argon and GPT-5.6-Sol standing in for GPT-6-Astra). R38
  lock order extended to invitations by phantom, pending forwards, `FOR
  SHARE` readers, per-path table; accept bodies restructured claim → chain →
  merge → trust (§5.2, M0). R39 waiting batch lock in READ COMMITTED
  accepts — Field contention can't abort a signup (§5.2). R40 delete,
  rename and erasure take their implicit locks explicitly; erasure pre-lock
  (§4, §5.2). R41 phantom tag inserts lock the phantom `FOR SHARE` before
  `person_tags` (§3.2). R42 tombstone row dropped from the pin table — a
  live U has none (§3.3, §5.2). R43 notes no longer copied: display-time
  sections, 4000 per row (D13, §3.4, §5.2, §5.3). R44 FK delete actions
  (§3). R45 dead-merge claimed rows lapse; `ForwardCase.deliverPending`
  defined incl. side effects and already-active edges (§7). R46 active-only
  tag reads, `off_field_count`, `membership_id` kept across tag restore
  (§3.2). R47 HMAC key ring moved to M4, indexes, startup key check, absent
  setting = ON + notice card (§3.5, §8, §9, §12). R48 GC on `UPDATE OF
  object_key`, queue PK and lease (§3.4). R49 preview/`r` touchpoints incl.
  landing transitions (§4). R50 invite minted on first Copy/Share (§4, §8).
  R51 names 3–32 (§3.1, §4, §8). R52 cluster members failing the guards are
  skipped; orphaned tie ends skipped (§10). R53 complaint screen +
  visibility-scoped port (§6.2, §10.3). R54 D15 for existing accounts stays
  admission-only; Defect D (D15, §2, M0). R55 first-seen marker (§5.4). R56
  PHANTOM in `applyBatch` FK retry, `shownAnchors`, client store (§3.3). R57
  owner-only phantom realtime, urgent refresh (§6.1). R58 note search
  defined (§3.4). Rejected with evidence: "private uploads write the object
  before the row" (`image_repository.dart:73–86` writes the row first).
- **rev 7 (2026-10-31), adversarial review round 1.** R1 `invitationById`
  leak → issuer-only projection (§4, §11). R2 global lock order incl. anchor
  batch/cursor, tx-scoped methods, deadlock tests (§5.2). R3/R29/R31 PHANTOM
  anchor: trigger identity + tombstone branch, apply-ops branch, watermarks,
  Dart/GraphQL plumbing (§3.3). R4 snapshot restore resolve + dedupe (§3.3).
  R5 already-friends phantom preview path (§4). R6 manual link deletes the
  invite; no token revival (§4, §5.2). R7/R27 unmerge keeps phantom
  memberships and uses `membership_id` (§3.2, §5.3); contact-name/avatar
  inverses (§5.3). R8 pre-existing-edge exception removed (D23). R9 note
  length rule (§3.4). R10 cap on unmerge (D4, §3.1). R11/R33 mixed tag
  repository + realtime trigger + `source` (§3.2). R12 private ACL + 403 test
  (§3.4). R13 delivery revalidation via `ForwardCase.deliverPending`, note
  kept, lapse terminal (§7). R14 claim/merge binding, terminal states (§7).
  R15 authorized `r` preview (§7). R16 HMAC key ring (§9). R17 ties keep
  phantom ids, deletion rule (§10.1). R18 shared-tie endpoint filtering
  (§10.3). R19 cluster merge protocol (§10.3). R20 §2 corrected (admission
  vs friendship; client complaint path). R21 Hasura `phantom_id` (§4). R22
  rename only via `phantomUpdate` (§4). R23 pin case table (§5.2). R24 hint
  first-seen rules (§5.4). R25 D15 across every gate incl. `invitationAccept`
  (§2, M0). R26 private-object GC queue with delete trigger + refcount
  (§3.4). R28 single expiry rule through entity/mapper + test matrix (§4).
  R30/R32 14-char `PH` ids: target-aware inputs, complaint port (P5, §10.3).
  R34 note copy instead of re-key (§5.2). R35 orphaned state (§0, §3.1).
  R36 `invitationAccept` (§2, M0). R37 manual-link forwards offered, not
  delivered (§5.1, §7).
- **rev 1–6 (2026-10-31):** walk-through decisions D1–D27.
