# Adversarial review: Constellation pinning P01–P09

Review date: 2026-09-12. Branch: `feature/pin_constellation`.

**Verdict: reopen P03, P06, P08 and P09 acceptance.** Seven correctness findings remain in the reviewed implementation. The most direct failure is that the Map builds its nodes from the automatic field arrays even though pinned-only entities live in the anchor overlay. Passing composition tests alone cannot establish that those pins render.

## Scope and evidence

The P09 acceptance boundary is `a3c403723`. I reviewed the plan, branch history and tracked source at `9a6f69f00`, using an immutable `git archive` in `/tmp/tentura-pinning-review-9a6f69f00`. This includes subsequent P10-era changes, particularly `98ac22248`; findings below concern behavior required by P01–P09. P10's rejected browser acceptance and P11's future release gate are not counted as implementation defects here.

This is a static adversarial review, not a claim that the test suites or browser journeys passed. I traced server selection, authorization, mutation/storage boundaries, client mapping/composition, refresh/write lifecycle and Map construction, and inspected relevant tests. I did not start integration tests, analyzers, codegen or browsers alongside the implementation agent. Existing development processes were inspected using IDs, state, memory and executable names only; none were terminated because ownership and hung status were not established.

Live changes were checked before writing this report. They modify nine client paths, including the anchor case, Cubit and composition. The pending edits remove the tier-1 budget exemption and Text-pin origin fallback, improve pin eligibility and selection, and change failure messages. They do **not** resolve the seven findings below. Line references use the committed snapshot; locate the named method when applying fixes to the moving branch.

## R1 — High: Map omits entities present only in the anchor overlay

**Locations:** `packages/client/lib/features/constellation/ui/bloc/constellation_cubit.dart:1286`, especially `1301` and `1317–1320`, `_rebuildGraph`.

**History/contract:** P08 integration `072227f81` adopted `composition.labelPlan` but retained the old automatic-only entity lookup. P09 accepted this wiring. C5/P09 require Map and Text to consume the same composed presentation.

The Map creates `peersById` from `field.peers` and `drawnRequests` from `field.requests`. It never unions in `composition.anchorOverlay.pinnedPeers`, `supportPeers` or `pinnedRequests`. Having a pinned ID in the label plan or `keptPeerIds` cannot create its missing node: the peer loop explicitly skips absent entities. The wire mapper keeps automatic arrays and the anchor projection separate, as it should.

**Reproduce:** pin another person's Request, then reload FULL. The server excludes its pinned ID from automatic discovery and returns it in `anchorProjection.pinnedRequests`. The composition can select its ID, but `_rebuildGraph` has no Request entity to instantiate. Likewise, a remote ANCHORS update introducing a person outside the retained automatic snapshot cannot add that person to the Map. Paint ordering and layout changes cannot fix a node that was never created.

**Fix recipe:**

1. Build deduplicated render-entity maps from the composed automatic layer plus its *visible* anchor overlay. Include authorized support peers.
2. Use those maps when creating Map nodes and attachment edges. Keep typed anchor identity; perform graph-ID conversion only at the graph boundary.
3. Preserve the original automatic field and `loadedAt`; do not merge overlay entities permanently into `field.peers`/`requests` as a workaround.
4. Make Text and Map use the same composed entity selection. Do not render every stored anchor: dormant/filtered targets remain absent.

**Regression:** feed the Cubit a realistic FULL payload with a pinned Request only in the projection; assert a `FieldRequestNode`, author node and attachment edge exist. Then introduce a pinned-only person through ANCHORS and assert it appears without changing the automatic snapshot or timestamp. Finally hide/remove the overlay target and assert overlay-only nodes disappear. Inspect actual graph nodes, not just `drawnRequestIds`.

## R2 — High: failed recovery read escapes and leaves placement unresolved

**Locations:** `packages/client/lib/features/constellation/domain/use_case/constellation_anchor_case.dart:278`, `_runWrite`; Cubit `_submitUpsert` / `_applyWriteOutcome` at `471–520`.

**History/contract:** P08 `8735a507c`, amended by `14bf2e132`. C7 explicitly requires rollback to last confirmation and `syncPending` when offline.

After a mutation throws, its catch block awaits `_refreshAnchorsOnce` without catching failure of that recovery read. Real offline behavior normally fails both calls. The second exception escapes; no typed failed outcome reaches the Cubit. Clearing the case's `_pendingWrite` in `finally` does not clear the Cubit's pending phase or restore its optimistic presentation. Also, the success-path catch-up read is inside the mutation `try`: if the mutation succeeds but that read fails, it is treated as a mutation failure and another read is attempted.

The tests named “failed write fetches ANCHORS once” and “offline failure…” fail the mutation while leaving the field repository available. They do not prove offline fallback.

**Fix recipe:**

