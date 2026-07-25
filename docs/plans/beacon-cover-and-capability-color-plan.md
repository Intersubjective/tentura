---
status: ready
kind: plan
revision: 3
---

# Unified request visual identity (cover) + capability colour system — implementation plan

**Revision 3 (2026-07-25).** This revision resolves all twelve findings from
Appendix A and all fifteen findings from
`docs/plans/beacon-cover-review-rev2.md`. It is an execution document: every
step names the files, compatibility boundary, and gate. Do not improvise a
different media protocol or contract the legacy surface early.

**Goal.** A Request has exactly one resolved visual identity:

1. its selected cover photo when `cover_source = photo` and the selected image
   is still attached;
2. otherwise the icon of `primary_need_slug`, coloured by its capability group;
3. otherwise the neutral `Icons.campaign_outlined` glyph.

The author may retain a selected photo while choosing the symbol presentation.
The old free-form symbol taxonomy is removed only after the additive server and
new client have completed their compatibility window. User-facing text says
**Request**; code and schema continue to use `beacon`.

---

## 0. Revision 3 finding resolution

Appendix A is the verbatim revision-1 review. The second table maps the hostile
revision-2 re-review to corrections in this plan.

| ID | Severity | Revision 3 resolution | Sections |
| --- | --- | --- | --- |
| CR-1 | Blocking | Authorize before upload, re-authorize and check attachment under the beacon lock, and use an author-scoped image-row delete. | §3.3, §3.5, §9.2 |
| CR-2 | Blocking | Every upload returns its exact image ID; no position-to-ID inference remains. | §2.3, §3.3, §7.5 |
| CR-3 | High | New uploads are invisible stages; one locked `beaconSetMedia` publishes the full media state. Database deletion and GC enqueue commit together. | §3.3, §3.4, §7.5 |
| CR-4 | High | Composite FK enforces cover membership; deferrable position uniqueness and a beacon-row lock serialize all media writes. | §3.1, §3.3, §9.2 |
| CR-5 | High | `BeaconStageImage` and `BeaconSetMedia` are direct-V2 operations with a routing contract test. | §2.3, §6 Step 6, §9.4 |
| CR-6 | High | Additive `m0130` and legacy fields survive every intermediate compile gate; contraction is a separate final step. | §3.1, §6 |
| CR-7 | High | Responsive theming preserves sibling extensions; access is fail-fast and tested in the real light/dark responsive tree. | §5.4, §9.1 |
| CR-8 | Medium | Canonical slug order and explicit cover-source wire values live in `tentura_root`. | §3.7, §6 Step 1 |
| CR-9 | Medium | `Beacon.displayImages` is the only cover-first projection used by gallery, viewer, URLs, counters, and aspect ratios. | §4.3, §9.3 |
| CR-10 | Medium | Mutations reject invalid input; only client rendering tolerates stale persisted/read data. | §3.5, §4.2 |
| CR-11 | Medium | The control shows persisted preference, fallback is explained, crop cancellation preserves state, and server-image crop reuses `fetchImageBytes`. | §7.1, §7.4 |
| CR-12 | Medium | Cleanup includes tests and generated mocks; generation precedes tests and dead-reference gates. | §8, §11 |

| ID | Severity | Revision 3 resolution | Sections |
| --- | --- | --- | --- |
| CR2-1 | Blocking | `m0130` is additive; `m0131` is the only legacy-column contraction. | §3.1, §6 Steps 3 and 10 |
| CR2-2 | Blocking | `beacon_image_stage` and `beaconStageImage` make uploads invisible until `beaconSetMedia`; create/draft/edit/retry sequences are explicit. | §2.3, §3.3, §7.5 |
| CR2-3 | High | Failed upload/attach compensation runs after rollback in a new transaction; remote deletion is outbox-only; hash scheduling is non-fatal after commit. | §3.3, §3.4, §9.2 |
| CR2-4 | High | `m0130` backfills canonical primary, dense positions, and lowest-position cover; `m0131` requires fresh production authorization. | §3.1, §6 Step 10 |
| CR2-5 | High | `UNIQUE (image_id)` establishes one-upload/one-beacon ownership before any detach-delete behavior ships. | §3.1, §9.2 |
| CR2-6 | High | The plan uses the repository's list workaround, retains `v2_Upload = {}`, adds required integer input support, and reloads Hasura before schema fetch. | §2.3, §3.6, §11 |
| CR2-7 | High | Five concrete invariant exceptions accompany the five appended codes. | §3.5, §6 Step 5 |
| CR2-8 | High | One `resolveIdentity(allowPhoto:)` implementation handles normal, error, stale, and unreadable states using live capability APIs. | §4.2, §9.3 |
| CR2-9 | High | Theme access has no fallback; `TenturaIdentityTileFrame` owns shared square geometry in the design system. | §5.4, §6 Steps 2 and 7 |
| CR2-10 | High | GC claims use owner-checked leases and `FOR UPDATE SKIP LOCKED` through a narrow port. | §3.4, §9.2 |
| CR2-11 | Medium | `BeaconCreateCase` owns orchestration through `BeaconWritePort` and `BeaconImagePort`; the cubit injects only the case. | §4.4, §6 Step 8 |
| CR2-12 | Medium | Only direct capability renderers change; semantic coordination colours and external geometry remain unchanged. | §5.4, §9.1 |
| CR2-13 | Medium | Commands use root-preserving subshells, zero-match source greps, both packages' generation checks, active goldens, and the documented Hasura reload order. | §9.5, §11 |
| CR2-14 | Medium | Live-tree facts and contrast claims are corrected; migration, compatibility, cleanup, concurrency, privacy, layout, and web tests are mandatory. | §1, §5.3, §9 |
| CR2-15 | Medium | Rollout is server-additive → Hasura reload → old-client smoke → client bake/telemetry → gated forward-only contraction. | §6, §12 |

### 0.1 Closed product decisions

| ID | Decision |
| --- | --- |
| D-1 | Removing the primary capability auto-promotes the canonical-first remaining capability. Only empty `needs` produces no primary. |
| D-2 | The 40 px list identity may show the selected photo. |
| D-3 | “Adjust crop” reuses the profile image cropper at 1:1 with `CropStyle.rectangle`; the replacement is a new upload, not a separate cover asset. |
| D-4 | `primary_need_slug` must be a member of `needs`; the symbol sheet cannot choose an unattached capability. |
| D-5 | `special` uses neutral slate rather than a salient category hue. |
| D-6 | The neutral glyph is `Icons.campaign_outlined`. |
| D-7 | The segmented control shows persisted `cover_source`. If the preferred branch cannot render, helper text explains the fallback. |
| D-8 | Field update and media reconciliation are two visible commands. Updates and reconciliation are idempotent and internally consistent; staged uploads are not visible. Initial create is submitted once, its returned beacon ID is retained before staging, and an unknown create response is never auto-resubmitted. |

---

## 1. Ground truth about the live tree

Rechecked on 2026-07-25. Deployment counts in Step 10 are deliberately not
frozen here and must be rerun against the named production environment.

| Fact | Verified live detail |
| --- | --- |
| Workspace | Root package is `tentura_root`; members are `packages/client`, `packages/server`, and `packages/tentura_lints`. Both client and server already depend on the root package. |
| Shared wire precedent | `lib/domain/entity/beacon_status.dart` uses explicit smallint values and parsing. Do not persist `enum.index`. |
| PostgreSQL | `compose.dev.yaml:99` uses `vbulavintsev/postgres-tentura:v0.8.0`, PostgreSQL 17.9. The repository image executed `ON DELETE SET NULL (cover_image_id)`, the circular beacon/image delete path, a composite FK to `beacon_image(beacon_id,image_id)`, and a deferrable unique constraint successfully. |
| Migrations | Raw migrations are parts of `packages/server/lib/data/database/migration/_migrations.dart`. Latest is `m0129` at lines 134 and 267; next IDs are `m0130` and `m0131`. |
| `beacon_image` | `packages/server/lib/data/database/table/beacon_images.dart` has composite PK `(beaconId,imageId)`, `position`, and Drift `withoutRowId`. The composite PK is a valid referenced key. It does not make `image_id` globally unique. |
| `image` | `packages/server/lib/data/database/table/images.dart` has UUID PK `id`, `authorId → users.id`, dimensions, hash, and creation time. |
| `beacon` | `packages/server/lib/data/database/table/beacons.dart` has legacy `iconCode`/`iconBackground`, comma-joined `needs`, and no cover/primary columns. |
| Capabilities | Client `CapabilityTag` and server `kAllowedCapabilitySlugs` contain the same 37 slugs in the same order. Client lookup is `CapabilityTag.fromSlug`; localized label API is `labelOf`. There are seven groups. |
| Image cap | `kMaxImagesPerBeacon = 10` in `packages/server/lib/domain/use_case/beacon_case.dart:32`. |
| Lock helper | `BeaconRepository.runInBeaconStateTransaction` at `:281-295` locks by beacon ID but does not authorize. Every caller must compare the locked entity's author with `userId`. |
| Current image authorization | `BeaconCase.addImage` writes before its final owner check; `removeImage` lacks an attachment check. `ImageRepository.delete` at `:96-106` deletes by UUID alone and directly removes storage. |
| Current add response | `beaconAddImage` returns a beacon; the client selection `{ id }` is the beacon ID, not the image ID. |
| Direct V2 routing | `_tenturaDirectOperationNames` is in `packages/client/lib/data/service/remote_api_client/build_client.dart:120-155`. Unlisted operations go through Hasura. |
| GraphQL list workaround | `packages/server/WORKAROUNDS.md:55-86` forbids `.nonNullable()` on `GraphQLListType`. `InputFieldImageIds.field` introspects as `[String!]`; `fromArgs` enforces argument presence. Scalar non-null is safe. |
| Upload shape | `InputFieldUpload` and the generated schema expose the upload argument as `v2_Upload = {}`. Retain that compatibility shape. |
| Theme bug | `TenturaResponsiveScope` replaces the extension list at `packages/client/lib/design_system/tentura_responsive_scope.dart:25`; `TenturaTheme` currently registers only tokens at `tentura_theme.dart:92`. |
| Lint scope | Raw feature colours/radii/spacing are linted only in the configured operational directories; design-system files are excluded. Still use design-system primitives everywhere. |
| Gallery coupling | `beacon_image_gallery.dart` and `beacon_gallery_viewer.dart` index `images` and `imageUrls` in parallel; `beacon_image.dart` uses `images.first`. |
| Worker connections | `TaskRepository` uses a separate `pg_job_queue` connection, so it cannot be the transactional image GC outbox. `TaskWorkerCase` is process-local and multiple server processes may poll concurrently. |
| Existing client bytes API | `ImageRepository.fetchImageBytes` already exists at `packages/client/lib/data/repository/image_repository.dart:64-70`; do not add `fetchBytes`. |
| Hasura metadata | Beacon select permission lists legacy icon columns at `hasura/metadata.json:222-223`. The surrounding list is not alphabetically sorted; make only required edits. |
| Local audit | Read-only local counts were 573 users, 187 beacons, six legacy-icon beacons, zero duplicate attached image IDs, zero beacon/image author mismatches, and zero duplicate positions. This is not proof about production users. |
| Custom lints | Run `./scripts/check-custom-lints.sh` at package roots. Current ratchets are client 115 and server 0. `flutter analyze` does not load the plugin, and neither does `dart analyze <subdir>`. |
| Goldens | The existing `typography_overhaul_test.dart` golden group is skipped. New cover goldens must be active standalone tests. |

