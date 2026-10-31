# #781 Phantoms — "map of my people" architecture

Status: **draft rev 6 (2026-10-31), under walk-through with the owner.**
Source: GitHub #781 (body + 11 owner comments, 2026-10-25), mockups
`docs/design/phantoms/phantoms-{a,b}.png`, plus decisions taken in the
2026-10-31 walk-through (marked **[2026-10-31]**).

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
| merge | Binding a phantom to a real account `U`. The phantom row survives (for Undo/Unlink) with `merged_user_id = U`. |
| claim | Phase 2 view of a phantom: "owner X says they know someone called Anna". |
| cluster | Phase 2: phantoms of different owners confirmed to be the same person. |
| tie | Phase 2: a suggested relation drawn by an owner. Never trust until confirmed. |

User-facing copy: **«Not on Tentura yet» / «Ещё не в Tentura»**; Field filter
chip «Not here yet · N». Never "phantom" in UI.

---

## 1. Decisions

### Already decided (owner)

- **D1 No MeritRank presence [2026-10-31].** Phantoms never appear in
  `user`, `vote_user`, `trust_evidence`, `user_trust_edge`, or pgmer2. Not even
  owner→phantom. Supersedes the 2026-10-25 "owner→placeholder is an ordinary MR
  edge" comment and the A3 mockup footer line.