1. Separate mutation completion from projection-recovery completion. Retain whether the server returned a successful mutation.
2. Attempt the required reconciliation read once; catch its failure separately.
3. Always complete the command with an outcome that clears the Cubit's pending placement. On unavailable recovery, restore the newest known confirmed state and mark sync pending. Retain a successful mutation's confirmed result if its subsequent read fails.
4. Contain/log failures from fire-and-forget realtime refreshes too. Do not blindly replay mutations.
5. Return a domain failure reason and localize it in UI; the pending raw `$error` message is not a substitute for recovery handling.

**Regression:** independently test mutation-fails/read-fails, mutation-succeeds/read-fails, and mutation-fails/read-succeeds. Assert write/read counts, no uncaught future error, final pending phase, restored position, sync-pending state and reconnect recovery.

## R3 — High: screen lifecycle reuses tokens and abandons in-flight command ownership

**Locations:** anchor case `121–166` (`activate`, `deactivate`, `onAccountChanged`, `bindLoadGeneration`), `278–334`; Cubit `173–191` (`close`, `load`).

**History/contract:** P08 `8735a507c`, `072227f81`, `14bf2e132`. C7 requires account/load guards, one pending write and command reconciliation surviving route disposal.

The singleton case retains `_confirmed` across `deactivate`/`activate`, but `deactivate` clears `_pendingWrite` and forgets the refresh future without cancelling the underlying operation. A new Cubit starts its local load generation at one and assigns that value back into the singleton. Old and new operations can therefore share the same “valid” generation. `activate` does not clear prior-account confirmation when its account argument changes; that reset exists in a separate `onAccountChanged` method, with no production caller found outside the Cubit's otherwise unreferenced method.

**Reproduce:** start a write on screen A, close it, and open another Constellation screen before completion. The new screen can enable a second write, while the first completion can pass the reused generation check. If the first completes while closed, reconciliation is simply discarded. For an account transition, seed account A revision 20, activate B and load B revision 1: the retained revision comparison rejects B's projection. Revision numbers from different accounts are not comparable. This is a client cache-isolation defect; it does not establish a server authorization bypass.

**Fix recipe:**

1. Give the use case ownership of a monotonically increasing lifecycle token; never replace it with a new Cubit's local counter.
2. Capture account identity and token in every asynchronous operation. Check both before adopting results.
3. Clear or partition confirmed state on account change inside the actual activation/account subscription path.
4. Separate screen subscription detach from command ownership. A route close must not erase a submitted same-account command or permit a second command before reconciliation completes.
5. Enforce single-write admission in the use case, not solely through UI button state. Ensure an old screen cannot deactivate a newer screen's subscription.

**Regression:** use completers for close/reopen before write completion, account A→B before read completion, and an older screen closing after a replacement attaches. Assert stale results cannot change B's projection, account B accepts its lower revision, and only one same-account command is admitted across navigation.

## R4 — Medium: readable cancelled/unknown stored anchors are removed instead of dormant

**Location:** `packages/server/lib/data/repository/constellation_field_snapshot_reader.dart:196`, `_loadAuthorizedAnchors`.

**History/contract:** introduced by `5ffaac2c8`, still present after P03 remediation `8867e7759`. C2 distinguishes readable stored anchors from status-limited **upserts**.

The stored-anchor authorization query includes `b.status = ANY('{0,7,8,5,4,6}'::int[])`. Thus a published, still-readable anchored Request changing to cancelled or an unknown status disappears from the returned anchor list before dormant classification. It should disappear from rendered `pinnedRequests`, while its authorized anchor survives and contributes no filter-hidden count.

**Fix recipe:**

1. Remove renderability/status gating from stored-anchor authorization only.
2. Keep publication, content-readability and both block directions intact.
3. Retain status restrictions for upsert authorization. Classify authorized stored targets afterward into visible, filter-hidden or dormant.
4. Share the common readability predicate between reads and writes, keeping the additional upsert restriction explicit; duplicated SQL caused this distinction to drift.

**Regression:** create/pin while eligible, change status to cancelled, read FULL and ANCHORS: anchor remains, Request is absent, hidden count is zero. Repeat for unknown status, restore eligibility and verify original coordinates. Also prove blocked/unreadable anchors return no ID or count. Repair the current test at `constellation_field_repository_pg_test.dart:569`: it attempts to upsert an already-cancelled target and expects an empty anchor list, so it does not test the required transition and conflicts with upsert authorization.

## R5 — High: connected pinned Requests lose their required author support

**Locations:** server snapshot reader `347–354`; `packages/client/lib/features/constellation/domain/constellation_anchor_composition.dart:289–305`, `_overlayForVisiblePins`.

**History/contract:** server closure remediation `8867e7759`; client P06 composition `74eb91674`. D24/C5 require the author and minimum authorized connecting closure for a visible pinned Request.

Both support calculations subtract visible pinned Request authors from `resolution.keep`. An author is added back only through the residual/ring path. A connected author therefore disappears from `supportPeers` unless independently pinned. FULL can mask this because its automatic `peers` array also includes reserved authors. ANCHORS has no automatic arrays and cannot rely on that accident. The server even fetches those author profiles and then omits them from both returned peer lists.

