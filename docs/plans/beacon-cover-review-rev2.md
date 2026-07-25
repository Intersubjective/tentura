# Hostile review: `beacon-cover-and-capability-color-plan.md` revision 2

Reviewed from scratch against the live tree on 2026-07-25. PostgreSQL claims
were also exercised against the repository image
`vbulavintsev/postgres-tentura:v0.8.0`; `postgres --version` reports 17.9.
Claims not called out below were rechecked and found consistent with the live
tree. Findings are ordered by execution risk, not by plan section.

1. **Blocking — CR2-1: the claimed additive server bridge cannot compile after
   Step 3.**

   **Claim or gap.** Revision 2 removes `iconCode` and `iconBackground` from the
   Drift `Beacons` table and runs code generation in Step 3, while deferring the
   repository, domain, mapper, use-case, and GraphQL changes to Steps 4 and 5.
   The Step 3 `dart test -x pg` gate therefore cannot pass.

   **Evidence checked.** The columns are declared in
   `packages/server/lib/data/database/table/beacons.dart:44-48`. Generated
   companion arguments are still used by all three repository write paths in
   `packages/server/lib/data/repository/beacon_repository.dart:66-85`,
   `:184-205`, and `:246-267`. The legacy fields remain required by
   `packages/server/lib/domain/entity/beacon_entity.dart:15-60`,
   `packages/server/lib/domain/port/beacon_repository_port.dart:5-65`, and
   `packages/server/lib/api/controllers/graphql/mutation/mutation_beacon.dart:20-22,69-103`.

   **Concrete correction required.** Make `m0130` and its Drift table changes
   additive. Retain both legacy columns, domain fields, and GraphQL
   fields/arguments through the server-first and client rollout. Add a final,
   explicitly forward-only `m0131` contraction step that removes the last
   code/metadata references and only then drops the two columns. Every
   intermediate step must compile independently.

2. **Blocking — CR2-2: “one atomic media command” is not the protocol revision 2
   specifies, and the new-client create flow has no executable ID sequence.**

   **Claim or gap.** Revision 2 has the client call `beaconAddImage` for each
   upload before `beaconSetMedia`. Each add commits a visible attachment and can
   change the cover, so observers can see multiple intermediate states. It also
   leaves the current create mutation's implicit first upload active while
   separately adding the remaining images.

   **Evidence checked.** The client sends the first image inside
   `BeaconRepository.create` and uploads images after it in
   `packages/client/lib/features/beacon/data/repository/beacon_repository.dart:125-169`.
   Draft/edit synchronization currently removes and adds images in
   `packages/client/lib/features/beacon_create/ui/bloc/beacon_create_cubit.dart:357-381,601-615`.

   **Concrete correction required.** Add an author-scoped
   `beaconStageImage` operation and a `beacon_image_stage` table. New clients
   create/update fields first, stage uploads without touching `beacon_image`,
   retain every returned image ID, and call one beacon-locked
   `beaconSetMedia`. That mutation must admit attached-or-staged IDs, detach,
   order, select the cover, and discard unused stages atomically. Keep a
   hardened `beaconAddImage` only as the legacy immediate-attach bridge.
   Specify distinct create, draft-update, published-edit, and retry sequences.

3. **High — CR2-3: failed-upload cleanup is placed inside the transaction that
   rolls back, while object deletion still occurs before commit.**

   **Claim or gap.** Revision 2 enqueues GC and deletes an image inside
   `runInBeaconStateTransaction`, then rethrows. Those cleanup writes roll back
   with the failed transaction. Conversely, the existing repository deletes
   the remote object during the database operation, so a later rollback cannot
   restore it. `put` also leaves a database row or partial object when remote
   upload fails.

   **Evidence checked.** `runInBeaconStateTransaction` uses the real Drift
   transaction through `withMutatingUser` in
   `packages/server/lib/data/repository/beacon_repository.dart:280-295` and
   `packages/server/lib/data/database/tentura_db.dart:147-179`.
   `ImageRepository.delete` deletes the row and then the object directly in
   `packages/server/lib/data/repository/image_repository.dart:95-106`.
   `ImageRepository.put` inserts the row before remote upload and has no
   compensating cleanup at
   `packages/server/lib/data/repository/image_repository.dart:48-76`.

   **Concrete correction required.** Make every committed image removal a
   database-row delete plus GC enqueue in the same Drift transaction. Remote
   deletion must occur only in a leased after-commit worker. Harden `put` so a
   failed or partial object upload deletes the known row and enqueues cleanup.
   Catch a failed stage/attach transaction outside the rolled-back callback and
   run compensation in a new transaction. A post-commit blurhash scheduling
   failure must be logged and must not turn a committed upload into a failed
   mutation.

