# #781 Phantoms — "map of my people" architecture

Status: **rev 7 (2026-10-31)** — design walk-through with the owner done
(D1–D27); rev 7 applies adversarial review round 1 (reviewer GPT-6.1-Sol,
critics Gemini 4 Argon + GPT-6-Astra, advisory Muse Wonder; findings R1–R37,
change log §14).
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
  union, notes appended, an existing private avatar on U wins (§5.2).
- **D14 Same-name hint:** first-token casefold match + "newly seen" (§5.4).
- **D15 Request invites never block joining.** Applies to *all* Request
  invites, not only phantoms: if the Request is closed/expired/unreadable, the
  issuer can no longer forward, or the parent forward chain was cancelled, the
  invite falls back to an ordinary user-to-user invite (consumed; mutual
  connection with the issuer) and the invite screens say so: *"Vadim invited
  you to «Request», but it has already closed. You're still welcome on
  Tentura, and you're now connected with Vadim."* Landing preview (before
  signup), in-app accept screen, and a card after joining. Lands in M0.
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
  - **Defect A:** lock order differs — signup claims the invitation then locks
    the parent forward chain; `bindMutual` locks the chain then claims.
  - **Defect B:** `acceptAsExisting` on already-mutual friends with a
    non-Request invite returns `true` without consuming the invite.
  - **Defect C (several gates):** `_requireInviteIssuerMayForward`
    (`:153`) throws on a closed/expired Request or lost forward right;
    `_materializeBeaconInviteForward` → `_lockActiveInviteParentChain`
    (`:115,196`) throws on a cancelled ancestor *after* the user row is
    created; `bindMutual` returns `false` before claiming on a broken chain
    (`:945`); `_acceptBeaconInviteOnly` throws on unreadable /
    non-forwardable Requests.
- **Private per-viewer data**: `user_contact(viewer, subject, contact_name)`;
  people tags (`m0261`, V2-only, owner-scoped SQL, `person_tags:<owner>`
  advisory lock, realtime trigger `notify_person_tag_change` m0262).
- **Field**: V2 `constellationField` → `ConstellationFieldSnapshotReader`
  (snapshot read first; `person_field_first_seen` rows written afterwards,
  with `-infinity` on the viewer's first backfill read,
  `constellation_field_repository.dart:124–152`). Caps
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
  `custom_types.dart:1112`; snapshot decode `values.byName`).
- **Client Field**: `NodeDetails` sealed (`FieldPersonNode`,
  `FieldBeaconNode`, `FieldDraftNode`). Canvas long-press/secondary tap opens
  the create menu (`constellation_create_entry.dart`); app-bar "+" menu typed
  by `BeaconKind`. **Dashed outline already means "temporary person".**
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

All new tables: owner FK → `"user"(id) ON DELETE CASCADE`; **not tracked in
Hasura**; read/written by V2 resolvers with `WHERE owner_id = $viewer`.

### 3.1 `phantom`

| column | notes |
|---|---|
| `id text PK` | `PH` + 12 hex (14 chars, P5) |
| `owner_id` | FK user CASCADE |
| `display_name text` | 1–128, trimmed |
| `emoji text NULL` | ≤ 8 (A2 "Photo / emoji") |
| `created_at`, `updated_at` | |
| `merged_user_id text NULL` | FK user **ON DELETE SET NULL** |
| `merged_at timestamptz NULL`, `merge_origin smallint NULL` | 1 invite-new, 2 invite-existing, 3 manual link, 4 cluster (M8) |
| `current_merge_id text NULL` | → `phantom_merge.id` of the live merge |
| `revision bigint` | realtime / optimistic concurrency |

- States: **active** (`merged_at IS NULL`), **merged** (`merged_at` and
  `merged_user_id` set), **orphaned** (`merged_at` set, `merged_user_id`
  NULL — hidden everywhere, unmerge refused, snapshot restore drops it).
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
  under the existing `person_tags:<owner>` lock:
  - `applyMembers` accepts `PH` ids: validated against `phantom` (owner =
    caller, active) instead of `"user"`, written to `phantom_tag_member`;
  - `memberships`, member counts and the 1000-per-tag limit read/count both
    tables;
  - tag delete snapshot and its restore carry `{kind: person|phantom, id}`;
    restore skips phantoms that are no longer active;
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

Application (shared + server + client):
- `ConstellationAnchorTargetKind.phantom`, a sealed phantom target, wire
  parsing, the GraphQL enum, `_existingUpsertTargets` / `_storedAnchors`,
  `ConstellationAnchorProjectionReader`, snapshot capture/list/decode/restore
  and client adapters — with round-trip tests for PHANTOM *and* the existing
  kinds;