---

## 2. Target contract and invariants

### 2.1 Persisted shape

Add to `public.beacon`:

```text
primary_need_slug TEXT NULL
cover_image_id   UUID NULL
cover_source     SMALLINT NOT NULL DEFAULT 0  -- 0 photo, 1 symbol
```

Keep `cover_image_id` while `cover_source = symbol`; toggling back to photo is
lossless. `cover_source = photo` with no images is valid and resolves to symbol
or neutral. When any images exist, commands preserve a selected attached
`cover_image_id`.

### 2.2 Invariants

| ID | Invariant |
| --- | --- |
| N1 | Every non-null `primary_need_slug` is one of the 37 allowed slugs. |
| N2 | `primary_need_slug` is null iff `needs` is empty; otherwise it is a member of `needs`. |
| N3 | If a primary is removed, choose `canonicalFirstCapabilitySlug(remainingNeeds)`. Never use `Set` iteration order. |
| C1 | `cover_image_id` is null when there are no attached images. |
| C2 | When images exist, `cover_image_id` identifies one attached image, including while symbol presentation is selected. |
| C3 | `(beacon.id,beacon.cover_image_id)` is enforced by FK to `beacon_image(beacon_id,image_id)`. |
| M1 | An `image_id` belongs to at most one `beacon_image` row. |
| M2 | Positions are dense `0..n-1` and unique per beacon at commit. |
| M3 | All attach, detach, reorder, cover, legacy add/remove, stage expiry, and fork writes lock the beacon row first. |
| A1 | No object upload begins before a read-only owner check; authority is rechecked under the write lock before publication/staging. |
| A2 | Remote object deletion never occurs inside a database transaction. A committed row delete and GC enqueue are atomic. |

### 2.3 Additive GraphQL compatibility surface

| Operation/type | Additive contract through client bake |
| --- | --- |
| `beaconCreate`, `beaconUpdate`, `beaconUpdateDraft` | Add optional `primaryNeedSlug: String`. Retain `iconCode`/`iconBackground`. Retain `beaconCreate(image: v2_Upload = {})`; the new client passes `image: null` and stages explicitly. An omitted `primaryNeedSlug` is legacy input and derives canonical-first from submitted `needs`; an explicitly supplied null is valid only for empty `needs`. |
| `v2_Beacon` | Add nullable `primaryNeedSlug`, nullable `coverImageId`, and non-null `coverSource: Int!`. Retain legacy icon fields until Step 10. |
| `beaconAddImage` | Legacy immediate-attach bridge. Keep upload input shape. Return `v2_BeaconImageAdded! { id: String!, imageId: String!, beacon: v2_Beacon! }`; `id` remains the beacon ID so old `{ id }` documents keep working. |
| `beaconStageImage` | New `beaconStageImage(id: String!, image: v2_Upload = {}): v2_BeaconImageStaged!` returning `imageId` and `beaconId`; it does not change `beacon_image`. |
| `beaconSetMedia` | New `beaconSetMedia(id: String!, imageIds: [String!], coverImageId: String, coverSource: Int!): v2_Beacon!`. `InputFieldImageIds.fromArgs` enforces presence; do not call `.nonNullable()` on the list. |
| `beaconRemoveImage`, `beaconReorderImages` | Retained and hardened for legacy clients, but the new save path never calls them. |
| `beaconSetCover` | Does not exist. Do not add it. |

Add `BeaconStageImage` and `BeaconSetMedia` to
`_tenturaDirectOperationNames`. Add the payload/input types to the server V2
schema, the client documents, and the routing contract test. Only Step 10
removes legacy fields and arguments.

---

## 3. Server design

### 3.1 Additive migration `m0130`

Create `packages/server/lib/data/database/migration/m0130.dart`, register its
`part` and list entry after `m0129`, and execute statements in this order.
Before applying in any populated environment, record that both preflights
return zero rows:

```sql
SELECT image_id, count(*)
FROM public.beacon_image
GROUP BY image_id
HAVING count(*) > 1;

SELECT beacon_id, position, count(*)
FROM public.beacon_image
GROUP BY beacon_id, position
HAVING count(*) > 1;

SELECT bi.beacon_id, bi.image_id, b.user_id AS beacon_author,
       i.author_id AS image_author
FROM public.beacon_image AS bi
JOIN public.beacon AS b ON b.id = bi.beacon_id
JOIN public.image AS i ON i.id = bi.image_id
WHERE b.user_id <> i.author_id;
```

If the first or third query returns rows, stop. Do not choose an owning beacon
or delete another author's image. If only the second returns rows, the
deterministic rank update below repairs them.

```sql
ALTER TABLE public.beacon
  ADD COLUMN primary_need_slug TEXT NULL,
  ADD COLUMN cover_image_id UUID NULL,
  ADD COLUMN cover_source SMALLINT NOT NULL DEFAULT 0,
  ADD CONSTRAINT beacon_cover_source_ck CHECK (cover_source IN (0, 1));

UPDATE public.beacon AS b
SET primary_need_slug = (
  SELECT canonical.slug
  FROM (VALUES
    ('transport',1),('storage',2),('pickup_delivery',3),('tools',4),
    ('physical_help',5),('calls',6),('translation',7),('writing',8),
    ('negotiation',9),('introductions',10),('local_knowledge',11),
    ('legal_navigation',12),('medical_navigation',13),('documents',14),
    ('verification',15),('pets',16),('childcare',17),('eldercare',18),
    ('emotional_support',19),('hosting',20),('money',21),('food',22),
    ('housing',23),('equipment',24),('workspace',25),('tech_help',26),
    ('repair',27),('manual_work',28),('software',29),('design',30),
    ('admin_paperwork',31),('time',32),('contact',33),('orders',34),
    ('gig',35),('job',36),('other',37)
  ) AS canonical(slug, ord)
  WHERE canonical.slug =
      ANY (regexp_split_to_array(b.needs, '\s*,\s*'))
  ORDER BY canonical.ord
  LIMIT 1
)
WHERE b.needs <> '';

WITH ranked AS (
  SELECT beacon_id,
         image_id,
         (row_number() OVER (
           PARTITION BY beacon_id ORDER BY position, image_id
         ) - 1)::integer AS new_position
  FROM public.beacon_image
)
UPDATE public.beacon_image AS bi
SET position = ranked.new_position
FROM ranked
WHERE bi.beacon_id = ranked.beacon_id
  AND bi.image_id = ranked.image_id;

ALTER TABLE public.beacon_image
  ADD CONSTRAINT beacon_image_position_uq
    UNIQUE (beacon_id, position) DEFERRABLE INITIALLY DEFERRED,
  ADD CONSTRAINT beacon_image_image_id_uq UNIQUE (image_id);

UPDATE public.beacon AS b
SET cover_image_id = (
  SELECT bi.image_id
  FROM public.beacon_image AS bi
  WHERE bi.beacon_id = b.id
  ORDER BY bi.position, bi.image_id
  LIMIT 1
)
WHERE b.cover_image_id IS NULL
  AND EXISTS (
    SELECT 1
    FROM public.beacon_image AS bi
    WHERE bi.beacon_id = b.id
  );

ALTER TABLE public.beacon
  ADD CONSTRAINT beacon_cover_image_membership_fk
  FOREIGN KEY (id, cover_image_id)
  REFERENCES public.beacon_image (beacon_id, image_id)
  ON DELETE SET NULL (cover_image_id);

CREATE INDEX beacon_cover_image_id_idx
  ON public.beacon (cover_image_id)
  WHERE cover_image_id IS NOT NULL;

CREATE TABLE public.beacon_image_stage (
  image_id UUID PRIMARY KEY
    REFERENCES public.image(id) ON DELETE CASCADE,
  beacon_id TEXT NOT NULL
    REFERENCES public.beacon(id) ON DELETE CASCADE,
  staged_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX beacon_image_stage_expiry_idx
  ON public.beacon_image_stage (staged_at, beacon_id);

CREATE TABLE public.image_object_gc (
  image_id UUID PRIMARY KEY,
  author_id TEXT NOT NULL,
  enqueued_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT NULL,
  lease_owner TEXT NULL,
  lease_until TIMESTAMPTZ NULL
);

CREATE INDEX image_object_gc_claim_idx
  ON public.image_object_gc (next_attempt_at, lease_until, enqueued_at)
  WHERE attempts < 10;
```

