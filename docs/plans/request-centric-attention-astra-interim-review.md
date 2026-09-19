**Interim verdict: C is substantially enforced for the implemented obligation kinds. A has strong server protections but is not yet delivered end to end. B still conflicts with the accepted server projection. I found no P0; several P1 seams need correction before activation.**

This was a read-only source review on `feature/events_refac`, observed through `982194be6`. I did not execute tests; journal test results are historical evidence, not independently reproduced results.

1. **P1 — Clearing an outcome can hide the Request’s live attention. Defect.**

   The feed excludes `requestActivity` whenever its Request appears in `dismissed_tombstone`, irrespective of whether uncleared optional receipts remain or subsequently arrive ([server projection:579](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/attention_repository.dart:579)). Those receipts still contribute to the tab total ([summary:240](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/attention_repository.dart:240)).

   B is also incomplete before dismissal: non-helping outcomes receive event counts and previews, contrary to “no dot, no sub-cards” ([outcome projection:488](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/attention_repository.dart:488), [preview attachment:867](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/attention_repository.dart:867)).

   **Smallest correct fix:** separate outcome visibility from live Request eligibility. Dismissing the historical trace must not veto current or future Request attention. Project tombstones without children or dots; retain independently reachable live attention. Test outcome-only dismissal followed by a new optional event.

2. **P1 — Client optimism still conflates reading with clearing, and sweep membership is too broad. Defect.**

   `markSeen` changes primary-surface totals; `markAllSeen` explicitly zeroes them ([markSeen:539](/home/vader/MY_SRC/tentura/packages/client/lib/domain/attention/attention_case.dart:539), [markAllSeen:695](/home/vader/MY_SRC/tentura/packages/client/lib/domain/attention/attention_case.dart:695)). Group projection subtracts read children from `eventUnseenCount`, although the server now defines that count through uncleared optional attention ([group projection:51](/home/vader/MY_SRC/tentura/packages/client/lib/domain/attention/attention_group_projection.dart:51), [server definition:395](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/attention_repository.dart:395)).

   Meanwhile, optimistic `dismissAll` selects every cached top-level receipt that is not cleared—without filtering surface, obligations, or outcome type ([dismissAll:818](/home/vader/MY_SRC/tentura/packages/client/lib/domain/attention/attention_case.dart:818)). Server refusal eventually corrects this, but the intermediate projection falsely clears ineligible rows.

   **Smallest correct fix:** read operations must update History’s read state only. Compute clear deltas from active optional membership, independent of `isSeen`. For sweeping, use actual dismissible receipt/outcome identities; where membership is unknown, avoid optimistic removal.

3. **P1 — Explicit event clears cannot be undone through the implemented undo endpoint. Defect.**

   Single-clear operations never establish `undo_deadline` ([clear completion:254](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/attention_clear_repository.dart:254)); undo treats a null deadline as `neverApplied` ([undo:668](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/attention_sweep_repository.dart:668)). The clear result also supplies no undo token.

   There is a second missing connection: the snapshot captures `decisionRevision`, but apply does not pass it, and single-clear members do not persist it ([case:76](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/attention_clear_case.dart:76), [member insert:201](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/attention_clear_repository.dart:201)).

   **Smallest correct fix:** give explicit clears the same bounded undo metadata and per-member generation/revision capture as sweeps. Return that capability through the client. Adding a snackbar in U16 cannot repair this server gap.

4. **P1 — U10d’s provenance payload cannot implement the required first note. Defect in an accepted prerequisite.**

   The card requires the **latest forward carrying a note**, followed by chronological ordering ([spec:234](/home/vader/MY_SRC/tentura/docs/plans/issue-171-card-spec.md:234)). The query instead returns three senders ranked by MeritRank; `strongestNotePreview` comes from the highest-ranked sender without requiring a nonempty note ([m0188:104](/home/vader/MY_SRC/tentura/packages/server/lib/data/database/migration/m0188.dart:104)). The DTO carries neither forward timestamp nor forward identity ([sender DTO:81](/home/vader/MY_SRC/tentura/packages/client/lib/features/inbox/domain/entity/inbox_provenance.dart:81)).

   A recent note from the fourth-ranked sender can therefore be absent entirely. U16 cannot recover it by sorting the supplied data.

   **Smallest correct fix:** extend the existing provenance contract with an explicitly selected latest note-bearing forward, its identity, timestamp and attribution. Preserve the authorization filters. Test four senders, with the newest note outside the MR top three and the top-ranked sender having no note.