- upsert validation for PHANTOM joins `phantom` (owner = viewer, active).

Layout snapshots are not rewritten on merge. **Restore resolves then dedupes:**
`PHANTOM:h` → `PHANTOM:h` (active), `PERSON:U` (merged), dropped (orphaned or
deleted); if two entries resolve to the same target, the one that came from a
phantom wins (D13); deduplication happens before any write.

### 3.4 Notes and private avatars (any person) — M2

- `person_note(owner_id, subject_user_id NULL, subject_phantom_id NULL,
  body text, updated_at, revision)`; exactly-one subject; unique per
  `(owner, subject)`; `owner ≠ subject_user_id`. **Length:** API writes are
  capped at 4000 chars but may not *lengthen* a note beyond
  `max(4000, current length)`; the DB check is 8200 chars, so a merged note
  (two notes + separator, §5.2) always fits.
- `person_private_avatar(owner_id, subject_user_id NULL, subject_phantom_id
  NULL, object_key, blurhash, width, height, created_at)`; same uniqueness.
  Several rows may reference one `object_key` (merge copies, §5.2).
- **Storage:** prefix `private/<ownerId>/<uuid>.jpg`, uploaded with an
  explicit **private ACL** (the adapter's default public-read metadata is
  overridden), served only by an authenticated controller that checks
  `owner_id = viewer`. Test: anonymous direct GET of a private object → 403.
  Counts against `UPLOAD_DAILY_CAP_MB`; `kMaxImageUploadBytes` applies.
- **GC:** a new `private_object_gc(object_key, enqueued_at)` queue. A
  `BEFORE DELETE` row trigger on `person_private_avatar` enqueues the key, so
  every path — avatar replacement, phantom deletion, owner erasure, subject
  erasure, FK cascades — is covered. The worker deletes the object only when
  no `person_private_avatar` row references the key any more.

### 3.5 Phantom contact points — M4/M5