- **D2 Owner-derived visibility [2026-10-31].** Viewer `v` sees phantom `h`
  iff `v` is an owner of `h`, or some owner `o` of `h` satisfies
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
- **D4** Cap **200 active phantoms per owner**.
- **D5** Phantoms **count toward Field caps** (#699 §3.4).
- **D6** Same-name hint card (A4) is on; the owner confirms; never automatic.
- **D7** Private notes, private avatars: any user, on any person (real or
  phantom); visible only to the author; never in merges for others,
  notifications, logs or MR; author-only export.
- **D8** Ties must start at the author or one of the author's own phantoms.
- **D9** "Already on Tentura" check via keyed HMAC, behind a per-user
  setting (default ON, explicit at signup), rate-limited, boolean answer. A
  match against *another owner's* phantom is shown only if that phantom is
  visible to the asker (D2).
- **D10** Shared phantoms carry name + ties only; photo/note/tags/contact
  points stay with each owner. Always attributed ("added by Vadim").
- **D11** Removal paths: owner deletes; "Ask Vadim to remove this
  placeholder" (B2); "Remove me from everyone's maps" (B4); non-user
  deletion request via a public page (#780). The non-user path must ship
  before shared visibility (M8).

- **D16 Phantom look [2026-10-31, Q4].** Violet accent token + ghost badge
  fixed now; exact stroke chosen in the first M1 UI bead (material-3 skill,
  screenshots for owner review). **Phantom nodes render semi-transparent when
  not selected**, full opacity when selected/hovered.
- **D17 Email only [2026-10-31, Q6].** Contact matching and contact points
  handle email only. Phones from imports are kept (if the owner opts in) as
  plain private text, never hashed or matched, until phone auth exists.
- **D18 Export deferred to #780 [2026-10-31, Q10].** Repositories expose
  owner-scoped readers; the export UI ships with #780.
- **D19 Owner surfaces [2026-10-31, Q11]:** Field map + list, a "Not on
  Tentura yet" section on the People screen (with invite status), people-tag
  member views (tag manager, Field tag view), the forward picker (M3), and
  People → Invites → Pending (phantom invites listed there too, labelled with
  the phantom's name, never expiring).

- **D20 Tie lifecycle — ties never become trust [2026-10-31, Q7].** A tie
  exists only while at least one end is a phantom. When the last phantom end
  merges into a real account (so both ends are real), the tie is **deleted**.
  Consequences: a third party (Alice) can never put any tie between two real
  people (Bob, Carol) in any scenario (anti-spam); a tie can't even be created
  between two real people (with D8, every tie has the author's own phantom
  at one end, or runs author → own phantom). Supersedes the 2026-10-25
  "suggested edges appear when the person joins … become real trust when
  confirmed" and the B4 "They suggested these ties" section.
- **D21 "Remove me from everyone's maps" [2026-10-31, Q8]:** rejects all
  pending "Is this you?" proposals about me and takes me out of every shared
  cluster; owners keep their private pin/tags/note on me. Each affected
  phantom gets a mark visible only to its owner: *"Someone asked to remove
  it."*
- **D22 "Ask Vadim to remove this placeholder" shows who asked [2026-10-31,
  Q9]:** the owner gets a card "Ivan asked you to remove «Anna K.» from your
  map"; rate-limited.

- **D23 Unmerge withdraws the owner's trust [2026-10-31].** Undo/Unlink of
  an invite-origin merge also withdraws the **owner's** trust edge to that
  account (`vote_user(owner → U)` removed, pair re-projected). `U`'s edge to
  the owner stays — it is `U`'s own outflow. Delivered Request forwards stay.
- **D24 Others' phantoms get a separate small budget on my Field
  [2026-10-31].** `kConstellationForeignPhantomCap` (start at 50), outside the
  400-peer cap, so they never push real people off. My own phantoms stay
  reserved + counted in the peer budget (D5).
- **D25 Phase 2 manual link: owner-side now, shared after confirm
  [2026-10-31].**
- **D26 Non-user deletion = privacy email address [2026-10-31].** The landing
  shows a privacy contact address; the operator handles requests by hand with
  a documented admin script (find phantoms by email HMAC — via a Dart admin
  command, since the key lives in the server env — or by name + owner;
  delete). No public form, no queue.

- **D27 GDPR check done — no gate [2026-10-31].** The owner reviewed it:
  fine as long as the data stays semi-closed, which Tentura guarantees —
  nothing is public, reach is limited by MeritRank and personal trust, and a
  shared phantom carries only a name (plus ties). Keep it that way: shared
  projections never grow beyond name + ties + attribution (D10).

### Proposed in this plan (confirm in walk-through)

- **D12 Separate tables [2026-10-31, Q1].** (was P1)
- **D13 Merge rules [2026-10-31, Q2]:** phantom pin wins, tags union, notes
  appended, an existing private avatar wins (§5.2).
- **D14 Same-name hint [2026-10-31, Q3]:** first-token casefold match +
  "newly seen" (§5.4).
- **D15 Request invites never block joining [2026-10-31, Q5].** Applies to
  *all* Request invites, not only phantoms: if the Request is closed/expired or
  the issuer can no longer forward, the invite falls back to an ordinary
  user-to-user invite (mutual connection with the issuer) and the invite
  screens say so: *"Vadim invited you to «Request», but it has already closed.
  You're still welcome on Tentura, and you're now connected with Vadim."*
  Covers the landing preview (before signup), the in-app accept-as-existing
  screen, and a card after joining. Lands in M0.

### Proposed in this plan (confirm in walk-through)

- **P1 Separate tables, additive reads (= D12).** Phantom data lives in its own
  tables, keyed by `phantom_id`, not tracked in Hasura (V2 resolvers only, like
  people tags). No existing query learns to *exclude* phantoms; a few new
  reads *add* them. Exception: `constellation_anchor`, which is already
  polymorphic (§3.3).
- **P2 One live invite per phantom**, non-expiring, rotated by "New link"
  (§4).
- **P3 Merge keeps the phantom row** and a merge record; Undo and Unlink are
  the same "unmerge" operation (§5).
- **P4 Request delivery is post-commit** and never blocks joining (§7).
- **P5 Id prefix `PH`** (`generateId('PH')`; `PT`/`P` are taken but
  prefix+lowercase-hex keeps them disjoint).

---

## 2. What exists today (relevant facts)

- **Invitations** (`m0193.dart:5580`): `id 'I'+12`, `user_id`, `invited_id`,
  `beacon_id`, `addressee_name ≤128`, `parent_forward_edge_id`,
  `invite_origin`, `accepted_at`. Expiry = `created_at + INVITATION_TTL`
  (7 d), checked at `user_repository.dart:232,412,939` and
  `invitation_entity.dart:32`. No renew endpoint. Hasura select own rows; the
  client lists invites via Hasura with a `created_at_gt` filter.
- **Accept paths**: signup `createInvited` / `createInvitedWithCredential`
  (`user_repository.dart:217,394`), existing account `InvitationCase.accept` /
  `acceptAsExisting` (`invitation_case.dart:311,349`) → `bindMutual`
  (`user_repository.dart:926`). All write mutual `vote_user` + project trust,
  upsert `user_contact(issuer, invitee, addressee_name)`, and for Request
  invites materialize a forward edge.
  - **Defect A:** lock order differs — signup claims the invitation then locks
    the parent forward chain; existing-account locks the chain then claims.
  - **Defect B:** `acceptAsExisting` on already-mutual friends with a
    non-Request invite returns `true` without consuming the invite.
  - **Defect C:** a closed Request (or lost forward right) on a Request invite
    *fails signup* (`_requireInviteIssuerMayForward`, `:153`).
- **Private per-viewer data**: `user_contact(viewer, subject, contact_name)`
  (private rename); people tags (`m0261`, V2-only, owner-scoped SQL).
- **Field**: V2 `constellationField` → `ConstellationFieldSnapshotReader`.
  Peers = visible set ∪ direct contacts (contact-only, #246) ∪ bond ∪
  temporary; caps `kConstellationPeerCap = 400`, reserved set outside the
  cap. Pins in `constellation_anchor` (kinds PERSON/BEACON, `target_id`,
  typed FK columns, tombstones). Layout snapshots store anchors as jsonb.
- **Client Field**: `NodeDetails` sealed (`FieldPersonNode`,
  `FieldBeaconNode`, `FieldDraftNode` — a precedent for non-user nodes).
  Canvas long-press/secondary tap already opens the create menu
  (`constellation_create_entry.dart`); app-bar "+" menu typed by
  `BeaconKind`. **Dashed outline already means "temporary person".**
- **Images**: public-read bucket `images/<authorId>/<id>.jpg`. Only
  authenticated binary path: room attachments
  (`room_attachment_download_controller.dart`).
- **Visibility**: `person_visible_peer_ids_tx(v, ctx)` (m0235) — memoized,
  epoch-stamped, fails closed. Same shape already used for discoverable
  Requests by author (`beacon_readable_ids`, m0242).
- **Not existing**: self-service data export (#780), About page, contacts
  plugin / vCard parsing, any per-person note or private avatar.

---

## 3. Data model (Phase 1)

All tables below: owner FK → `"user"(id) ON DELETE CASCADE`; **not tracked in
Hasura**; read/written by V2 resolvers with `WHERE owner_id = $viewer`.

### 3.1 `phantom`

| column | notes |
|---|---|
| `id text PK` | `PH` + 12 hex |
| `owner_id` | FK user CASCADE |
| `display_name text` | 1–128, trimmed |
| `emoji text NULL` | ≤ 8 (A2 "Photo / emoji") |
| `created_at`, `updated_at` | |
| `merged_user_id text NULL` | FK user **ON DELETE SET NULL** |
| `merged_at timestamptz NULL`, `merge_origin smallint NULL` | 1 invite-new, 2 invite-existing, 3 manual link |
| `revision bigint` | for realtime / optimistic concurrency |

- Active = `merged_at IS NULL`. Cap 200 counts active rows, checked under
  `SELECT … FOR UPDATE` on the owner's `user` row (or an advisory lock keyed
  by owner) in the create path.
- Merged row whose `merged_user_id` became NULL (merged account deleted):
  treated as gone; hidden everywhere.

### 3.2 Tag membership — `phantom_tag_member`

`(tag_id, owner_id, phantom_id)`, PK `(tag_id, phantom_id)`, composite FK
`(tag_id, owner_id) → person_tag`, FK phantom CASCADE. Separate from
`person_tag_member` so existing tag queries stay untouched (P1). The
1000-members-per-tag cap counts both tables. Automatic tags (`autoTagKinds`)
do not apply to phantoms.

### 3.3 Pins — extend `constellation_anchor`

Add `target_kind = 'PHANTOM'` and a typed column `phantom_id → phantom ON
DELETE CASCADE`; extend the exactly-one-target check. `target_id = phantom.id`.
Upsert validation joins `phantom` (owner = viewer, active) for that kind. Op
log / watermark are keyed by `(kind, target_id)` already — no change.
**Layout snapshots** (`constellation_layout_snapshot` jsonb) are not rewritten
on merge; restore resolves `PHANTOM:<id>` through `merged_user_id` at restore
time.

### 3.4 Notes and private avatars (any person) — M2

- `person_note(owner_id, subject_user_id NULL, subject_phantom_id NULL,
  body text ≤ 4000, updated_at)`; exactly-one subject; unique per
  `(owner, subject)`; `owner ≠ subject_user_id`.
- `person_private_avatar(owner_id, subject_user_id NULL, subject_phantom_id
  NULL, object_key, blurhash, width, height, created_at)`; same uniqueness.
- Object storage: new prefix `private/<ownerId>/<id>.jpg` **outside** the
  public-read policy, served by an authenticated controller (copy the room
  attachment pattern) that checks `owner_id = viewer`. Counts against
  `UPLOAD_DAILY_CAP_MB`; `kMaxImageUploadBytes` applies.
- Account erasure: both tables cascade; `user_erasure_case` adds the private
  prefix to object GC.

### 3.5 Phantom contact points — M4/M5

`phantom_contact_point(phantom_id, kind email|phone, value text NULL,
match_hmac bytea NULL, hmac_key_version smallint)`. `value` is stored only if
the owner chose to keep it (import default OFF); `match_hmac` only when D9
check applies (§9). Owner-private, CASCADE with phantom.

---

## 4. Invites (Phase 1)

- **`invitation.phantom_id text NULL → phantom ON DELETE CASCADE`**, unique
  partial index `WHERE invited_id IS NULL` → one live token per phantom.
- `addressee_name` mirrors `phantom.display_name` (kept in sync on rename),
  so the existing `_upsertInviteContact` makes the phantom's name the owner's
  private contact name for the joined account. This also answers #781 Q2
  ("you knew them as «Anna, workshop»"): the panel shows the contact name.
- **No expiry** when `phantom_id IS NOT NULL`: every TTL check (the three
  repository sites, `invitationById`, the client `created_at_gt` filter)
  learns this exemption.
- **"New link"** (A3 "Renew") rotates: delete the unaccepted row, insert a new
  one for the same phantom. Old links then say "invalid".
- **Remove phantom** deletes the live invite (CASCADE).
- Phantom invites **are listed** in People → Invites → Pending (D19), shown
  with the phantom's name and no expiry caption; tapping opens the phantom
  panel. Delete there = remove the invite only (the phantom stays, "New link"
  mints another). After merge they appear under "Accepted" as today.
- Link: `/invite/<code>`; with a Request context `/invite/<code>?r=<beaconId>`
  — `r` drives the landing preview only (§7).
- Share UI: A2/A3 "Copy invite link" + "Share…" with a prefilled personal
  line ("Hi Anna, I put you on my map in Tentura — join so we can ask each
  other for a hand."). Extend `ShareCodeDialog` / `SharePlus` call with
  `text`.
- Invite preview (`InvitationCase.preview`, landing) exposes **nothing** about
  the phantom (no tags, note, emoji); inviter as today.

---

## 5. Merge, Undo, Unlink (Phase 1)

### 5.1 Triggers

| Trigger | Origin | Trust effect |
|---|---|---|
| Signup through the phantom's invite | invite-new | existing `createInvited*` (mutual `vote_user`) |
| Accept-as-existing through the phantom's invite | invite-existing | existing `bindMutual`; **fix Defect B** so phantom invites always consume + merge, even if already mutual |
| Owner "This is someone already on Tentura…" → picks a person the owner can see on their Field | manual link | **none** (linking is private bookkeeping) |
| Same-name hint "Link them" (A4) | manual link | none |

### 5.2 Merge transaction (`PhantomMergeRepository.merge`)

Inside the accept transaction (invite origins) or its own (manual link).
**Global lock order** (fixes Defect A for all accept paths):
`invitation row (claim) → phantom row FOR UPDATE → parent forward chain →
trust_pair_lock(s)`. Post locks are not taken inside merge (§7).

Steps, owner `o`, phantom `h`, real user `U`:
1. Reject if `h` merged already, or `U = o`, or `block_hides(o, U)`.
2. Snapshot into `phantom_merge(id, phantom_id, owner_id, user_id, origin,
   created_at, undo jsonb, undone_at)`: U's prior anchor (if any, with
   revision), U's prior note/avatar presence, U's prior contact name.
3. **Pin:** phantom's anchor wins (#781 table row 4). If `o` already has a
   PERSON anchor on `U`, overwrite position; else re-key the PHANTOM anchor
   row to `PERSON/U`. Bump anchor cursor revision.
4. **Tags:** `INSERT INTO person_tag_member … SELECT … FROM
   phantom_tag_member ON CONFLICT DO NOTHING` (union); record inserted pairs
   in `undo`; delete the phantom memberships.
5. **Note / avatar:** re-key to `subject_user_id = U`; if `U` already has a
   note from `o`, append phantom note under a separator; avatar: keep the
   existing one, drop the phantom's (record object key for GC after the undo
   window).
6. **Contact name:** invite paths already upsert from `addressee_name`; manual
   link upserts `user_contact` only if `o` has none for `U`.
7. Set `merged_user_id, merged_at, merge_origin`; bump revisions; emit
   attention event `phantomMerged` to `o` only.

### 5.3 Undo / Unlink = unmerge

One operation, best effort, owner-only:
- re-activate `h`; move back tag pairs recorded in `undo` that still exist;
- pin: if U's anchor revision is unchanged since merge, move the position back
  to a PHANTOM anchor and restore U's prior anchor (or delete it); otherwise
  leave U's pin and give the phantom no pin;
- note: split back only if unchanged since merge; else keep on U;
- invite-origin merge (D23): remove `vote_user(owner → U)` and re-project the
  pair (`trust_project_pair`, same lock order as §5.2); `U → owner` stays;
  delivered forwards stay. The `undo` record stores whether the owner's edge
  pre-existed the merge (accept-as-existing between people who already
  trusted each other) — then it is **kept**;
- the invite stays consumed — the phantom gets a fresh token on "New link".

Snackbar UNDO (A4) calls it immediately; "Unlink" in the merged person's panel
calls it later (covers "invite link forwarded and someone else accepted it").

### 5.4 Same-name hint (A4)

Computed in the owner's Field snapshot: active phantom `h` and a person `p` on
the owner's Field such that `first_token(casefold(h.name)) =
first_token(casefold(p.display_name or o's contact name for p))` (≥ 2 chars),
`person_field_first_seen(o, p) > h.created_at`, and no dismissal in
`phantom_link_hint_dismissal(phantom_id, user_id)`. "Not her" writes the
dismissal (D14).

---

## 6. Field and client (Phase 1)

### 6.1 Server

- `ConstellationFieldSnapshotReader` adds `phantoms: [PhantomRecord]` for
  `owner = viewer` (Phase 1): `id, displayName, emoji, hasPrivateAvatar,
  ownTagIds, pinState, inviteState (none | live), createdAt, linkHint?`.
- **Caps (D5):** own active phantoms join the reserved set (always shown, like
  direct contacts) **and** reduce the remaining peer budget:
  `peerBudget = 400 − |own phantoms|`. Worst case 200 phantoms → 200 slots
  for the rest.
- `constellationFieldHasNoContacts` (#252) stays "no real contacts"; the empty
  banner gains a "+ Person" action.

### 6.2 Client (`features/phantoms/`, clean architecture)

- Entity `Phantom`; repository over new V2 ops: `phantomCreate`,
  `phantomUpdate`, `phantomDelete`, `phantomInviteRotate`, `phantomLink`,
  `phantomUnmerge`, `phantomHintDismiss`; reads ride on the Field snapshot.
- `NodeDetails.FieldPhantomNode`, graph id `fh:<id>`; `ConstellationPerson`-like
  rows in the List view (#253) and name search.
- **Look:** violet phantom accent (new design-system token, light/dark) +
  ghost badge + a stroke **distinguishable from the temporary dashed
  outline**, semi-transparent unless selected/hovered (D16). Stroke decided in
  the M1 design bead via the `material-3-flutter` skill.
- **Other owner surfaces (D19):** People screen section "Not on Tentura yet"
  (name, tags, invite status, Copy link); phantoms as members in tag manager
  and Field tag view (tag member lists become person-or-phantom).
- **Create:** canvas long-press / secondary tap menu gains "Add someone not on
  Tentura yet" (A1) — the menu entry type stops being `BeaconKind` only; the
  app-bar "+" menu gets "+ Person". Sheet A2: name, photo/emoji, tags, note
  (note/photo only after M2), invite text, Copy link / Share…, "Save without
  inviting"; position = the long-press point (creates the PHANTOM anchor).
- **Panel A3:** name, «Not on Tentura yet · invite sent N days ago», tags
  (existing tag block), note, Copy invite link, New link, This is someone
  already on Tentura…, Remove from my map (confirm).
- **Filter chip** «Not here yet · N» in `ConstellationVisibilityBar`.
- **Merge snackbar** on `phantomMerged` (A4) with UNDO; arrangement-history
  entries are not used for merge (server-side op).
- Cross-platform: every long-press path has secondary-tap + visible button.

---

## 7. Forwarding a Request to a phantom — M3

- Table `phantom_pending_forward(id, phantom_id, sender_id, beacon_id,
  parent_forward_edge_id NULL, note, created_at, state pending|delivered|
  lapsed, resolved_at)`; unique `(phantom_id, beacon_id) WHERE pending`.
  Phase 1: `sender_id = owner`.
- Forward sheet: "Invite a new person" bar gains **"Pick from my
  placeholders"**; phantoms appear as owner-only candidates. Picking records a
  pending forward (same forward-policy checks as a real forward, under the
  Post lock as today) and offers Copy/Share of
  `/invite/<phantomCode>?r=<beaconId>`. No new invitation row.
- A2 "Attach a request (optional)" = create a pending forward.
- Request → People tab → Forwards (sender's view only): "Vasya (not on Tentura
  yet)", status pending/lapsed.
- Joining via a phantom invite with a lapsed pending forward uses the same
  D15 copy and card.
- **Lapse is computed, not triggered:** displayed/resolved as lapsed when the
  Request is closed/expired or the sender can no longer forward.
- **Delivery (P4):** after the merge transaction commits, a
  `PhantomForwardDeliveryCase` runs each pending forward in its own short
  transaction via the existing `_materializeBeaconInviteForward` path
  (idempotent, ON CONFLICT DO NOTHING); lapsed → attention card for the joiner
  "Vadim sent you a request; it has since closed. You're connected with
  Vadim." A retry sweep picks up rows left `pending` for merged phantoms.
  **Joining never fails because of a Request.**
- Link opened after merge → "You're already on Tentura, log in"; if `r` is
  still active and undelivered, open it.
- D15 makes the same rule global for plain Request invites (M0).
- No forward-count caps exist today; nothing to count against.

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
- `phantomCreateBatch` (atomic, ≤ remaining cap) → phantoms land unpinned,
  tagged with an own tag **"Imported"** (created if absent; the tag magnet
  clusters them). Photos then upload one by one as private avatars.
- Only ticked rows leave the device. No invites are sent by import.

---

## 9. "Already on Tentura" check — M5

- Server secret `CONTACT_MATCH_HMAC_KEY` + `hmac_key_version` (rotation =
  recompute in a background job).
- **Email only (D17).** Normalization `trim().toLowerCase()` (same as
  `email_auth_util.dart`). Phones are never hashed or matched.
- `account_verified_contact.match_hmac` written by both writers
  (`_insertAuthoritativeContacts`, `addVerifiedContacts`) + a one-shot
  backfill task (needs the key, so Dart, not SQL migration).
- Setting **"People who have my email can see I'm on Tentura"**: stored
  outside the Hasura-readable `user` columns (new `user_privacy_setting` row,
  default ON). Explicit choice at signup (native register screen + landing
  name step); toggle in Settings → Account (or a new Privacy group).
- `contactCheck(kind, value)` → `{alreadyOnTentura: bool}`; also run on
  phantom contact save/import. Only users with the setting ON match.
  **200 checks/day/account**, counter + log alert on bulk patterns.
- UI: "Already on Tentura — send them an invite yourself." Existing user is
  never notified.

---

## 10. Phase 2

### 10.1 Suggested ties — M6

- `phantom_tie(id, author_id, from_user_id NULL, from_phantom_id NULL,
  to_user_id NULL, to_phantom_id NULL, kind, created_at)`;
  `from` = author or author's own phantom (D8); `to` = any person or phantom
  visible to the author; **CHECK at least one end is a phantom** (D20).
  Kinds: `know_each_other`, `from_vouches_to`, `to_vouches_from` (B1).
- Drawn on the author's Field as dotted "suggested" edges. Private to the
  author in M6, shared in M8. Zero MR effect, ever.
- **On merge (D20):** ties re-point the merged end at `U`; any tie whose ends
  are now both real is deleted in the same transaction (and on unmerge it is
  **not** restored — `undo` doesn't record ties). Same rule when a cluster
  merges.

### 10.2 Confirmation flow + joiner review — M7

- **Joiner review (B4)** after signup or on first merge of an existing user:
  "N people already had you on their map" (owners' real names, only owners
  who merged a phantom into me), "Is this you?" link proposals with That's me
  / Not me, Continue, "Remove me from everyone's maps" (D21). **No ties
  section** (D20). Nothing accepted by default.
- **Manual link becomes a proposal** once Phase 2 is on (D25): the owner's private
  merge still happens immediately (Phase 1 behaviour, owner-side only), but
  anything visible to `U` (ties, attribution, cluster) needs `U`'s
  confirmation ("Vadim had you on his map, is that you?").
- "Remove me from everyone's maps" (D21): rejects link proposals about me,
  removes me from all clusters' shared view (M8), marks each affected
  phantom for its owner ("Someone asked to remove it"); owners' private data
  is unaffected.

### 10.3 Shared visibility, clusters, safeguards — M8

- **Read (D2):** others' phantoms enter my Field snapshot when an owner is in
  my visible set (minus blocks). Projection = display name (owner's name for
  it), attribution ("added by Vadim and 2 others" — owners visible to me +
  count of the rest), ties authored by owners visible to me (dedup count).
  Never note, avatar, emoji, tags, contact points. Placed by force layout
  near visible owners. **Budget (D24):** at most
  `kConstellationForeignPhantomCap` (50) foreign phantoms, outside the peer
  cap, ranked by number of visible owners then recency.
- **B2 actions:** "I know Anna too — add to my map" (creates my own phantom
  with the name + a cluster proposal), "Invite her", "Ask Vadim to remove this
  placeholder" (attention card to the owner naming the requester, D22;
  rate-limited).
- **Clusters (B3):** `phantom_cluster_link(a, b, proposed_by, confirmed_at)`;
  cluster = connected component over confirmed links. Shared identity: one
  attribution list, deduped ties, any owner's token joins. Merge into `U`
  merges every cluster member (each owner's own local merge; each owner's
  pending forwards delivered with that owner as sender — per-owner tokens).
  "Leave this merge" deletes only my links.
- **Cross-owner contact match (D9):** shown only if the matched phantom is
  visible to me.
- **Report / hide:** complaint flow gains a phantom target (fix the
  `startsWith('U')` branch in `complaint_case.dart`); per-viewer hide table.
- **Non-user deletion request (D11, D26):** privacy contact address on the
  landing + operator runbook and a Dart admin command (find by email HMAC or
  name + owner, delete, log the erasure). Blocks M8 ship.
- **Axiom amendment:** `docs/Tentura_current_status_quo.md` §2 "no dossier
  machine" → explicit amendment (owner-authored, attributed list of people the
  owner vouches for, not a compiled profile).
- **GDPR:** checked by the owner (D27); no gate. Any later change that adds
  fields to the shared projection or makes phantoms reachable outside the MR /
  trust neighbourhood reopens it.

---

## 11. Privacy guarantees and how they are tested

1. **No Hasura exposure:** phantom tables are not in `hasura/metadata.json`
   (a test asserts it).
2. **Phase 1 two-user pg suite:** owner A creates phantoms with names, tags,
   notes, pending forwards; user B (mutually visible to A, sharing a Request)
   calls every read that carries person ids — Field snapshot, people tags,
   forward candidates, Request forwards, invite preview of A's phantom
   invite, attention feed, `graph()` — and no phantom id or name appears.
3. **Logs:** phantom names/notes never logged; Sentry breadcrumbs scrub V2
   phantom ops' variables.
4. **Export (#780, D18):** self-service export does not exist yet; phantoms,
   notes, private avatars and contact points join it when #780 lands.
5. **Deletion:** owner deletion cascades every phantom table + private
   objects; merged user's deletion nulls `merged_user_id` (phantom becomes
   hidden).

---

## 12. Milestones (one epic each, run in blocks, in this order)

| M | Epic | Depends on | Notes |
|---|---|---|---|
| M0 | Invite accept hardening | — | Defect A (lock order), Defect B (consume on already-mutual), Defect C → D15 fallback (server + landing preview + accept screen + post-join card) |
| M1 | Phase 1 phantoms: storage, invites, Field, merge/undo/unlink, hint, privacy suite | M0, #699 | the "first slice" acceptance of #781 |
| M2 | Private notes + private avatars on anyone (+ search) | M1 | A5; re-keys on merge |
| M3 | Forward a Request to a phantom | M1 | §7 |
| M4 | Selective contact import | M1, M2 (avatars) | §8 |
| M5 | "Already on Tentura" check + setting | M4 | §9 |
| M6 | Suggested ties (private) | M1 | §10.1 |
| M7 | Joiner review + confirmation flow | M6 | §10.2 |
| M8 | Shared visibility + clusters + safeguards | M7, M5, D26 runbook + admin command | §10.3 |

Each epic ends with a ship bead (next minor above current; raise
`kDefaultMinClientVersion` — no legacy-client support).

### #781 acceptance mapped

- "5 people placed, tagged, invite copied in < 2 min" → M1 widget/integration
  test of the A2 sheet flow (count of taps), manual QA timing.
- "Signs up via invite, keeps place and tags" → M1 pg test on both accept
  paths.
- "Manual link + undoable merge" → M1 pg + widget test.
- "No API response/notification/log exposes a phantom" → §11 suite.

---

## 13. Open questions for the walk-through

- ~~Q1~~ → D12. ~~Q2~~ → D13. ~~Q3~~ → D14.
- ~~Q4~~ → D16.
- ~~Q5~~ → D15.
- ~~Q6~~ → D17.
- ~~Q7~~ → D20. ~~Q8~~ → D21. ~~Q9~~ → D22.
- ~~Q10~~ → D18. ~~Q11~~ → D19.