4. **High — CR2-4: the migration creates stale persisted state and treats an
   unverified deployment condition as a timeless fact.**

   **Claim or gap.** Revision 2 adds nullable cover/primary fields without
   backfilling them, so existing rows violate its own canonical-primary and
   cover behavior. It also drops legacy icon data based on “there are no active
   users,” which cannot be established from the repository or a local database.

   **Evidence checked.** Existing image ordering is persisted by the
   `beacon_image` migration in
   `packages/server/lib/data/database/migration/m0029.dart:11-27`. Capabilities
   are stored as comma-separated `beacon.needs` in
   `packages/server/lib/data/database/table/beacons.dart:32-38`. A read-only
   local audit found 573 users, 187 beacons, and six beacons with legacy icon
   values; that looks like QA/seed state but is not production authorization.

   **Concrete correction required.** In `m0130`, backfill
   `primary_need_slug` by the shared canonical order, normalize dense image
   positions, and select the lowest `(position, image_id)` as cover before
   adding constraints. Add a populated m0129-to-m0130 upgrade test. Immediately
   before `m0131`, record production-labeled counts and obtain same-day
   release-owner confirmation that real-user onboarding has not begun. Stop and
   design a data-preserving migration if that authorization is unavailable.

5. **High — CR2-5: deleting an `image` row has wider effects than the beacon
   membership check proves.**

   **Claim or gap.** Revision 2 detaches an image from one authorized beacon and
   deletes the `image` row. The live schema permits the same `image_id` to be
   attached to multiple beacons, so `ON DELETE CASCADE` can silently remove
   another beacon's attachment.

   **Evidence checked.** `beacon_image` is unique only on
   `(beacon_id, image_id)` in
   `packages/server/lib/data/database/migration/m0029.dart:11-21` and
   `packages/server/lib/data/database/table/beacon_images.dart:7-22`.

   **Concrete correction required.** Run a duplicate preflight and add a
   non-deferrable `UNIQUE (image_id)` constraint in `m0130`, matching the
   plan's one-upload/one-beacon ownership model. The current local duplicate
   count is zero. Add tests for duplicate rejection and same-author
   cross-beacon removal. If production duplicates exist, stop rather than
   deleting or guessing ownership.

6. **High — CR2-6: several promised GraphQL signatures cannot be produced by
   the server library as written.**

   **Claim or gap.** Revision 2 specifies a non-null GraphQL list with
   `.nonNullable()`, changes the established upload argument shape, and assumes
   `InputFieldInt` already supports a required scalar. It also fetches the
   client schema without first reloading Hasura's cached remote schema.

   **Evidence checked.** The repository workaround explicitly forbids
   `.nonNullable()` on `GraphQLListType`; list presence is checked in the
   resolver while introspection remains `[String!]` in
   `packages/server/WORKAROUNDS.md:55-86` and
   `packages/server/lib/api/controllers/graphql/input/input_field_image_ids.dart:3-10`.
   Upload currently introspects as `v2_Upload = {}` in
   `packages/server/lib/api/controllers/graphql/input/input_field_upload.dart:3-31`
   and `packages/client/lib/data/gql/schema.graphql:2224-2229`.
   `InputFieldInt` only exposes a nullable field in
   `packages/server/lib/api/controllers/graphql/input/_input_types.dart:117-133`.

   **Concrete correction required.** Publish the executable contract:
   `imageIds: [String!]` with mandatory presence enforced by
   `InputFieldImageIds.fromArgs`; retain the existing `v2_Upload = {}` shape;
   add an explicit non-null scalar field/parser to `InputFieldInt`; list all
   new input/payload helper files and direct-V2 routing tests. Reload the Hasura
   remote schema before `docker compose run --rm schema_fetcher`.

7. **High — CR2-7: adding enum values does not create throwable exception
   types.**

   **Claim or gap.** Revision 2 instructs the use case to throw five new beacon
   invariant failures but edits only `exception_codes.dart`.

   **Evidence checked.** `BeaconCreateException` is hard-wired to
   `beaconCreateException` in
   `packages/server/lib/domain/exception.dart:235-243`; the beacon code range
   currently has four entries in
   `packages/server/lib/domain/exception_codes.dart:72-90`.

   **Concrete correction required.** Append the five codes without reordering
   existing values and add five concrete `ExceptionBase` classes, or one typed
   invariant exception that only accepts those five codes, in `exception.dart`.
   Name the exact class thrown by each validation branch and assert the numeric
   GraphQL error codes in tests.