`phantom_contact_point(phantom_id, kind email|phone, value text NULL,
match_hmac bytea NULL, hmac_key_version smallint NULL)`. `value` is stored
only if the owner chose to keep it (import default OFF); `match_hmac` is
computed for every email (D17) at write time. Owner-private, CASCADE with
phantom. Key versions: §9.

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
  only through `phantomUpdate`, which updates both rows in one transaction
  under the phantom row lock; `invitationUpdate` rejects phantom invites.
  So the existing `_upsertInviteContact` makes the phantom's name the owner's
  private contact name for the joined account (answers #781 Q2).
- **"New link"** (A3 "Renew") — active phantoms only: delete the unaccepted
  row, insert a new one. Old links then say "invalid".
- **Remove phantom** deletes the live invite (CASCADE). **Manual link**
  deletes it too (§5.2). A merged phantom has no live invite; unmerge never
  revives an old token — the owner mints one with "New link".
- **Invites tab (D19):** phantom invites listed in Pending with the
  phantom's name and no expiry caption; tapping opens the phantom panel.
  Delete there = remove the invite only (the phantom stays).
- **Link:** `/invite/<code>`; with a Request context `/invite/<code>?r=<beaconId>`
  — `r` only feeds the preview (§7).
- **Share UI:** A2/A3 "Copy invite link" + "Share…" with a prefilled personal
  line ("Hi Anna, I put you on my map in Tentura — join so we can ask each
  other for a hand."). Extend `ShareCodeDialog` / `SharePlus` with `text`.
- **Preview** (`InvitationCase.preview`, landing) exposes nothing about the
  phantom (no name, tags, note, emoji); inviter as today.
- **Already friends:** for a phantom invite the preview never returns the
  terminal `alreadyFriends`; it returns `existingUser` with
  `phantomInvite: true`, and the client calls accept (merge) and shows
  "You're on Vadim's map". The client path is covered end to end.

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

**Global lock order** — every path that touches these resources, including
plain anchor batches, tag edits, phantom create/update/delete/rotate and all
accept paths, acquires them in this order (skipping what it doesn't need):

1. Post lock (Request invites only; `PostLockRepository`);
2. invitation row (claim: `UPDATE … WHERE invited_id IS NULL`);
3. cluster row `FOR UPDATE` (M8, clustered phantoms only);
4. per owner, in owner-id order: `lockConstellationViewerBatch(owner)` →
   `lockConstellationViewerCursor(owner)` (upserting a missing cursor row) →
   `phantoms:<owner>` advisory lock;
5. phantom row(s) `FOR UPDATE`, in id order;
6. anchor rows (and their target watermarks);
7. `person_tags:<owner>` advisory lock → tag memberships;
8. parent forward chain `FOR UPDATE` (Request invites);
9. `trust_pair_lock`s (sorted, as `_applyReciprocalTrustEdges` does).

Plain anchor batches only take 4→6 (they never lock a phantom row beyond the
FK check), so they cannot cycle with merge. Defect A is fixed by moving
`bindMutual`'s claim before its chain lock. **M1 ships a pg deadlock test**
for merge × anchor batch on the same owner, merge × phantom delete, and
signup × existing-account accept of the same Request invite.

Steps for owner `o`, phantom `h`, user `U`:

1. **Guards:** `h` active; `U ≠ o`; `NOT block_hides(o, U)`.
2. **Record** `phantom_merge(id, phantom_id, owner_id, user_id, origin,
   created_at, undo jsonb, undone_at)`; `undo` gets everything below.
3. **Pin** (case table; `h` anchors are never tombstoned — phantom deletion
   cascades):

   | `h` anchor | U anchor | Action | `undo` records |
   |---|---|---|---|
   | none | any | keep U as is | nothing |
   | live | none | delete `PHANTOM:h`, insert `PERSON:U` at h's position | h position; "U had none" |
   | live | live | set U's position to h's, delete `PHANTOM:h` | h position; U's prior position |
   | live | tombstone | delete the tombstone, insert `PERSON:U` at h's position | h position; "U had tombstone" |

   Inserts/updates set `target_kind`/`target_id` explicitly. Bump the target
   watermarks of **both** `PHANTOM:h` and `PERSON:U` (stale pre-merge
   conditional writes then fail), and record U's watermark after the merge.
4. **Tags:** for each `phantom_tag_member(T, h)`: insert `(T, U)` into
   `person_tag_member` unless it exists (skip if `block_hides`); record in
   `undo` the *full* original phantom membership list and the
   `membership_id` of every row the merge inserted. Phantom memberships are
   **kept** on `h` (the merged phantom is hidden, so they're invisible).
5. **Note:** `h`'s note row stays on `h`. If U has no note from `o`, create
   one with `h`'s body; else append `"\n\n— «<h name>»\n" + h body`. Record
   U's prior body/absence and the resulting `revision`.
6. **Avatar:** `h`'s avatar row stays on `h`. If U has no private avatar from
   `o`, insert a row for U referencing the same `object_key` (record it);
   otherwise U's wins (D13).
7. **Contact name:** invite origins: `_upsertInviteContact` already wrote
   `addressee_name`; manual link: upsert only if `o` has none. Record U's
   prior contact name/absence and the value written.
8. **Invite:** invite origins: the claimed invite is the phantom's; manual
   link: delete `h`'s live invite.
9. **Ties (M6+):** delete ties whose ends would both be real (§10.1).
10. Set `merged_user_id, merged_at, merge_origin, current_merge_id`; bump
    revisions; emit attention event `phantomMerged` to `o` only.

### 5.3 Undo / Unlink = unmerge

Owner-only; refused for orphaned phantoms; subject to the cap (D4). Inside
one transaction with the §5.2 lock order:

- **Tags:** delete U's memberships whose `membership_id` matches one recorded
  as merge-inserted (a later removal + re-add has a new id and stays);
  `h`'s own memberships were never removed (tags deleted since simply drop
  out via CASCADE).
- **Pin:** if U's target watermark still equals the recorded post-merge
  value, restore U's prior state (none / position / tombstone) and re-create
  `PHANTOM:h` at the recorded position; otherwise leave U's pin and give `h`
  no pin. Bump both watermarks.
- **Note / contact name:** restore U's prior value only if the current
  revision/value equals what the merge wrote; `h`'s own note row is untouched.
- **Avatar:** delete the U row the merge inserted, if still present (the
  object survives — `h` still references it).
- **Trust (D23):** invite origins: remove `vote_user(o → U)` and re-project
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
- **First-seen initialization:** creating a phantom first runs the owner's
  first-seen backfill if the owner has no first-seen rows yet (same
  transaction), so `-infinity` only ever marks people seen before the first
  phantom existed.
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

### 6.2 Client (`features/phantoms/`, clean architecture)

- Entity `Phantom`; repository over new V2 ops: `phantomCreate`,
  `phantomUpdate`, `phantomDelete`, `phantomInviteRotate`, `phantomLink`,
  `phantomUnmerge`, `phantomHintDismiss`; reads ride on the Field snapshot.
- `NodeDetails.FieldPhantomNode`, graph id `fh:<id>`; rows in the List view
  (#253) and name search.
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
- **Report (M8):** `ComplaintCase` gets a phantom lookup port and a `PH`
  branch.
- Cross-platform: every long-press path has secondary-tap + visible button.

---

## 7. Forwarding a Request to a phantom — M3

- Table `phantom_pending_forward(id, phantom_id, sender_id, beacon_id,
  parent_forward_edge_id NULL, note, created_at, state, merge_id NULL,
  recipient_id NULL, forward_edge_id NULL, resolved_at)`; states
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
  2. after commit, `PhantomForwardDeliveryCase` handles each claimed row in
     its own short transaction: lock the row, check it still belongs to the
     phantom's `current_merge_id`, then **re-run the full forward checks**
     (`ForwardCase.deliverPending`: Request status, sender readability and
     forward right, policy, blocks between sender and U, recipient
     eligibility, parent chain alive) and insert the forward edge with the
     stored note → `delivered` + `forward_edge_id`; any failed check →
     `lapsed` (terminal, never throws);
  3. a retry sweep processes only `claimed` rows whose `merge_id` is the
     phantom's live merge. Terminal rows are never re-delivered, so a forward
     the sender later cancelled is not resurrected.
  4. lapsed rows produce the joiner card *"Vadim sent you a request; it has
     since closed. You're connected with Vadim."* — the connection clause only
     when the merge created the connection (invite origins do).
- **Manual link:** pending rows become `offered`: the owner sees "Forward
  «Request» to Anna now?" and confirming runs an ordinary forward to U. Never
  delivered automatically; no joiner card.
- **Unmerge:** `claimed` rows of that merge return to `pending`.
- Link opened after merge → "You're already on Tentura, log in"; if `r` is
  still active and undelivered, open it.
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
  phantoms land unpinned, tagged with an own tag **"Imported"** (created if
  absent; the tag magnet clusters them). Photos then upload one by one as
  private avatars.
- Only ticked rows leave the device. No invites are sent by import.

---

## 9. "Already on Tentura" check — M5

- **Email only (D17).** Normalization `trim().toLowerCase()` (as
  `email_auth_util.dart`).
- **Key ring:** `CONTACT_MATCH_HMAC_KEYS` (versioned). Writes use the newest
  version. Matching computes the candidate hash under every version still
  referenced by any stored row. `account_verified_contact` keeps plaintext,
  so its hashes are re-keyed by a background job; hash-only phantom rows
  can't be, so their key version stays in the ring until those rows are gone.
  A version is retired only when no row references it.
- `account_verified_contact.match_hmac` + `hmac_key_version` written by both
  writers (`_insertAuthoritativeContacts`, `addVerifiedContacts`) + a one-shot
  Dart backfill.
- Setting **"People who have my email can see I'm on Tentura"**: new
  `user_privacy_setting` row (outside Hasura-readable `user` columns), default
  ON; explicit choice at signup (native register screen + landing name step);
  toggle in Settings → Account.
- `contactCheck(kind, value)` → `{alreadyOnTentura: bool}`; also run on
  phantom contact save/import. Only users with the setting ON match.
  **200 checks/day/account**, counter + log alert on bulk patterns.
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
  unmerge need no tie bookkeeping.
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
  other members' live invites are deleted. Shared effects of origin-4 merges
  wait for U's confirmation in B4 (D25). Each owner's pending forwards are
  delivered only for the accepted member's owner; the others become
  `offered`.
- **Cross-owner contact match (D9):** shown only if the matched phantom is
  visible to me.
- **Report / hide:** `complaintCreate` takes a target-aware id input (13-char
  ids as today, plus `PH` ids, P5); client `ComplaintCase` gets the phantom
  port and branch; per-viewer hide table.
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
   private objects (§3.4); merged user's deletion orphans the phantom.

---

## 12. Milestones (one epic each, run in blocks, in this order)

| M | Epic | Depends on | Notes |
|---|---|---|---|
| M0 | Invite accept hardening | — | Defect A (lock order), Defect B, Defect C → D15 fallback across every gate (both signup methods, `acceptAsExisting`, `invitationAccept`; consumes the invite, `bindFriendship: true`, invite-accepted event with a "Request lapsed" outcome); landing preview + accept screen + post-join card; `invitationAccept` gets the same expiry check |
| M1 | Phase 1 phantoms | M0, #699 | storage + PHANTOM anchors (§3.3) + mixed tags (§3.2) + invites (§4) + merge/undo/unlink (§5) + hint + Field/client (§6) + privacy suite (§11) + deadlock tests |
| M2 | Private notes + private avatars on anyone (+ search) | M1 | §3.4; merge copies (§5.2) |
| M3 | Forward a Request to a phantom | M1 | §7 |
| M4 | Selective contact import | M1, M2 (avatars) | §8 |
| M5 | "Already on Tentura" check + setting | M4 | §9 |
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