`beacon.id` and `users.id` are text in the live schema; keep the Drift stage/GC
types aligned with the generated table definitions. Do not add an FK from the
GC outbox to `image`: the image row is intentionally deleted in the same
transaction that creates the outbox row.

Step 3 Drift changes are additive:

- retain `iconCode` and `iconBackground` in `table/beacons.dart`;
- add `primaryNeedSlug`, `coverImageId`, and `coverSource`;
- add `table/beacon_image_stages.dart` and `table/image_object_gcs.dart`;
- register both tables in `tentura_db.dart`.

### 3.2 Final migration `m0131`

Create and deploy `m0131` only in Step 10. Before the migration, the new server
must already normalize every write so the check can validate existing rows.

```sql
ALTER TABLE public.beacon
  ADD CONSTRAINT beacon_primary_need_membership_ck CHECK (
    (needs = '' AND primary_need_slug IS NULL)
    OR
    (needs <> ''
      AND primary_need_slug IS NOT NULL
      AND primary_need_slug =
          ANY (regexp_split_to_array(needs, '\s*,\s*')))
  );

ALTER TABLE public.beacon
  DROP COLUMN icon_code,
  DROP COLUMN icon_background;
```

This migration is forward-only. A server binary that still reads legacy
columns cannot be rolled back after it. Step 10 therefore requires the rollout
and authorization gates in §6; failure to prove any gate means `m0131` is not
created or deployed.

### 3.3 Media write protocol

All methods below use the same beacon-row lock.

**`beaconStageImage`.**

1. Read the beacon and reject a non-owner before uploading any bytes.
2. Call hardened `ImageRepository.put`; it returns the exact image ID only
   after the object write succeeds.
3. In `runInBeaconStateTransaction`, recheck owner, recheck the combined
   attached-plus-staged count against 10, verify the image row is owned by the
   actor, and insert `beacon_image_stage`.
4. Commit, then schedule blurhash work. Catch/log scheduling failure; the
   mutation still succeeds.
5. If step 3 fails, catch outside the rolled-back callback. In a new Drift
   transaction enqueue GC, delete the actor-owned image row, and rethrow.
6. Return `imageId` and `beaconId`. No reader of the beacon can see the stage.

**Legacy `beaconAddImage`.** Perform the same precheck, upload, locked
re-authorization, cap check, and post-rollback compensation, but insert directly
into `beacon_image` at `max(position)+1`. When the beacon has no selected cover,
set the new image as cover. Return both the compatibility `id = beaconId` and
the exact `imageId`.

**`beaconSetMedia`.** Inside one `runInBeaconStateTransaction`:

1. verify `locked.author.id == userId`;
2. load attached rows and this beacon's staged rows under the lock;
3. reject duplicate `imageIds`, more than 10 IDs, an ID belonging to neither
   set, an unknown `coverSource`, or a cover ID outside `imageIds`;
4. require `coverImageId == null` when `imageIds` is empty and require a
   non-null member cover when `imageIds` is non-empty;
5. delete attached rows omitted from `imageIds`; for each corresponding owned
   image, enqueue GC and delete the image row in this transaction;
6. discard staged rows omitted from `imageIds` the same way;
7. for desired staged IDs, delete the stage row and insert `beacon_image`;
8. update/insert every desired row to its list index; the deferrable uniqueness
   constraint permits transient position collisions;
9. update `cover_image_id` and `cover_source` last and return the locked beacon.

The retry after a successful call is a no-op: all desired IDs are now attached,
and no staged ID is required. The retry after a failed transaction sees the
unchanged attachments/stages. Do not call `beaconRemoveImage` or
`beaconReorderImages` from the new client save path.

**Legacy remove/reorder.** `removeImage` checks actor and exact attachment under
the lock, enqueues GC plus deletes the actor-owned image row in the same
transaction, and selects the lowest remaining `(position,image_id)` when the
removed image was the cover. `reorderImages` checks that the supplied set
exactly equals the attached set and writes dense positions under the lock.

**Stage expiry.** A worker sweep considers stages older than 24 hours. For each
candidate it locks that beacon, rechecks age and presence, enqueues GC, and
deletes the owned image row. The same beacon lock makes expiry versus
`beaconSetMedia` deterministic. Never expire an attachment.

### 3.4 Object storage cleanup and leases

`pg_job_queue` is not the outbox. Add
`packages/server/lib/domain/port/image_object_gc_port.dart` with typed rows and:

```dart
Future<void> enqueue({
  required String imageId,
  required String authorId,
});

Future<void> removeObject({
  required String imageId,
  required String authorId,
});

Future<List<ImageObjectGcLease>> claim({
  required String leaseOwner,
  required DateTime now,
  int limit = 32,
});

Future<bool> complete({
  required String imageId,
  required String leaseOwner,
});

Future<bool> fail({
  required String imageId,
  required String leaseOwner,
  required DateTime retryAt,
  required String error,
});
```

Implement it in
`packages/server/lib/data/repository/image_object_gc_repository.dart`. Claim in
one transaction:

```sql
WITH due AS (
  SELECT image_id
  FROM public.image_object_gc
  WHERE attempts < 10
    AND next_attempt_at <= $2
    AND (lease_until IS NULL OR lease_until <= $2)
  ORDER BY next_attempt_at, enqueued_at, image_id
  FOR UPDATE SKIP LOCKED
  LIMIT $3
)
UPDATE public.image_object_gc AS gc
SET lease_owner = $1,
    lease_until = $2 + interval '2 minutes',
    attempts = gc.attempts + 1
FROM due
WHERE gc.image_id = due.image_id
RETURNING gc.*;
```

`complete` deletes only `WHERE image_id = ? AND lease_owner = ?`.
`fail` updates `last_error` and exponential-backoff `next_attempt_at`, and
clears the lease only under the same owner predicate. An expired lease is
claimable again. A missing object is successful/idempotent completion. Rows at
10 attempts remain queryable for operations; document the inspection query in
the runbook. `enqueue` uses `INSERT ... ON CONFLICT (image_id) DO NOTHING`; a
retry must not reset attempts or steal a live lease.

Add one self-throttled `TaskWorkerCase` closure. Its per-process
`leaseOwner` is a random UUID created at worker startup. It claims, calls the
narrow port's object-removal method using
`$kImagesPath/$authorId/$imageId.$kImageExt`, and completes/fails by lease
owner. Remote removal happens only here, after the database transaction that
removed the image row has committed.

Remove direct object deletion from every live caller, not only
`beaconSetMedia`: legacy `removeImage`, full beacon deletion, fork/create
compensation, stage expiry, and
`packages/server/lib/domain/use_case/user_case.dart` account deletion all
enqueue before deleting image rows in the same Drift transaction. The domain
worker talks only to `ImageObjectGcPort`; its data implementation may delegate
the physical MinIO call to the existing storage service.

Harden `ImageRepository.put`: generate the ID, insert the row, and attempt the
remote write. If the remote call throws or may have partially written, run a
new database transaction that enqueues the known object path and deletes the
owned row; preserve the original error after logging any compensation error.

### 3.5 Strict validation and exception types

Server writes are strict:

- unknown primary slug → `BeaconPrimaryNeedInvalidException`;
- non-null primary absent from submitted `needs`, or null with non-empty
  `needs` → `BeaconPrimaryNeedNotInNeedsException`;
- media ID outside attached-or-staged set →
  `BeaconImageNotAttachedException`;
- cover outside desired media → `BeaconCoverNotAttachedException`;
- duplicate IDs, invalid cover-source wire value, or null/non-null cover
  mismatch → `BeaconMediaInvalidException`.

Append, never reorder, these values in
`packages/server/lib/domain/exception_codes.dart`:

```dart
beaconPrimaryNeedInvalid,       // 1304
beaconPrimaryNeedNotInNeeds,    // 1305
beaconImageNotAttached,         // 1306
beaconCoverNotAttached,         // 1307
beaconMediaInvalid,             // 1308
```

Add the five named `ExceptionBase` subclasses in
`packages/server/lib/domain/exception.dart`, each fixed to its corresponding
code. Tests assert class and numeric GraphQL extension code. Do not reuse
`BeaconCreateException` for these branches.

Legacy requests omit `primaryNeedSlug`. The resolver must detect key absence
before coercion and pass a compatibility flag; the use case derives
canonical-first from the same submitted `needs`. Explicit new-client null with
non-empty needs remains invalid.

### 3.6 GraphQL and Hasura files

Edit:

- `packages/server/lib/api/controllers/graphql/input/_input_types.dart`: add
  `InputFieldInt.fieldNonNullable` and a required parser;