5. **P1 — Cross-surface atomicity is only implemented for part of the transition. Defect.**

   Beacon invalidations use `_refreshAcrossSurfaces`; help-offer and Inbox invalidations still refresh counters and Activity independently ([dispatcher:197](/home/vader/MY_SRC/tentura/packages/client/lib/domain/attention/attention_case.dart:197)). My Desk refreshes separately after a debounce ([desk subscriber:182](/home/vader/MY_SRC/tentura/packages/client/lib/features/my_work/ui/bloc/my_work_cubit.dart:182)).

   The U15 test claiming “Never on two surfaces at once” observes only My Desk’s archived/nonarchived lists—it never observes For You ([test:44](/home/vader/MY_SRC/tentura/packages/client/test/features/my_work/my_work_request_invalidation_test.dart:44), [assertion:74](/home/vader/MY_SRC/tentura/packages/client/test/features/my_work/my_work_request_invalidation_test.dart:74)).

   **Smallest correct fix:** coordinate both surface projections and totals under one transition generation, including help-offer/Inbox changes. Verify with held responses while observing both mounted surfaces. The existing test does not establish the claimed property.

6. **P1 — My Desk’s clear path discards authoritative outcomes and can darken a card while attention remains. Defect.**

   The cubit removes `latestUnseen` locally before sending the command, and refreshes only on an exception ([clearOptionalEvent:468](/home/vader/MY_SRC/tentura/packages/client/lib/features/my_work/ui/bloc/my_work_cubit.dart:468)). Its use case discards `AttentionClearResult` ([adapter:214](/home/vader/MY_SRC/tentura/packages/client/lib/features/my_work/domain/use_case/my_work_case.dart:214)), so skipped/denied results are indistinguishable from successful clearing.

   With additional optional receipts, removing the sole preview leaves no renderable row; the card derivation deliberately turns its optional total into zero ([derivation:43](/home/vader/MY_SRC/tentura/packages/client/lib/features/my_work/domain/derive_my_work_card_attention.dart:43)). Recovery depends on a later refresh.

   **Smallest correct fix:** preserve and handle the command result, then replace the desk projection authoritatively, including the next optional preview. Keep removal reversible on refusal/failure.

7. **P2 — Tab dots still violate their declared semantics. Defect, not a styling preference.**

   My Desk’s dot total counts `activeAttention`, which includes obligations, rather than optional attention alone ([summary:246](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/attention_repository.dart:246)). Conversely, surface totals enumerate receipts only, not independently dismissible outcome rows or pending-forward membership.

   The navbar then returns immediately when showing the obligation badge, suppressing the dot ([navbar:32](/home/vader/MY_SRC/tentura/packages/client/lib/features/home/ui/widget/my_work_navbar_item.dart:32)). The journal’s “one-badge-slot, count-first” endorsement conflicts with the durable contract’s independent dot-and-number rule.

   **Smallest correct fix:** define explicit dot-bearing membership per surface, derive totals from it, and render dot and number together. Test obligation-only, optional-only, both, pending-forward-only and outcome-only states against actual server responses.

8. **P2 — Clearing the last attention row changes My Desk’s ordering anchor. Defect.**

   `myWorkAttention` omits Requests with no remaining optional events or obligations ([server:148](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/attention_repository.dart:148)). Consequently, the client loses `firstEntryAt` and switches to `beacon.createdAt` ([sort:110](/home/vader/MY_SRC/tentura/packages/client/lib/features/my_work/domain/derive_my_work_cards.dart:110)).

   A Request whose entry time differs from creation time can move when cleared, then move again when another optional event arrives.

   **Smallest correct fix:** return/preserve ordering anchors independently of active attention. Test clear-last-event and subsequent optional arrival with deliberately different creation and entry times.