8. **High — CR2-8: the client identity pseudocode does not compile, and its
   privacy/error tests contradict it.**

   **Claim or gap.** Revision 2 calls APIs that do not exist, does not neutralize
   unreadable cached/synthetic beacons, and asks `Image.network.errorBuilder` to
   reproduce the symbol/neutral half of the identity rule.

   **Evidence checked.** `CapabilityTag` exposes nullable `fromSlug` and
   localized `labelOf`, not `tryFromSlug` or `label`, in
   `packages/client/lib/domain/capability/capability_tag.dart:66-72`.
   `Beacon` already carries `canReadContent` in
   `packages/client/lib/domain/entity/beacon.dart:66-79`.

   **Concrete correction required.** Define exactly one
   `resolveIdentity({required bool allowPhoto})` implementation.
   `identity` calls it with `allowPhoto: true`; an image error calls it with
   `allowPhoto: false`. The method returns neutral before inspecting content
   when `canReadContent == false`, uses `CapabilityTag.fromSlug`, and leaves
   localization to `labelOf`. Add identity truth-table, image-error, and
   unreadable-state privacy tests.

9. **High — CR2-9: the theme-composition test can pass while the capability
   extension is absent, and the identity-frame prescription conflicts with the
   feature lint.**

   **Claim or gap.** Revision 2's context accessor silently falls back to the
   light palette, hiding the exact `TenturaResponsiveScope` bug the test is
   intended to detect. It also prescribes raw calculated radii in feature UI.

   **Evidence checked.** The live responsive scope replaces all theme
   extensions in
   `packages/client/lib/design_system/tentura_responsive_scope.dart:15-32`;
   the base theme registers extensions in
   `packages/client/lib/design_system/tentura_theme.dart:85-93`. Raw
   `BorderRadius` values in the affected feature directories are linted.

   **Concrete correction required.** Make `context.capabilityColors` fail fast
   with `Theme.of(context).extension<TenturaCapabilityColors>()!`. Under the
   real `TenturaTheme` plus `TenturaResponsiveScope`, assert exact light/dark
   swatches in all three window classes. Add a design-system
   `TenturaIdentityTileFrame` that owns square constraints, clipping, border,
   and radius for photo/symbol/neutral branches; feature UI must not recreate
   raw geometry.

10. **High — CR2-10: the GC outbox is unsafe with multiple workers and worker
    crashes.**

    **Claim or gap.** Revision 2 performs an unlocked “due rows” select. Two
    server processes can delete the same object, and a process crash has no
    ownership or recovery protocol.

    **Evidence checked.** `TaskWorkerCase` polls closures in a process-local loop
    in `packages/server/lib/domain/use_case/task_worker_case.dart:74-179`.
    The repository already contains the required lease pattern using
    `FOR UPDATE SKIP LOCKED` in
    `packages/server/lib/data/repository/attention_channel_delivery_repository.dart:22-52,68-94`.

    **Concrete correction required.** Add `lease_owner`, `lease_until`,
    `next_attempt_at`, and attempt/error fields. Atomically claim rows with
    `FOR UPDATE SKIP LOCKED`, increment attempts on claim, complete/fail only
    when `lease_owner` matches, and reclaim expired leases. Put these methods on
    a narrow `ImageObjectGcPort`, not the already broad image repository port.
    Test two concurrent claimers, wrong-owner completion, crash expiry, retry,
    terminal attempt retention, and idempotent “object missing” success.

11. **Medium — CR2-11: the multi-repository client use case is only a sentence,
    not an executable architecture step.**

    **Claim or gap.** `BeaconCreateCubit` currently injects and coordinates two
    concrete repositories. Merely adding any `*Case` parameter can satisfy the
    syntactic lint while leaving the orchestration and dependencies in the
    cubit.

    **Evidence checked.** The cubit injects both repositories and coordinates
    them at
    `packages/client/lib/features/beacon_create/ui/bloc/beacon_create_cubit.dart:31-62,307-334,357-381`.
    The lint's structural check is in
    `packages/tentura_lints/lib/src/rules/cubit_requires_use_case_for_multi_repos.dart:46-84,111-143`.

    **Concrete correction required.** Define a named `BeaconCreateCase` in the
    domain layer with `BeaconWritePort` and `BeaconImagePort`. Give it exact
    create/draft/edit/stage/reconcile operations. Data adapters implement the
    ports; DI/codegen wires the case; the cubit injects only the case and keeps
    only UI state/effects. Add architecture assertions that no repository field
    or data-layer import remains in the cubit before re-enabling the lint.