- add `input/input_field_beacon_media.dart` to compose the existing
  resolver-required `InputFieldImageIds`, optional cover ID, and required
  integer;
- `custom_types.dart`: additive beacon fields plus
  `v2_BeaconImageAdded` and `v2_BeaconImageStaged` payloads;
- `mutation/mutation_beacon.dart`: retain legacy arguments, add stage/media
  mutations, and implement omitted-versus-explicit primary handling;
- `hasura/metadata.json`: add the three beacon select columns without removing
  or reordering the legacy columns.

The server schema contract test must assert:

- `imageIds` introspects as `[String!]` and the resolver rejects absence;
- `coverSource` introspects as `Int!`;
- upload remains `v2_Upload = {}`;
- old create/update/add documents validate unchanged;
- both new operations resolve directly in V2.

After deploying the additive server, apply metadata, reload Hasura's `tentura`
remote schema, and only then run `docker compose run --rm schema_fetcher`.

### 3.7 Shared wire contracts

Add `lib/domain/capability/capability_slugs.dart` with the 37 slugs in the
verified order and:

```dart
const kCapabilitySlugOrder = <String>[/* exact verified 37 slugs */];
final kCapabilitySlugRank = <String, int>{
  for (var i = 0; i < kCapabilitySlugOrder.length; i++)
    kCapabilitySlugOrder[i]: i,
};

String? canonicalFirstCapabilitySlug(Iterable<String> slugs) {
  String? result;
  var rank = kCapabilitySlugOrder.length;
  for (final slug in slugs) {
    final candidate = kCapabilitySlugRank[slug];
    if (candidate != null && candidate < rank) {
      rank = candidate;
      result = slug;
    }
  }
  return result;
}
```

Copy the exact slug literals from the live client enum; do not retype from
memory. The server adapter exports this file and derives
`kAllowedCapabilitySlugs = kCapabilitySlugOrder.toSet()`.

Add `lib/domain/entity/beacon_cover_source.dart`:

```dart
enum BeaconCoverSource {
  photo(0),
  symbol(1);

  const BeaconCoverSource(this.wireValue);
  final int wireValue;

  static BeaconCoverSource parse(int value) => switch (value) {
    0 => photo,
    1 => symbol,
    _ => throw ArgumentError.value(value, 'value', 'unknown cover source'),
  };

  static BeaconCoverSource fromWireOrPhoto(int? value) => switch (value) {
    1 => symbol,
    _ => photo,
  };
}
```

Export both through `lib/domain.dart`. Command paths use `parse`; client read
mapping alone uses `fromWireOrPhoto`.

---

## 4. Client domain and orchestration

### 4.1 Resolved identity types

Add `packages/client/lib/domain/entity/beacon_cover.dart`:

```dart
sealed class BeaconIdentity {
  const BeaconIdentity();
}

final class BeaconIdentityPhoto extends BeaconIdentity {
  const BeaconIdentityPhoto(this.image);
  final ImageEntity image;
}

final class BeaconIdentitySymbol extends BeaconIdentity {
  const BeaconIdentitySymbol(this.tag);
  final CapabilityTag tag;
}

final class BeaconIdentityNeutral extends BeaconIdentity {
  const BeaconIdentityNeutral();
}
```

### 4.2 One identity resolver

Add `primaryNeedSlug`, `coverImageId`, and `coverSource` to `Beacon`; retain
legacy fields until Step 9. Implement only this decision point:

```dart
ImageEntity? get coverImage {
  final selected = coverImageId;
  if (selected == null) return null;
  return images.where((image) => image.id == selected).firstOrNull;
}

BeaconIdentity resolveIdentity({required bool allowPhoto}) {
  if (!canReadContent) return const BeaconIdentityNeutral();

  if (allowPhoto && coverSource == BeaconCoverSource.photo) {
    final selected = coverImage;
    if (selected != null) return BeaconIdentityPhoto(selected);
  }

  final slug = primaryNeedSlug;
  if (slug != null && needs.contains(slug)) {
    final tag = CapabilityTag.fromSlug(slug);
    if (tag != null) return BeaconIdentitySymbol(tag);
  }
  return const BeaconIdentityNeutral();
}

BeaconIdentity get identity => resolveIdentity(allowPhoto: true);
```

Use a small local `firstOrNull` loop if the current dependencies do not expose
that extension. Do not add a package for it. `Image.network.errorBuilder` calls
`resolveIdentity(allowPhoto: false)` and renders that returned branch; it does
not independently inspect slug, needs, or cover fields. Labels use
`tag.labelOf(l10n)`.

### 4.3 Stable image identity and ordered projection

Add `@Default('') String localKey` to `ImageEntity` and:

```dart
String get key => id.isNotEmpty ? id : localKey;
```

Every local pick gets a UUID `localKey`; server images use their exact `id`.
Never infer a returned ID from list position.

`Beacon.displayImages` returns the valid selected cover first, then every other
image in persisted order. `displayImageUrls` maps that exact list. Migrate
`beacon_image.dart`, `beacon_image_gallery.dart`, `beacon_gallery_viewer.dart`,
`beacon_definition_body.dart`, and `graph_node_widget.dart` so image object,
URL, aspect ratio, page count, current index, and viewer `initialIndex` all use
the same projection. No widget may index `images` and `imageUrls` separately.

### 4.4 `BeaconCreateCase` boundary

Add domain ports:

```text
packages/client/lib/domain/port/beacon_write_port.dart
packages/client/lib/domain/port/beacon_image_port.dart
packages/client/lib/domain/use_case/beacon_create_case.dart
```

`BeaconRepository implements BeaconWritePort` and exposes field create,
draft-update, published-update, `stageImage`, and `setMedia`. `ImageRepository
implements BeaconImagePort` and exposes the existing `fetchImageBytes` plus
the existing crop operation through domain-only byte/image inputs. Ports return
only domain entities/typed results, never Ferry types.

`BeaconCreateCase` owns:

```dart
Future<BeaconSaveResult> create(BeaconSaveCommand command);
Future<BeaconSaveResult> saveDraft(BeaconSaveCommand command);
Future<BeaconSaveResult> saveEdit(BeaconSaveCommand command);
Future<ImageEntity?> adjustCoverCrop(ImageEntity image);
```

Each save method performs its field command, stages only local images, replaces
each local entry with the exact returned ID, then calls one `setMedia`. On a
stage failure it throws a typed `BeaconSaveFailure` carrying the progressed
image list, returned beacon ID, and failed phase so the cubit can emit it and
retry without position inference or a second create.
Successfully staged but unused images remain private and expire; a later
successful reconciliation discards unused stages.

`BeaconCreateCubit` injects only `BeaconCreateCase`. Remove concrete repository
imports, fields, constructor parameters, and GetIt lookups from the cubit. It
continues to own picker/crop UI effects and state transitions, but all
multi-repository persistence orchestration belongs to the case.

---

## 5. Capability group colour system

### 5.1 Rules

- Capability colour is a tinted container plus on-container glyph, never
  semantic status text, border, action, or coordination colour.
- Icon and label remain the semantic channel; colour is redundant.
- Colour is a pure function of `CapabilityTag.group`; users cannot choose it.
- `coordination_ui.dart` remains unchanged because its colours describe status.
- Outer card rows, slots, chip heights, wrapping, and spacing remain unchanged.

### 5.2 Palette

| Group | Light container | Light on | Dark container | Dark on |
| --- | --- | --- | --- | --- |
| logistics | `#EEF2FF` | `#3730A3` | `#252F4A` | `#A5B4FC` |
| communication | `#ECFEFF` | `#155E75` | `#16323C` | `#67E8F9` |
| knowledge | `#F5F3FF` | `#5B21B6` | `#2A2647` | `#C4B5FD` |
| care | `#FDF4FF` | `#86198F` | `#3A1F3F` | `#F0ABFC` |
| resources | `#F0FDFA` | `#115E59` | `#123832` | `#5EEAD4` |
| technical | `#F5F5F4` | `#44403C` | `#292524` | `#D6D3D1` |
| special | `#F1F5F9` | `#475569` | `#273240` | `#CBD5E1` |

### 5.3 Verified contrast wording

Against the plan's containers and live light/dark surfaces, every pair clears
WCAG AA text contrast. Dark logistics is 6.65:1, light communication is
6.99:1, and light special is 6.92:1; those three must not be called AAA.
All other measured pairs are at least 7:1. Store the ratio fixture inputs in
`capability_group_palette_test.dart` so future palette edits recalculate rather
than copy prose.

### 5.4 Design-system API and exact consumers

Add:

```text
packages/client/lib/design_system/tentura_capability_colors.dart
packages/client/lib/design_system/components/tentura_capability_glyph.dart
packages/client/lib/design_system/components/tentura_identity_tile_frame.dart
```

`TenturaCapabilityColors` is a `ThemeExtension` containing one
`CapabilitySwatch(container,onContainer)` per group, with complete `copyWith`
and `lerp`. Its named context extension is fail-fast:

```dart
extension TenturaCapabilityColorsX on BuildContext {
  TenturaCapabilityColors get capabilityColors =>
      Theme.of(this).extension<TenturaCapabilityColors>()!;
}
```

Register exact light/dark instances in `TenturaTheme.light()` and `.dark()`.
Fix `TenturaResponsiveScope` by preserving every extension except the old
`TenturaTokens`, then appending its window-class-adjusted tokens:

```dart
extensions: <ThemeExtension<dynamic>>[
  ...theme.extensions.values.where((value) => value is! TenturaTokens),
  tokens,
],
```