9. **P2 — Concurrent single clears can both report the same receipt as applied. Defect identified by source interleaving.**

   Single clear computes and stores `applied` before its guarded update, then reports that precomputed list without checking which rows it actually changed ([eligibility:176](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/attention_clear_repository.dart:176), [update:229](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/attention_clear_repository.dart:229), [result:267](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/attention_clear_repository.dart:267)).

   Two different operations can both select an uncleared receipt; only one clears it, but both report success. This corrupts per-operation counts and future undo ownership.

   **Smallest correct fix:** derive applied membership from `UPDATE … RETURNING`, or lock and recheck before recording it. Sweep already checks actual operation ownership after writing ([sweep:313](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/attention_sweep_repository.dart:313)).

The accumulated deferrals require these explicit gates:

- **P1, U18:** legacy obligation identity and historical hierarchy placement are assigned to cutover in the journal ([legacy identities:2484](/home/vader/MY_SRC/tentura/docs/plans/request-centric-attention-implementation-journal.md:2484), [placement:6827](/home/vader/MY_SRC/tentura/docs/plans/request-centric-attention-implementation-journal.md:6827)), but U18’s executable manifest principally describes seen-to-cleared conversion ([manifest:643](/home/vader/MY_SRC/tentura/docs/plans/request-centric-attention-implementation-plan.md:643)). These compound: reconciliation deliberately cannot repair unkeyed obligations, while old hierarchy receipts remain primary attention. Add both migrations and their interrupted/repeated-run acceptance cases explicitly before scheduling U18.
- **P1, existing privacy debt:** the attention provenance path correctly gates content and filters blocked senders before list/count projection. I found no new leak there. However, the legacy Inbox delegate explicitly passes `false` for blocked filtering ([m0188:194](/home/vader/MY_SRC/tentura/packages/server/lib/data/database/migration/m0188.dart:194)). U17’s retained Following/Rejected consumers mean #188 remains relevant after U16. Record its disposition explicitly; protected grouped cards do not establish whole-feature privacy.
- **P2, U17/U19:** the missing `attentionRequest` endpoint compounds with My Desk’s single optional preview and “Timeline” navigation that only opens the Request ([query comment:36](/home/vader/MY_SRC/tentura/packages/server/lib/api/controllers/graphql/query/query_attention.dart:36), [navigation:268](/home/vader/MY_SRC/tentura/packages/client/lib/features/my_work/ui/widget/my_work_cards.dart:268)). Finish the authorized personal event destination before accepting overflow reachability.
- **P2, U16:** the three-chip ceiling is an explicit implementation constraint, not a defect in the current primitive. Enforce it in the assembled card and provide access to omitted chips; retain the four-chip/1.3× regression case ([manifest:602](/home/vader/MY_SRC/tentura/docs/plans/request-centric-attention-implementation-plan.md:602)).

The overseer’s remaining blind spot is **testing both sides against different meanings of the same field**. The clearest example is the accepted claim “one card swept is one decrement” ([journal:7857](/home/vader/MY_SRC/tentura/docs/plans/request-centric-attention-implementation-journal.md:7857)), while the server counts receipts. Mutation testing proves a test detects changes to its assumption; it does not prove the assumption matches the other layer. Likewise, the ownership guard detects specific strings, while My Desk maintains and mutates attention projections in another shape ([guard:50](/home/vader/MY_SRC/tentura/packages/client/test/architecture/single_attention_owner_test.dart:50)).

What is sound: server sweep eligibility excludes obligations and unanswered forwards, with a database trigger protecting the latter; generic live-obligation settlement is rejected; My Desk’s current CTAs lead to response/review flows rather than Done. Those are substantive protections. The necessary next verification increment is a real server-to-client seam suite covering the findings above—not another isolated component acceptance pass.