**Fix recipe:**

1. Include visible pinned Request authors in required support, except ego and independently pinned persons. Preserve intermediate path nodes too.
2. Apply the same rule in client recomposition after local filters. Do not subtract an author merely because a pinned Request references it.
3. Deduplicate shared support and remove exclusive support only after its last visible dependency disappears; retain automatic copies independently.
4. Pair this with R1 so supplied support is actually rendered.

**Regression:** use a connected author absent from the retained automatic snapshot (for example, beyond its cap). ANCHORS must contain the author's profile and required edges; Map must render the author-to-Request attachment. Cover direct and multi-hop paths, an independently pinned author, shared support, and filtering the last dependent Request. Keep the existing no-path author fixture, but do not treat it as proof of the connected case.

## R6 — High: pinning a person suppresses that person's unpinned Requests

**Locations:** server snapshot reader `74–102`, FULL assembly; `_discoverableRequests` around `538–574`.

**History/contract:** P03 `5ffaac2c8`. C5 requires pins/support outside independent automatic budgets; it does not exclude their unrelated Requests.

`reservedPeerIds` contains pinned persons, support persons and pinned Request authors. FULL passes that entire set as `excludeAuthorIds` to Request discovery, whose SQL excludes every matching `b.user_id`. Consequently, pinning a person can remove all that person's unpinned Requests on reload. Pinning one Request can also remove its siblings. They are not recovered by the overlay, which contains only pinned Requests.

**Fix recipe:**

1. Keep peer-budget exclusion separate from Request-budget exclusion.
2. Request discovery should exclude already-pinned Request IDs, not all Requests by reserved people. Preserve existing publication, visibility and membership filters.
3. Deduplicate by Request ID when composing results; do not resolve duplicate peers by dropping their Requests.

**Regression:** create two eligible Requests by one visible author. Compare FULL before and after pinning the person: both automatic Requests remain. Pin one Request: its sibling remains automatic and the pinned Request appears in the overlay. Add cap+1 candidates and prove the remaining automatic budget is still filled.

## R7 — Medium: queued refreshes retain stale parameters and can be lost

**Locations:** anchor case `185–207`, `408–449`, `adoptConfirmedProjection` and `_applyIncomingProjection`.

**History/contract:** P08 coalescer `8735a507c`, remediation `14bf2e132`. C7 requires one in-flight ANCHORS read plus one queued rerun and only the latest matching request generation to apply equal-revision membership changes.

The refresh loop captures generation and membership filters once. If a hint arrives while a read is running, only a boolean is set. After a filter/FULL generation change, the old loop returns at its stale check without rerunning for the current generation. If filters change without a generation change, the rerun still uses the old filter values. The public `refreshAnchors` also bypasses this coalescer, allowing independent reads to complete out of order. Equal revision is accepted without a request-order token, so revision comparison alone cannot protect newer membership/permission results.

**Fix recipe:**

1. Route production anchor reads through one coordinator. Store the latest requested account/token/filter parameters when setting queued work.
2. On completion, discard stale data but still drain any queued request using its latest parameters.
3. Use a monotonically increasing request token to arbitrate equal-revision responses, including interaction with FULL adoption. Do not reject all equal revisions: permission refresh requires them.
4. Keep the bound of one active read and one coalesced rerun; do not spawn a future per hint.

**Regression:** hold read A, change filters/generation, enqueue a hint, then finish A. Verify a read B uses current filters and its result is adopted. Invert FULL/ANCHORS completion with equal revision and different membership. Assert stale data never wins and bursts remain bounded.

## Remediation order and verification instructions

Suggested independently reviewable commits:

1. Fix server membership and closure together: R4, R5 server half, R6.
2. Fix composed rendering: R5 client half and R1.
3. Fix lifecycle ownership and refresh coordination: R3 and R7.
4. Fix recovery outcomes and localization: R2, then targeted tests for all command outcomes.

For each commit, first add the listed failing fixture, implement the smallest fix, run the targeted test and review its assertions. Do not weaken assertions or preload pinned entities into automatic arrays to make tests pass. Do not mark a stage accepted solely because its journal says it was accepted.

Coordinate test ownership with the active implementation agent. Run **at most one integration/browser/real-PG suite at a time** unless measured available memory supports more. Avoid concurrent Dart analyzers. After every worker return, inspect development processes by PID/PPID/state/elapsed time/RSS/executable; terminate only positively identified task-owned leftovers. Old age alone does not prove a process is hung, and zombies require their parent to reap them.

After focused regressions pass, run the repository's required lint/terminology checks and relevant broader suites sequentially, then perform the P10 browser journeys. Record actual commands, result and commit hash. This review supplies static defects and precise acceptance tests; runtime verification remains outstanding.