`TenturaIdentityTileFrame` owns square constraints, `size * 0.2` radius,
clipping, the `outlineVariant` border, and the common semantics wrapper.
`BeaconIdentityTile` supplies only photo/symbol/neutral content.
`TenturaCapabilityGlyph` owns the square tinted glyph treatment and uses an
inner icon of `size * 0.52`.

Edit these direct renderers:

- `packages/client/lib/ui/widget/beacon_requirements_bar.dart`: keep its current
  outer icon slot and row height; place the group on-colour in the existing
  slot without changing wrapping;
- `features/capability/ui/widget/capability_requirement_tags.dart`: preserve
  tag height and spacing; tint the existing tag container;
- `features/capability/ui/widget/capability_tag_chip.dart`: tint the whole
  `FilterChip`; do not nest a square that changes chip height;
- `features/capability/ui/widget/forward_capability_chips.dart` and
  `removable_capability_chips.dart`: preserve 14 px and 18 px icon slots and
  tint their existing chip containers;
- `features/forward/ui/widget/forward_recipient_row.dart`: preserve the current
  recipient-row icon slot;
- `features/beacon_room/ui/widget/room_message_tile.dart`: preserve the current
  compact capability icon geometry.

Do not edit `features/beacon/ui/widget/coordination_ui.dart`,
`features/forward/ui/widget/compact_beacon_context_strip.dart`,
`features/capability/ui/widget/network_person_card.dart`,
`features/forward/ui/widget/forward_recipient_picker.dart`, or
`features/beacon_view/ui/dialog/help_offer_message_dialog.dart` merely because
they reference capabilities; they delegate to the direct renderers above or
use semantic colours.

---

## 6. Ten independently gated implementation steps

Each step is one reviewable commit and must pass its gate before the next
commit. Deployment happens at the explicit packet boundaries; a merged PR is
not itself a mixed-binary safety mechanism.

### Step 1 — shared contracts (`feat(root):`)

Files:

- add `lib/domain/capability/capability_slugs.dart`;
- add `lib/domain/entity/beacon_cover_source.dart`;
- export both from `lib/domain.dart`;
- change
  `packages/server/lib/domain/capability/capability_tag.dart` to the shared
  adapter;
- add
  `packages/client/test/domain/capability/capability_slug_order_test.dart` and
  the server equivalent.

The tests assert all 37 exact slugs, client enum order, server allowed set,
seven groups, canonical-first behavior, and explicit wire parsing. Search all
`kAllowedCapabilitySlugs` uses because it is no longer a `const Set`.

Gate:

```bash
(cd packages/server && dart test -x pg)
(cd packages/client && flutter test test/domain/capability/capability_slug_order_test.dart)
./scripts/check-custom-lints.sh packages/server
./scripts/check-custom-lints.sh packages/client
```

### Step 2 — capability design system, no feature behavior change (`feat(design-system):`)

Files:

- add the three design-system files in §5.4;
- update `tentura_theme.dart`, `tentura_responsive_scope.dart`, and
  `tentura_design_system.dart`;
- update only the direct renderers listed in §5.4;
- add `capability_group_palette_test.dart`,
  `capability_colour_surfaces_test.dart`, and
  `theme_extension_composition_test.dart`.

The composition test mounts the actual `TenturaTheme` plus
`TenturaResponsiveScope` for light/dark and compact/medium/expanded. It asserts
exact expected swatches, not merely non-null access. Surface tests assert
unchanged outer geometry and semantic coordination colours.

Gate:

```bash
(cd packages/client && flutter test \
  test/design_system/capability_group_palette_test.dart \
  test/design_system/capability_colour_surfaces_test.dart \
  test/design_system/theme_extension_composition_test.dart)
./scripts/check-custom-lints.sh packages/client
```

Before approval, capture the same 20-card Inbox fixture in light and dark and
verify the tint does not become a second status channel.

### Step 3 — additive database schema (`feat(server):`)

Files:

- add and register `m0130.dart`;
- add the three columns while retaining legacy columns in `table/beacons.dart`;
- add `table/beacon_image_stages.dart` and `table/image_object_gcs.dart`;
- register both in `tentura_db.dart`;
- add
  `packages/server/test/data/database/beacon_cover_migration_test.dart`.

Run server code generation. The migration test covers a fresh schema and a
populated m0129 fixture: canonical primary backfill, deterministic cover,
dense positions, unique `image_id`, composite membership rejection, targeted
`SET NULL`, deferrable full reorder, and both new tables. The pg-tagged test
must execute on PostgreSQL; an SQLite-only migration test is insufficient.

Gate:

```bash
(cd packages/server && dart run build_runner build -d && dart test -x pg)
(cd packages/server && dart test -t pg test/data/database/beacon_cover_migration_test.dart)
./scripts/check-custom-lints.sh packages/server
```

At this point old server code still compiles because both legacy columns remain.
Do not deploy Step 3 without the additive server in Deployment Packet A.

### Step 4 — server entities, ports, repositories (`feat(server):`)

Files:

- add new fields while retaining legacy fields in
  `domain/entity/beacon_entity.dart`;
- extend `domain/port/beacon_repository_port.dart` additively;
- add `domain/port/image_object_gc_port.dart`;
- add `data/repository/image_object_gc_repository.dart`;
- update `data/repository/beacon_repository.dart`,
  `image_repository.dart`, `mock/beacon_repository_mock.dart`, and
  `data/mapper/beacon_mapper.dart`;
- register implementations in the existing server DI module;
- regenerate all Mockito outputs that mention changed ports.

Repository media primitives require an already-held beacon lock; use cases own
authorization and orchestration. `ImageRepository.deleteOwnedRow` includes both
image ID and author ID and returns the affected-row count. `put` implements the
compensation in §3.4. The GC repository implements the exact lease predicates.

Gate:

```bash
(cd packages/server && dart run build_runner build -d && dart test -x pg)
./scripts/check-custom-lints.sh packages/server
```

### Step 5 — server use cases and additive GraphQL (`feat(server):`)

Files:

- update `domain/use_case/beacon_case.dart` with strict primary validation,
  staging, reconciliation, hardened legacy mutations, and fork behavior;
- update `domain/use_case/user_case.dart` so account-image removal writes the
  same transactional GC outbox before deleting image rows;
- update `domain/use_case/task_worker_case.dart` with GC and stage-expiry
  sweeps;
- append codes in `domain/exception_codes.dart` and add classes in
  `domain/exception.dart`;
- update/add the GraphQL files in §3.6;
- add only the three new beacon columns to `hasura/metadata.json`;
- add server tests listed in §9.2.

**Create and fork cleanup.** The legacy `beaconCreate(image: ...)` path and
`fork` may upload objects before their final beacon/attachment transaction. On
any later failure, catch outside that rolled-back transaction and compensate
every uploaded ID in a new transaction. Fork copies source images in source
order, maps the source cover to the corresponding new ID, creates the beacon
with null cover, inserts attachments, and sets the mapped cover last in the same
locked transaction. When source images are not authorized to copy, fork sets
cover null.

**Primary compatibility.** Old mutations that omit `primaryNeedSlug` derive it
from the submitted needs. New mutations that explicitly supply a value are
strict. Continue reading/writing legacy icon arguments for old clients, but
they no longer affect resolved identity.

Gate:

```bash
(cd packages/server && dart run build_runner build -d && dart test -x pg)
(cd packages/server && dart test -t pg \
  test/data/database/beacon_cover_migration_test.dart \
  test/data/repository/image_object_gc_repository_test.dart)
./scripts/check-custom-lints.sh packages/server
```

**Deployment Packet A.** Deploy Steps 1, 3, 4, and 5 together with `m0130`.
Step 2 is client-only and may already be merged. Keep a rollback-capable old
server binary: `m0130` is additive and still has its columns.

### Step 6 — remote-schema reload and generated client bridge (`feat(client):`)

With the additive server running:

1. apply `hasura/metadata.json`;
2. reload remote schema `tentura` using the exact command in §11;
3. run the old-client GraphQL compatibility fixture;
4. run `docker compose run --rm schema_fetcher`;
5. add Ferry documents:
   `beacon_stage_image.graphql` and `beacon_set_media.graphql`;
6. update create/update/draft/add documents additively; keep legacy selections
   in the generated schema until Step 9;
7. add `BeaconStageImage` and `BeaconSetMedia` to
   `_tenturaDirectOperationNames`;
8. regenerate Ferry output without hand-editing generated files.

Client `BeaconRepository` gains additive methods but existing call paths remain
unchanged in this step. Add
`test/data/service/remote_api_client/direct_operation_routing_test.dart` and
`test/features/beacon/data/additive_graphql_contract_test.dart`.

Gate:

```bash
(cd packages/client && flutter gen-l10n && dart run build_runner build -d)
(cd packages/client && flutter test \
  test/data/service/remote_api_client/direct_operation_routing_test.dart \
  test/features/beacon/data/additive_graphql_contract_test.dart)
./scripts/check-custom-lints.sh packages/client
```

### Step 7 — client identity and display projection (`feat(client):`)

Files:

- add `domain/entity/beacon_cover.dart`;
- update `domain/entity/beacon.dart` and `image_entity.dart`;
- update the client model/mapper for the three additive fields while retaining
  legacy fields;
- update `ui/widget/beacon_identity_tile.dart` to use
  `TenturaIdentityTileFrame` and `resolveIdentity`;
- update all projection consumers in §4.3;
- update Inbox, My Desk, graph, and detail call sites to use
  `BeaconIdentityTile`;