12. **Medium — CR2-12: the capability-colour file map and geometry promise do
    not match the actual consumers.**

    **Claim or gap.** Revision 2 lists widgets that only delegate capability
    rendering, includes `coordination_ui.dart` whose colors are semantic status
    colors, omits direct renderers, and simultaneously freezes a 22 px icon
    while prescribing a 22 px outer glyph whose inner icon is `size * 0.52`.

    **Evidence checked.** `coordination_ui.dart` uses semantic coordination
    colors at
    `packages/client/lib/features/beacon/ui/widget/coordination_ui.dart:11-28,51-162,197-205`.
    `compact_beacon_context_strip.dart` delegates to `BeaconRequirementsBar` at
    `packages/client/lib/features/forward/ui/widget/compact_beacon_context_strip.dart:83-129`.
    Direct renderers include `capability_requirement_tags.dart`,
    `capability_tag_chip.dart`, `forward_capability_chips.dart`,
    `removable_capability_chips.dart`, and room-message author icons.

    **Concrete correction required.** List and edit only direct renderers.
    Preserve semantic coordination colors. For each surface prescribe the
    unchanged outer slot/row/chip geometry and the new inner glyph size; on chip
    surfaces tint the whole chip rather than nesting a square. Freeze external
    layout, not the old vector-paint size.

13. **Medium — CR2-13: the required verification commands do not execute in
    the stated order or prove their comments.**

    **Claim or gap.** Sequential relative `cd` commands resolve from the prior
    package, the dead-reference grep does not search the documented archive,
    the stale-generation check omits server output, and the only existing
    golden suite is skipped.

    **Evidence checked.** The skipped golden group is
    `packages/client/test/golden/typography_overhaul_test.dart:117-235`.
    The documented schema fetch and remote-schema reload flow is in
    `DEVELOPMENT.md:178-199`.

    **Concrete correction required.** Use root-preserving subshells; make source
    dead-reference greps require zero matches while separately allowing
    historical migration/archive matches; check generated client and server
    paths; add active, targeted cover goldens rather than claiming the skipped
    suite ran; and spell out Hasura remote-schema reload before schema fetch.

14. **Medium — CR2-14: Section 1 contains stale facts and the test plan omits
    invariants introduced by revision 2 itself.**

    **Claim or gap.** The plan says 36 capability slugs, proposes a byte-fetch
    method that already exists, calls an unsorted Hasura list sorted, describes
    the worker closure incorrectly, and overstates two WCAG ratios. Its tests
    omit migration backfills, additive old-client compatibility, upload
    compensation, stage expiry, dual-worker leases, create/fork cleanup,
    exact theme composition, unreadable/error fallback, gallery index
    alignment, constrained layouts, and a named web integration test.

    **Evidence checked.** There are 37 slugs in
    `packages/client/lib/domain/capability/capability_tag.dart:6-56` and
    `packages/server/lib/domain/capability/capability_tag.dart:1-47`.
    `ImageRepository.fetchImageBytes` already exists in
    `packages/client/lib/data/repository/image_repository.dart:51-70`.
    Hasura's beacon permission columns are not alphabetically sorted at
    `hasura/metadata.json:212-247`. The hash queue closure is not self-throttled
    in `packages/server/lib/domain/use_case/task_worker_case.dart:115-137`.
    The claimed 6.99:1 and 6.92:1 ratios are AA, not AAA.

    **Concrete correction required.** Correct Section 1 and the contrast text.
    Add explicit tests for every omitted case above, including exact file names
    and which rollout gate runs each test.

15. **Medium — CR2-15: the plan has no safe contraction or rollback boundary.**

    **Claim or gap.** Revision 2 removes old GraphQL fields/arguments and
    columns in the initial deployment, claiming one PR solves compatibility.
    Old native/web binaries can still be active, Hasura caches the remote
    schema, and an old server rollback would fail after the column drop.

    **Evidence checked.** Selected client operations route directly to V2 while
    others route through Hasura in
    `packages/client/lib/data/service/remote_api_client/build_client.dart:120-155`.
    Hasura remote-schema caching/reload is documented in
    `DEVELOPMENT.md:187-199`.

    **Concrete correction required.** Prescribe this rollout:
    additive server and `m0130`; Hasura remote-schema reload; old-client
    contract smoke test; new-client rollout and bake; telemetry proving old
    operations are no longer used; fresh release-owner/no-real-user gate; then
    forward-only `m0131`. If any contraction gate is unavailable, retain the
    legacy GraphQL fields and database columns.