- add domain, widget, gallery, and active golden tests in §9.3-§9.5.

The image-error branch renders `resolveIdentity(allowPhoto: false)`. An
unreadable cached/synthetic entity is neutral before any title/capability/photo
semantics are constructed.

Gate:

```bash
(cd packages/client && flutter test \
  test/domain/beacon_identity_resolution_test.dart \
  test/ui/widget/beacon_identity_tile_test.dart \
  test/ui/widget/beacon_image_gallery_test.dart)
./scripts/check-custom-lints.sh packages/client
```

### Step 8 — create/edit use case and UI (`feat(client):`)

Files:

- add both domain ports, commands/results/failures, and
  `BeaconCreateCase` from §4.4;
- make the two data repositories implement the ports;
- update GetIt/injectable registration and regenerate it;
- update `beacon_create_state.dart` with `primaryNeedSlug`, `coverKey`, and
  `coverSource`;
- rewrite `beacon_create_cubit.dart` to inject only the case;
- update `info_tab.dart`, `image_tab.dart`, and add
  `cover_symbol_sheet.dart`;
- add required English/Russian localization keys and generate them;
- add the create/edit tests in §9.3-§9.4.

`cubit_requires_use_case_for_multi_repos` is already enabled and passing for this
cubit, so keep the case-only injection — reintroducing a second repository will
fail `dart analyze` outright (the rule reports at error severity). The
custom-lint count may fall; it must not rise above 115.

Gate:

```bash
(cd packages/client && flutter gen-l10n && dart run build_runner build -d)
(cd packages/client && flutter test \
  test/features/beacon_create/beacon_create_case_test.dart \
  test/features/beacon_create/beacon_create_cover_test.dart \
  test/features/beacon_create/cover_block_test.dart \
  test/features/beacon_create/image_tab_cover_test.dart)
./scripts/check-custom-lints.sh packages/client
```

### Step 9 — client legacy cleanup, end-to-end verification, and bake (`refactor(client):`)

Execute §8 client cleanup. Run all client tests, active goldens, and the named
web integration test. Deploy the new web client and release the native client.
During the agreed bake window, record:

- server/version distribution;
- calls using legacy icon arguments;
- legacy `beaconAddImage`, `beaconRemoveImage`, and
  `beaconReorderImages` usage;
- stage counts/age, reconciliation failures, GC retries, and terminal GC rows;
- client error rate for stage/media operations.

Rollback during this window means roll back the client or additive server code;
do not reverse `m0130`, and do not apply `m0131`.

Gate: all of §11 except the final dead-legacy source grep is green, telemetry
dashboard exists, and old-client compatibility remains green.

### Step 10 — gated forward-only contraction (`refactor(server):`)

> **RELEASE-OWNER SIGN-OFF RECORDED — 2026-07-25.** The repository owner
> (V.G. Bulavintsev) confirmed in writing: there are **no users on production**,
> and destructive changes to content during migrations are **authorized**. This
> discharges gates 1–5 below, which existed only to establish that fact. Step 10
> is therefore unblocked; proceed with the forward-only contraction.
>
> The one thing this sign-off does *not* waive: the step must still leave every
> gate in §11 green. A destructive migration being authorized is not permission
> to land a red test suite.

Before editing code or creating `m0131`, attach all evidence to the release
ticket:

1. production-labeled SQL counts for users, beacons, legacy-icon values,
   duplicate image attachments, invalid primary state, and invalid cover state;
2. same-day release-owner written confirmation that no real-user onboarding has
   begun and discarding the remaining legacy icon values is authorized;
3. native/web supported-version policy says old binaries are outside the
   compatibility window;
4. telemetry shows zero legacy icon arguments and zero legacy media mutation
   use for the full bake window;
5. additive server rollback artifact and database backup are recorded.

If any item fails, stop. Keep the additive fields and columns. If real users
exist, replace this step with a data-preserving migration reviewed separately.

After all gates pass:

- remove legacy icon arguments/output fields from server GraphQL;
- remove legacy fields from server entity, port, mapper, repository, mocks, and
  Drift table;
- remove legacy Hasura permission columns without reordering other columns;
- add/register `m0131` exactly as §3.2;
- regenerate server and client schema/code;
- reload Hasura remote schema and fetch schema again;
- run all §11 commands, including the zero-match dead-reference gate.

Deploy `m0131` and the contracted server together. This is a forward-only
activation; do not claim rollback to a legacy server is possible afterward.

---

## 7. UI states and persistence sequences

### 7.1 Request cover block

`info_tab.dart` adds a “Request cover” block inside its existing `ListView`.
At compact width it stacks preview/control; at wider widths it uses a 56 px
preview, text column, and trailing segmented control. It uses design-system
spacing and typography only.

| Persisted/UI state | Preview | Helper/control |
| --- | --- | --- |
| no photos, no capabilities, photo preference | neutral | Photo selected; tapping opens picker. Symbol disabled with “Add a capability first.” |
| no photos, valid primary, photo preference | primary symbol | Photo remains selected; “No cover photo yet — showing {capability} symbol.” |
| valid primary, symbol preference | primary symbol | Symbol selected and localized capability label shown. |
| photos, photo preference | selected photo | Photo selected; tap preview chooses/replaces cover. |
| photos, symbol preference | primary symbol or neutral | Symbol selected; stored photo selection remains available. |
| unreadable cached entity | neutral | No photo/capability text leaks. |

The control is bound to `state.coverSource`, never to resolved identity.

### 7.2 Symbol sheet

`cover_symbol_sheet.dart` lists only capabilities already in `state.needs`,
in canonical order, using localized labels and the group swatch. Selecting one
sets primary and symbol preference. If needs is empty, show the neutral preview
and a “Manage capabilities” action; do not offer the global catalog.

### 7.3 Image tab

Every image uses `ImageEntity.key`. Mark the selected cover with a semantic
label/check overlay that does not rely on colour. Tapping “Use as cover” sets
`coverKey` and photo preference. Reorder changes list order, not identity.
Deleting the cover selects the first remaining image by current list order;
deleting the last image clears `coverKey` but leaves persisted photo preference.

### 7.4 State transitions

| Event | Required transition |
| --- | --- |
| add first local image | assign UUID `localKey`, select it as cover, keep current source unless user explicitly chose symbol |
| add later image | append; do not change selected cover |
| choose photo | require an image or open picker; set `coverSource.photo` |
| choose symbol | require a valid primary; set `coverSource.symbol`, keep `coverKey` |
| choose primary | require slug in needs; set primary and symbol source |
| remove primary capability | promote canonical-first remaining slug |
| clear needs | clear primary; symbol resolves neutral |
| delete selected image | select first remaining image; clear when empty |
| clear all images | clear cover key; do not rewrite photo preference |
| begin crop local image | crop its local bytes |
| begin crop server image | call existing `fetchImageBytes`; on fetch failure show error and preserve state |
| cancel crop | preserve original image, cover key, and source exactly |
| accept crop | replace image with a new local-key entry at the same position; if it was cover, repoint cover key to replacement |
| stage succeeds | replace only that local-key entry with returned exact image ID |
| save fails after partial staging | emit progressed image list from `BeaconSaveFailure`; keep form editable/retryable |
| save succeeds | replace state with returned server entity and clear transient errors |

### 7.5 Separate persistence sequences

**Create.**

1. `BeaconCreateCase.create` sends fields with `image: null`, needs, and primary;
   receives beacon ID.
2. Stage each local image against that ID, replacing local keys with exact IDs.
3. Call one `beaconSetMedia` with the complete ordered ID list, selected cover
   ID, and source.
4. If field create succeeds but media fails, the Request exists with no partial
   attachments. Keep the ID and progressed images in state; retry starts at
   step 2/3, not a second create.

**Draft save.** Update draft fields first, stage local images, then reconcile
once. Existing attachments stay visible until reconciliation commits.

**Published edit.** Update fields first, stage local replacements, then
reconcile once. Other clients may observe the new fields before final media
state (D-8), but never individual uploaded attachments or transient reorder.

**Retry.** Reuse every known staged/attached ID in progressed state. Re-upload
only entries still identified by `localKey`. A repeated `beaconSetMedia` is
idempotent. Unused prior stages are deleted by the successful reconciliation.

**Stage expiry.** If retry occurs after a 24-hour stage expired, the server
rejects the missing ID. Refetch the beacon, convert only the expired local
source (if still available) to a new stage, and retry. Never infer which stage
expired from position.

**Crop replacement.** Accepting crop creates a new local image and omits the
old server image from desired IDs. The reconciliation admits the replacement,
detaches the old image, and enqueues its object for GC in one transaction.

### 7.6 Responsive and accessibility constraints

- `BeaconIdentityTile` is exactly 40×40 in Inbox/My Desk cards, 32×32 where the
  current detail app bar uses 32, and 56×56 only in the form preview.
- Preserve `BeaconCardHeaderRow` fixed menu slot, title gap, narrow
  `omitFixedChrome` behavior, row height policy, and requirements wrapping.
- Test widths 320, 360, 412, 600, 840, 1024, and 1600; landscape 740×360; text
  scales 1.0, 1.3, and 2.0.
- Tile semantics retain the Request title. Symbol identity appends the localized
  capability label. Capability chips retain label/tooltips; colour is never the
  only signal.
- Image errors do not cause layout shift. Set decode cache dimensions from tile
  size and device pixel ratio without changing layout constraints.

---

## 8. Legacy removal map

### 8.1 Client cleanup in Step 9

After all new client paths use the additive fields:

1. remove `iconCode`, `iconBackground`, and legacy identity helpers from the
   client `Beacon` and generated model mapping;
2. remove icon variables/selections from create/update/draft GraphQL documents;
3. delete `packages/client/lib/domain/entity/beacon_identity_catalog.dart`;
4. delete the old icon picker widgets/branches from `info_tab.dart`;
5. delete or rewrite
   `packages/client/test/domain/beacon_identity_catalog_test.dart`,
   `beacon_icon_picker_preview_test.dart`, and affected parts of
   `info_tab_picker_tap_test.dart`;
6. remove obsolete catalog localization keys from both ARB files;
7. migrate all `imageUrl`/parallel `imageUrls` consumers to the ordered
   projection before deleting old aliases;
8. regenerate localization and Ferry/freezed output.

Do not remove server GraphQL fields or database columns in this step. Old
server compatibility remains the rollback boundary during the client bake.

### 8.2 Server cleanup in Step 10

After the contraction gate:

1. remove legacy entity/port/repository/mapper/mutation fields;
2. remove legacy columns from Drift table and Hasura permission metadata;
3. remove legacy mock expectations and regenerate all server mocks;
4. apply `m0131`;
5. reload/fetch schema and regenerate client schema output;
6. run the zero-match source grep in §11.

Keep historical `m0030.dart` and Appendix A unchanged.

---

## 9. Mandatory test matrix

### 9.1 Shared and design-system tests

| File | Mandatory assertions |
| --- | --- |
| `packages/client/test/domain/capability/capability_slug_order_test.dart` | exact 37 slugs/order; seven groups; client labels/icons still map |
| server shared-contract test | same canonical order/set and cover wire values |
| `test/design_system/capability_group_palette_test.dart` | exact light/dark constants; recalculated contrast thresholds and corrected AAA wording |
| `test/design_system/theme_extension_composition_test.dart` | exact swatch under real light/dark theme × three responsive classes; failure when extension absent |
| `test/design_system/capability_colour_surfaces_test.dart` | direct renderers use group swatch; chip/row/slot geometry unchanged; coordination semantic colours unchanged |

### 9.2 Server tests

Add or extend:

- `beacon_cover_migration_test.dart`: fresh and populated upgrade, every
  backfill/constraint/index/table in Step 3;
- `beacon_cover_sql_pg_test.dart`: actual PostgreSQL targeted `SET NULL`,
  circular delete, composite FK, and deferrable reorder;
- `beacon_case_media_test.dart`: unauthorized add/stage before upload; owner
  recheck under lock; same-author image attached to another beacon; unknown ID;
  duplicate/cap/cover/source failures and exact codes; invisible staging;
  atomic reconcile; dense order; idempotent retry; concurrent legacy add versus
  reconcile; expiry versus reconcile;
- `image_repository_compensation_test.dart`: remote `put` failure, partial
  object failure, stage transaction rollback, and non-fatal post-commit hash
  scheduling;
- `user_case_image_gc_test.dart`: account deletion enqueues every owned object
  in the same transaction and never calls MinIO before commit;
- `image_object_gc_repository_test.dart`: two claimers, `SKIP LOCKED`,
  owner-checked complete/fail, expired lease recovery, backoff, attempt 10
  retention, and missing-object success;
- `beacon_case_create_media_cleanup_test.dart`: legacy create upload followed by
  database failure cleans in a new transaction;
- `beacon_case_fork_media_test.dart`: ordered copied IDs, mapped cover,
  unauthorized no-copy behavior, mid-copy failure, and final transaction
  rollback cleanup;
- GraphQL schema tests: old documents validate; actual list/upload/int
  introspection; missing list rejected; new payload IDs; numeric error codes.

Run concurrency/constraint tests with the `pg` tag against the repository
PostgreSQL image.

### 9.3 Client domain/use-case tests

- `beacon_identity_resolution_test.dart`: full truth table for source, valid or
  stale cover, valid/unknown/not-in-needs primary, empty needs, photo disabled,
  and unreadable state;
- `beacon_cover_key_resolution_test.dart`: local/server key replacement never
  uses positions;
- `beacon_display_images_test.dart`: non-first cover, missing cover, symbol
  source, URL/object alignment, viewer initial index and counter;
- `beacon_create_case_test.dart`: separate create/draft/edit calls, first image
  no longer implicit, partial stage progress, retry reuse, expired-stage
  recovery, omitted IDs, and exactly one reconciliation;
- architecture test/custom lint: `BeaconCreateCubit` has no concrete repository
  imports/fields and injects only `BeaconCreateCase`.

### 9.4 Widget and routing tests

- `beacon_identity_tile_test.dart`: photo/symbol/neutral/error/unreadable,
  exact 40×40, same frame geometry and semantics;
- `beacon_create_cover_test.dart`, `cover_block_test.dart`,
  `cover_symbol_sheet_test.dart`, `image_tab_cover_test.dart`: §7 states and
  transitions, persisted-control behavior, manage-capabilities escape, crop
  cancel/fetch failure/replacement;
- existing gallery test: same ordered image/URL at every page and viewer launch;
- direct-operation routing test: stage/media direct V2, no `beaconSetCover`;
- additive GraphQL contract test: old documents plus new documents against the
  additive schema fixture;
- card layout tests: compact/expanded, all identity branches, text scale 2.0,
  menu slot and requirements row unchanged.

### 9.5 Active goldens

Create active standalone
`packages/client/test/golden/beacon_cover_identity_golden_test.dart`; do not add
cases to the skipped typography group. Cover:

- photo/symbol/neutral in light/dark at 32, 40, and 56 px;
- Inbox and each My Desk card variant at 320, 700, and 1200 px;
- the cover form at compact and expanded widths and text scale 2.0;
- the seven capability groups in light/dark.

Regenerate only this file's goldens and inspect every PNG before accepting.

### 9.6 Web integration

Add
`packages/client/integration_test/request_lifecycle_beacon_cover_test.dart` and
run it with `scripts/run_client_integration_web_local.sh`. It must:

1. create a Request with two staged photos and a primary capability;
2. prove no attachment is visible before reconciliation;
3. publish and verify photo identity in detail, Inbox, and My Desk;
4. switch to symbol and verify realtime repaint on a second client;
5. remove the primary and verify canonical promotion;
6. crop/replace the selected server photo and verify aligned gallery/viewer;
7. simulate one failed stage then retry without duplicate attachments;
8. delete the cover and verify deterministic remaining cover;
9. verify an unreadable/tombstone presentation leaks no capability or photo.

---

## 10. Acceptance checklist

- [ ] Every Step 1-10 gate passed before its commit.
- [ ] `m0130` upgrade fixture and PostgreSQL syntax/constraint tests passed.
- [ ] Old client documents worked against the additive server after Hasura
      reload.
- [ ] No upload occurred before the first owner check; every publication
      rechecked owner under lock.
- [ ] No remote object deletion occurred before database commit.
- [ ] Dual-worker GC and crash recovery tests passed.
- [ ] Create, draft, edit, retry, expiry, crop replacement, legacy create, and
      fork cleanup sequences passed.
- [ ] Identity error and unreadable paths use the single resolver.
- [ ] Gallery image/URL/index/counter stayed aligned.
- [ ] Exact light/dark capability extension survived all responsive classes.
- [ ] Inbox/My Desk external geometry and semantic coordination colours stayed
      unchanged.
- [ ] Active target goldens and named web integration passed.
- [ ] Step 9 bake evidence exists.
- [ ] Step 10 production counts and same-day release-owner authorization exist,
      or contraction was skipped.
- [ ] Appendix A hash remained unchanged.

---

## 11. Verification commands

Run from the repository root in this order. Subshells preserve the root working
directory.

```bash
tentura_repo_root="$(git rev-parse --show-toplevel)"

# 1. Generate first. Never hand-edit generated files.
(cd "$tentura_repo_root/packages/server" &&
  dart run build_runner build -d)
(cd "$tentura_repo_root/packages/client" &&
  flutter gen-l10n &&
  dart run build_runner build -d)

# 2. Custom-lint behavior and package-root gates.
(cd "$tentura_repo_root/packages/tentura_lints" && dart test)
(cd "$tentura_repo_root" &&
  ./scripts/check-custom-lints.sh packages/server &&
  ./scripts/check-custom-lints.sh packages/client)

# 3. Server tests. The pg command requires the local stack.
(cd "$tentura_repo_root/packages/server" && dart test -x pg)
(cd "$tentura_repo_root/packages/server" && dart test -t pg)

# 4. Hasura additive/final schema sequence with the new server running.
(cd "$tentura_repo_root" && bash scripts/hasura_apply_metadata.sh)
curl -sS -X POST http://localhost:8080/v1/metadata \
  -H "X-Hasura-Admin-Secret: password" \
  -H "Content-Type: application/json" \
  -d '{"type":"reload_remote_schema","args":{"name":"tentura"}}'
(cd "$tentura_repo_root" && docker compose run --rm schema_fetcher)

# 5. Client tests and active targeted goldens.
(cd "$tentura_repo_root/packages/client" && flutter test)
(cd "$tentura_repo_root/packages/client" &&
  flutter test --update-goldens \
    test/golden/beacon_cover_identity_golden_test.dart)

# Inspect and accept only the intended new/changed PNGs, then rerun without
# --update-goldens.
(cd "$tentura_repo_root/packages/client" &&
  flutter test test/golden/beacon_cover_identity_golden_test.dart)

# 6. Named web integration.
(cd "$tentura_repo_root" &&
  ./scripts/run_client_integration_web_local.sh \
    integration_test/request_lifecycle_beacon_cover_test.dart)

# 7. Generation must now be clean in both packages.
(cd "$tentura_repo_root" &&
  git diff --exit-code -- packages/server packages/client)

# 8. Final contraction source gate: zero matches. Historical migration and
# this plan are intentionally outside the searched paths.
if rg -n \
  'icon_code|iconCode|icon_background|iconBackground|BeaconIdentityCategory|kBeaconIdentityPalette|kBeaconIdentityIcons|beaconSetCover' \
  "$tentura_repo_root/packages/client/lib" \
  "$tentura_repo_root/packages/server/lib" \
  "$tentura_repo_root/hasura/metadata.json" \
  --glob '!**/data/database/migration/m0030.dart'; then
  exit 1
fi

# 9. Generated GraphQL/mocks must not retain legacy API.
if rg -n \
  'icon_code|iconCode|icon_background|iconBackground|beaconSetCover' \
  "$tentura_repo_root/packages/client/lib" \
  "$tentura_repo_root/packages/server/test" \
  --glob '**/*.g.dart' --glob '**/*.freezed.dart' \
  --glob '**/*.mocks.dart' --glob '**/schema.graphql'; then
  exit 1
fi

# 10. Terminology and whitespace.
(cd "$tentura_repo_root" &&
  bash scripts/check-user-facing-terminology.sh &&
  git diff --check)
```

If the integration runner does not accept a positional test path, add the named
test to its existing suite selection and run the unparameterized script; do not
silently replace it with a different test. The final `git diff --exit-code`
assumes implementation changes have been committed stepwise as this plan
requires.

---

## 12. Risks and stop conditions

| ID | Risk | Mitigation/stop condition |
| --- | --- | --- |
| RK-1 | Capability hues become a second semantic status system. | Only tint capability containers/glyphs; preserve coordination/status colours; review dense light/dark fixtures. |
| RK-2 | Photo thumbnails at 40 px are less scannable than symbols. | Accepted by D-2; author-controlled crop and identical frame geometry mitigate it. |
| RK-3 | A staged object leaks after failure. | `put` compensation, post-rollback compensation, 24-hour stage expiry, leased GC, and terminal-row operations query. |
| RK-4 | Two workers delete/retry the same object. | `FOR UPDATE SKIP LOCKED`, lease owner predicates, expiry recovery, and idempotent missing-object success. |
| RK-5 | Field save succeeds while media reconciliation fails. | This is D-8. Stages remain invisible, attachments remain at the prior valid state, progressed state supports retry. |
| RK-6 | Old clients stop saving during rollout. | Preserve old fields/arguments/mutations, smoke old documents after Hasura reload, and do not contract until telemetry gate. |
| RK-7 | Old server rollback fails after column removal. | `m0131` is explicitly forward-only and only follows the Step 10 gate. Before it, `m0130` remains rollback-compatible. |
| RK-8 | Production has real users or duplicate image ownership. | Stop contraction/migration at the preflight. Design a data-preserving migration; never delete or assign ownership by guess. |
| RK-9 | A weaker implementer normalizes invalid command input. | §3.5 names exact strict exceptions; tolerance exists only in `resolveIdentity` read rendering. |
| RK-10 | Generated schema masks an incorrect GraphQL contract. | Assert introspection before fetch, reload Hasura first, generate in its own step, and run old/new contract fixtures. |

## Appendix A — original critic review (all findings resolved in rev 2)

Reviewed against the live tree on 2026-07-25. Kept verbatim for traceability; see §0 for where
each one is answered.

### CR-1 — Blocking: image mutations retain authorization and membership flaws

* `BeaconCase.addImage` performs the upload, schedules work, and inserts the `beacon_image` row
  before its final owner-filtered beacon read. An unauthorized request can therefore mutate
  another user's beacon before the read throws.
* `BeaconCase.removeImage` verifies ownership of the beacon but never verifies that `imageId`
  belongs to that beacon.
* `ImageRepository.delete` deletes the `image` row by UUID only. Its `authorId` argument is used to
  construct the object-storage path, not to constrain the SQL delete. A known image UUID can
  therefore delete an unrelated image and cascade through its relationships.

C1/C2 must not be implemented on top of these semantics. Each mutation must authorize the actor
before any write, lock the beacon, and verify image membership inside the same transaction. Add
negative server tests for: adding an image to another author's beacon; removing another beacon's
image; removing an image owned by the same author but attached to a different beacon; an unknown
image id and a stale attachment.

### CR-2 — Blocking: position-based `localKey → imageId` resolution is invalid

The mapping assumed upload order equals final `beacon_image.position`. That is not true for an edit
containing existing server images, removals, local reordering, and new images interleaved with the
existing rows. The cubit also mutates its local order without persisting that order.

Returning the created image id from `beaconAddImage` is mandatory, not optional hardening. The
client must record the exact returned id against the corresponding `localKey`; it must never infer
identity from a refetched list index. Tests must cover existing + new interleaved images, removal
before upload, reorder before save, crop replacement of an existing server image, and retry after
one upload fails.

### CR-3 — High: the published-edit media workflow has no atomic consistency model

The proposed client flow remained a sequence of independently observable commands (remove, upload,
update fields, set cover). An error in the middle leaves a partially saved edit, and realtime
recipients can observe transient cover promotion. The plan must choose one explicit model:
preferably upload to obtain stable ids, then one beacon-locked reconciliation command; otherwise
document partial-save semantics, idempotency, retry, and realtime ordering. Object-storage deletion
cannot be part of a Postgres transaction — commit the database state first and clean up through a
durable after-commit job/outbox, with tests for cleanup failure and retry.

### CR-4 — High: the database foreign key does not enforce cover membership

`cover_image_id REFERENCES image(id)` proves only that an image exists, not that it is attached to
the same beacon. The schema must enforce
`(beacon.id, beacon.cover_image_id) ∈ (beacon_image.beacon_id, beacon_image.image_id)` via a
composite constraint or a deferred constraint trigger. All cover/add/remove/reorder paths must
serialize through the same beacon-row lock, with concurrency tests. The plan must also define
deterministic ordering for duplicate positions, or prevent duplicates.

### CR-5 — High: `BeaconSetCover` is missing from V2 direct routing

The new operation would be sent to Hasura unless its GraphQL operation name is added to
`_tenturaDirectOperationNames` in
`packages/client/lib/data/service/remote_api_client/build_client.dart`. Add that file to the file
map and a routing contract test.

### CR-6 — High: Steps 3–5 are not independently compilable

Step 3 removed `Beacon.iconCode`, `iconBackground`, `hasIdentityTile` and
`beacon_identity_catalog.dart` while the identity tile, create state, `info_tab` and icon picker
still referenced them. Choose an additive compatibility bridge or one explicitly atomic client
cutover, and give every claimed review unit a concrete compile/test gate. Do not use compiler
failures as the planned discovery mechanism.

### CR-7 — High: `TenturaCapabilityColors` is dropped by the real app theme tree

`TenturaResponsiveScope` calls `theme.copyWith(extensions: [tokens])`, which replaces the extension
list and drops the new extension below the scope. Preserve all non-token extensions. The §3.5
accessor must also be a **named** public extension. Add a widget test under the actual
`TenturaTheme` + `TenturaResponsiveScope` composition, light and dark, all three window classes.

### CR-8 — Medium: canonical capability order is duplicated across packages

N3 is a business invariant, but a second manually synchronized ordered list on the server is not an
architecture boundary, and a client test cannot import the server package. Move the pure ordered
slug list into `tentura_root`, which both packages already depend on; keep `IconData` and localized
labels in the client adapter. Move the pure `BeaconCoverSource` wire contract there too, and do not
persist `enum.index`.

### CR-9 — Medium: cover-first gallery rendering needs one ordered projection

`BeaconImageGallery` and `BeaconGalleryViewer` index `images` and `imageUrls` in parallel.
Replacing one use of `images.first` does not make the cover the first gallery page and can
desynchronize the selected image, URL, aspect ratio, page counter and viewer `initialIndex`. Define
one domain projection and derive every index from it; keep persisted `position` unchanged. Test a
non-first cover, viewer opening from every page, reorder without cover change, and a stale cover id.

### CR-10 — Medium: command validation is mixed with tolerant rendering

N1/N2/N4 silently normalized invalid command input to `NULL` while the file map also proposed a new
exception code. Use strict command validation (unknown slug rejected; primary not in submitted
needs rejected; cover image not attached rejected; unknown `coverSource` rejected) and keep
tolerant fallback only on the read/render side. Test both.

### CR-11 — Medium: the segmented control misrepresents persisted preference

E13 displayed `Symbol` while persisted `cover_source` stayed `photo`, so the next upload could
restore photo mode against what the control showed. Either keep `Photo` selected and explain the
fallback, or normalize the persisted source on removing the last photo. This is a product-state
decision and must be explicit. T3/T15 cancellation wording also contradicted itself, and cropping
an existing server image needs a byte-fetch path with defined failure behaviour.

### CR-12 — Medium: cleanup and verification are incomplete

The removal plan omitted `packages/client/test/domain/beacon_identity_catalog_test.dart`, the
generated server Mockito mocks affected by the changed `BeaconRepositoryPort`, explicit
`build_runner` commands before tests, and a verification step proving no stale generated GraphQL or
mock API remains. Run the dead-reference grep only after code generation. E9 must also be reworded:
the Hasura permission filters out the entire beacon row when `can_read_content` is false; it does
not selectively drop content columns.
