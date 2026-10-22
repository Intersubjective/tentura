## 1. Verdict

**Revise before dispatch.** The owner decisions are broadly compatible with Tentura, but the plan is not yet executable without further interpretation: Questions authorization can restore revoked access, proposed copy misstates Request visibility, Lane 3 cannot meet “every trusted person” through its proposed client-only change, and its reset contradicts D5. Lane 4 substantially exceeds five hours; Lane 3 likely does too. Triage correctly prioritizes comprehension and freshness over performance, but omits #248 and labels several unresolved design tasks “fully specified.” Reviewed checkout `e6289c353` and locally available PR branches; this was a read-only review, with no tests run.

## 2. Blocking problems

1. **Claim: the proposed Questions audience is complete and safe.**  
   **Evidence:** The plan ORs active forwarding with *any* `inbox_item`, role 6, offers and admission ([plan:185](/home/vader/MY_SRC/tentura/docs/plans/2026-10-22-opus-sprint-decisions.md:185)). That permits historical inbox/participant records to defeat cancellation or rejection. Existing content authorization checks blocks, drafts/deletion and active relationships ([m0242.dart:142](/home/vader/MY_SRC/tentura/packages/server/lib/data/database/migration/m0242.dart:142)); `hidden_for_viewer` separately implements the block wall ([m0193.dart:4492](/home/vader/MY_SRC/tentura/packages/server/lib/data/database/migration/m0193.dart:4492)). PR #543’s `_canUseLobby` checks only author, lobby ban and active offer.  
   **Fix:** Define one server-owned Questions policy: readable Request **AND** eligible current audience **AND** no applicable block/Questions ban. Do not treat historical inbox presence as authorization. Specify discovery-only viewers, rejected/cancelled forwards, stewards, departed helpers, lifecycle read/write rules and cross-recipient blocks. Apply the same policy to messages, history, mentions, notifications and realtime delivery. Preserve General’s separate admission boundary.

2. **Claim: “Save without sending — Only people you forward to will see it.”**  
   **Evidence:** This action publishes the Request ([beacon_create_screen.dart:724](/home/vader/MY_SRC/tentura/packages/client/lib/features/beacon_create/ui/screen/beacon_create_screen.dart:724)). Discoverable Requests are readable by mutually visible people without forwarding ([m0242.dart:170](/home/vader/MY_SRC/tentura/packages/server/lib/data/database/migration/m0242.dart:170)).  
   **Fix:** Use publication wording and explain discovery truthfully, conditional on `isDiscoverable`. “Save” must not imply a private draft. Also remove the unsupported “roughly two steps” explanation of trust: visibility is mutual and MeritRank-dependent, not a fixed hop promise.

3. **Claim: adding direct-trust peers to `holderIds` implements D3.**  
   **Evidence:** Server candidates are mutually visible, unblocked peers ordered by ID ([projection_reader.dart:553](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/constellation_anchor_projection_reader.dart:553)); selection takes the first 200, without direct-trust priority ([snapshot_reader.dart:361](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/constellation_field_snapshot_reader.dart:361)). The client has another **120-peer** budget ([constellation_consts.dart:6](/home/vader/MY_SRC/tentura/packages/client/lib/features/constellation/domain/constellation_consts.dart:6)), and holders can be dropped ([cap_policy.dart:40](/home/vader/MY_SRC/tentura/packages/client/lib/features/constellation/domain/constellation_cap_policy.dart:40)). One-way direct trust does not establish mutual visibility.  
   **Fix:** Specify how D3 survives both caps and the visibility wall. Prefer an explicit contact-node projection that preserves restricted content access, with direct-contact reservation/exemption rules and bounded rendering. Test one-way trust, blocks, more than 120/200 contacts, pinned nodes and support paths. A client-only holder change is insufficient.

4. **Claim: reset person anchors by deleting rows and clearing local state.**  
   **Evidence:** D5 says **all** user-placed positions; Lane 3 narrows this to people ([plan:57](/home/vader/MY_SRC/tentura/docs/plans/2026-10-22-opus-sprint-decisions.md:57), [plan:170](/home/vader/MY_SRC/tentura/docs/plans/2026-10-22-opus-sprint-decisions.md:170)). Anchor writes use viewer locks, revision watermarks and replayable operation results ([anchor_repository.dart:42](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/constellation_anchor_repository.dart:42)); client writes can remain in flight ([placement_case.dart:560](/home/vader/MY_SRC/tentura/packages/client/lib/features/constellation/domain/use_case/constellation_placement_case.dart:560)).  
   **Fix:** Reset all positioned target kinds, including hidden/offscreen targets. Specify transactional revision advancement, tombstones, retry/idempotency, cross-device invalidation and handling of pending/in-flight placements. A bare DELETE plus local clear can let delayed writes restore positions.

5. **Claim: existing list/unread infrastructure makes Lane 3 execution-ready.**  
   **Evidence:** `ConstellationTextView` enumerates authors of eligible Requests only ([text_view.dart:156](/home/vader/MY_SRC/tentura/packages/client/lib/features/constellation/ui/widget/constellation_text_view.dart:156)). It excludes trusted people without Requests and Post-only authors. Field entities contain no per-item opened/unread state ([constellation_field.dart:19](/home/vader/MY_SRC/tentura/packages/client/lib/features/constellation/domain/entity/constellation_field.dart:19)). `room_seen` measures room reading, which is not equivalent to opening a discoverable Request.  
   **Fix:** Specify a common person population for Map/List and a concrete read-state contract for #256: what becomes new, what opening clears, persistence and cross-device behavior. Either supply its data projection or explicitly make #256 design-only. “Stop and report if missing” is not an autonomous implementation packet.

## 3. Should-fix

1. **Claim: D8 and D12 are assigned work.**  
   **Evidence:** #248 is the sole non-`good to go` issue omitted from §1; D8 has no implementation step. D12 records a required spec amendment but assigns no executor ([plan:60](/home/vader/MY_SRC/tentura/docs/plans/2026-10-22-opus-sprint-decisions.md:60)). The current glossary already recognizes Post workspaces as Chat ([terminology.mdc:9](/home/vader/MY_SRC/tentura/.cursor/rules/terminology.mdc:9)).  
   **Fix:** Assign #248 to Lane 2, including composer order and terminology tests. Treat “New chat” as the settled action label; retain Post as the object noun unless explicitly changing it. Assign D12’s amendment to the integrator; separate #189’s remaining compact-age concern.

2. **Claim: freshness symptoms have one root cause and need missing subscriptions.**  
   **Evidence:** MyWork has retry timers as well as hint debouncing ([my_work_cubit.dart:489](/home/vader/MY_SRC/tentura/packages/client/lib/features/my_work/ui/bloc/my_work_cubit.dart:489)); rejected reads have automatic backoff ([retry_rejected_read.dart:26](/home/vader/MY_SRC/tentura/packages/client/lib/data/service/remote_api_client/retry_rejected_read.dart:26)). Local untrust patching already exists for #359 ([graph_cubit.dart:561](/home/vader/MY_SRC/tentura/packages/client/lib/features/graph/ui/bloc/graph_cubit.dart:561)).  
   **Fix:** Call this a symptom cluster. Trace mutation completion → server delivery → client reception → each retry/refetch → emission → visible UI. Include reconnect, account change and stale-response races. Set a measurable acceptance threshold and a timebox; do not promise to resolve saturation while excluding its remediation.

3. **Claim: “Mark all read” can reuse `_ActivityDismissAllButton`; watching digest represents the watchlist.**  
   **Evidence:** That button explicitly replaced mark-all-seen and performs **dismissal**, not reading ([inbox_screen.dart:237](/home/vader/MY_SRC/tentura/packages/client/lib/features/inbox/ui/screen/inbox_screen.dart:237)). The digest counts watched Requests with qualifying active notifications, not every watched Request ([attention_repository.dart:692](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/attention_repository.dart:692)).  
   **Fix:** Specify independent seen, cleared and settled behavior. Define “old,” expiry conditions, pagination coverage, Watching membership and filter/group interaction. Expiration must not silently remove obligations, unanswered forwards or pending prompts.

4. **Claim: #479 can simply prompt after awaiting selection.**  
   **Evidence:** `RoomCubit.batonSelect` returns `void` and catches failures ([room_cubit.dart:1571](/home/vader/MY_SRC/tentura/packages/client/lib/features/beacon_threads/ui/bloc/room_cubit.dart:1571)); automatic selection may receive `userId == null`. Plan writes require a Request, enabled plan feature, editable lifecycle and admitted actor ([beacon_plan_case.dart:958](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/beacon_plan_case.dart:958)).  
   **Fix:** Define a successful selection result/effect carrying the resolved taker. Gate the prompt appropriately, retain the same step ID across retries, handle a departed assignee and failed plan save, and avoid reopening the prompt on ordinary realtime refresh.

5. **Claim: the cloud bucket is fully specified.**  
   **Evidence:** #267 still leaves paused-state placement/profile discoverability open; #269 provides a complaint without a chosen navigation solution; #271 leaves settings entry and permission messaging unspecified. #632 includes a departure-attribution privacy question; #634 combines a freshness gap, semantics and a release/closure race ([ISSUES_BUNDLE:2294](/tmp/claude-1000/-home-vader-MY-SRC-tentura/28db05ca-d496-4934-be08-7428a927d9f3/scratchpad/issues_bundle.md:2294)).  
   **Fix:** Supply bounded UI specifications before relabeling. Split #634 and coordinate its block-marker change with Lane 1 and concurrency fix with Lane 4. Keep #278–#280 together under one database owner with transaction-focused review. #243’s alert requirement also needs an owner.

6. **Claim: each lane fits roughly five hours.**  
   **Evidence:** Lane 4 combines an authorization/schema rebase with six other features and an Activity specification ([plan:180](/home/vader/MY_SRC/tentura/docs/plans/2026-10-22-opus-sprint-decisions.md:180)). Lane 3 combines population policy, list/search, unread semantics and distributed reset.  
   **Fix:** Use these bounded deliverables:

   | Lane | Five-hour assessment | Missing execution contract |
   |---|---|---|
   | 1 | Plausible for diagnosis plus a small fix group | Repro accounts, baseline, latency target, retry tracing, explicit cutoff |
   | 2 | Plausible with controlled scope | Add #248; truthful copy; empty vs filtered/error states; supported grouping data |
   | 3 | Not credible as written | Resolve population/caps first; separate reset; make #256 specified or design-only |
   | 4 | Not credible | Questions as its own delivery; move #597/#636/#474 to bounded follow-ups; separate #479/#268; Activity spec only |

   Name targeted tests, codegen commands and acceptance evidence per packet. The integrator must run both analyzer gates, required integration suites and browser checks; every local wrapped run must share the same serialization lock. Copy proofreading is an explicit pre-merge dependency, not an implementation ambiguity.

## 4. Answers to §5 Q1–Q8

1. **Contradictions:** D1 is an authorized, narrow exception to General-only rooms; update executable guards and policy tests, not just AGENTS.md. D3 needs a distinction between contact presence and content visibility. The person-only reset contradicts D5. D8 does not conflict with an existing ban on Chat terminology—the glossary already permits it. D11 must preserve responsibility routing and seen/cleared/settled distinctions. None requires public performance scoring; preserve the closure design’s voluntary, private signals and separation between co-presence and trust ([social design:167](/home/vader/MY_SRC/tentura/docs/plans/post-request-closure-social-design.md:167)).

2. **Questions audience:** **Not leak-free as written.** Use the centralized conjunction described in Blocking 1. `can_read_content` alone is also insufficient: discovery and hierarchy observers can read content without having received the Request. State explicitly that eligible recipients see the shared Questions conversation; General remains private to admitted participants.

3. **Polling and 1704:** No evidence supports a periodic 20–30-second data poll in the cited surfaces. However, “only debounce” is false: retries and reconnect catch-up exist. **1704 is admission backoff**, emitted for queue limits, deadlines or closed admission, with `retryAfterMs` ([main_db_scope_admission.dart:111](/home/vader/MY_SRC/tentura/packages/server/lib/data/service/main_db_scope_admission.dart:111), [257](/home/vader/MY_SRC/tentura/packages/server/lib/data/service/main_db_scope_admission.dart:257)). It does not by itself identify slow SQL.

4. **Direct-trust holders:** Yes, this affects both cap layers and potentially layout cost. Preserve pinned/support-path guarantees; do not obtain “always present” by bypassing the content visibility wall. The 201st server candidate cannot be recovered by client composition.

5. **Whole-plan save:** **Safe against silent concurrent overwrite when used correctly; a dedicated append mutation is not required.** The server locks the head and performs three-way merge against `baseSeq`, rejecting conflicts ([beacon_plan_case.dart:380](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/beacon_plan_case.dart:380)). The client already rebases conflicts ([plan_edit_cubit.dart:85](/home/vader/MY_SRC/tentura/packages/client/lib/features/beacon_plan/ui/bloc/plan_edit_cubit.dart:85)). Preserve the original base and stable new-step ID; test simultaneous appends, conflicting edits and retry after an uncertain response.

6. **Release set:** Pending offers only is the safe interpretation **for this action**, but label it “Decline remaining offers,” not a promise to remove everyone else. Exclude acknowledged helpers, watchers and mere recipients. Recheck eligibility under the same locks as admission/closure, settle corresponding obligations, and keep reasons private. Existing decline already rejects historically acknowledged contributions ([coordination_case.dart:535](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/coordination_case.dart:535)). Enough help must continue allowing backup offers.

7. **Sequencing:** Merge shared freshness contracts first, then the field population contract before list/search. Deliver Questions server support before its client. Keep Activity redesign last and migrations/versioning under one integrator. Detailed map follows.

8. **Triage:** Keep performance/MeritRank parked, #91 design-only, and the already-owned cloud fixes outside Opus unless live reproduction shows otherwise. Add #248. Split #634; specify #267/#269/#271 and #632’s privacy item before cloud execution. #597 and the now-decided #636 are good bounded cloud candidates. #281 requires collecting its rollout acceptance evidence, not merely flipping production configuration.

## 5. Factual corrections to §3 code claims

| Claim | Verification / correction |
|---|---|
| No client data polling; cited surfaces only debounce 50–100 ms | **Partly correct.** No periodic poll found; one-shot retries also fetch data. Invalidation batches ordinary hints at 100 ms and room messages at 16 ms: `invalidation_service.dart:90`. |
| Status, withdrawal and relationship triggers already exist | **Correct.** `m0193.dart:6960`, `6980`, `7020`, `7076`, `7196`–`7228`. Trigger existence does not prove authorized delivery or UI convergence. |
| `InvalidationService → RealtimeSyncCase` | **Correct**, through `RealtimeSyncPort`: `realtime_sync_case.dart:10`. |
| Server notify timestamp absent from the ordinary hint | **Correct for the inspected wire shape.** Client timing alone cannot measure the mutation-to-receipt interval. |
| Withdrawal improved to 1.9–8.6 seconds | **Supported by the supplied QA comment**, not independently measured in this review. |
| Picker/field empty-state locations | **Correct.** Picker currently renders `noReachableContacts`/`labelNothingHere`: `forward_recipient_picker.dart:780`. Absence of direct trust is not sufficient evidence that the visible result is empty. |
| Legend/profile/rating need new information affordances | Legend locations are correct; the profile already has an info button (`profile_view_body.dart:293`), and rating already supplies a tooltip (`rating_screen.dart:260`). Improve existing affordances. “Wider network reach” follows the cited ARB range, at line 1313 onward. |
| Field person panel avoids synthesizing MeritRank scores | **Correct for the field mapping:** `constellation_cubit.dart:2648`. |
| Picker already has trust tier/path | **Overstated.** `ForwardCandidate` has a `Profile`, score and lineage explanation fields, not a general intermediary path (`forward_candidate.dart:13`). Direct grouping can use explicit trust; “Through X” requires authorized evidence. |
| “Save without sending” visibility explanation | **Wrong:** published discoverable Requests can be seen without forwarding. |
| Holder composition and 72-hour Post window | **Broadly correct:** `constellation_anchor_composition.dart:185`, `271`. Pinned peers are also budget-exempt and re-added; holders are not guaranteed retention. |
| Server cap protects direct-trust peers | **Wrong:** first 200 by ID after exclusions; no direct-first ordering. Client additionally caps at 120. |
| Existing text view is a ready friends list | **Wrong:** Request-author grouping only; no complete people/Post population. |
| Existing attention/room-seen data supplies #256 | **Unproven and absent from field entities.** The cited status-marker widget renders Request lifecycle/pinning, not person unread state. |
| Re-arrange moves free nodes only | **Correct:** `constellation_cubit.dart:1819`. It does not reset stored anchors. |
| PRs #543/#544 are 280 commits behind; `m0253` collides | **Correct against local refs.** Main’s `m0253` repairs #398 block cleanup. Branch `_canUseLobby` is at line 178. |
| PR review fixes remain relevant | **Confirmed:** admitted-only mentions, per-person audience checks, General-oriented realtime lookup, custom `AlertDialog`, and missing pagination parameters remain in inspected branches. |
| #597 can reuse `viewerCanForward` | **Correct:** `my_work_cards.dart:52`; helper card currently exposes forwarding through overflow at line 794, not a dedicated footer CTA. |
| Baton selection creates no plan step | **Correct:** `room_baton_case.dart:232`. It records selection, system message and attention. |
| Whole-plan save needs concurrency handling | **Correct, already implemented:** head lock, merge and conflict recovery. Preserve that path. |
| `missingCriteria` may already be available | **Not on reviewed main.** The sheet still derives missing conditions locally: `beacon_close_confirm_sheet.dart:77`, `110`. |
| Watching digest and mark-all-read references | Digest exists, but is notification-derived. `_ActivityDismissAllButton` is **dismiss all**, not mark all read. `UpdatesFeedCubit.markAllSeen` exists at line 269. |

## 6. Suggested merge order of lanes and file-conflict map

1. **Integrator preparation:** correct the plan, assign #248/D12, freeze policy contracts, allocate migration numbers and reserve one test lock.
2. **Lane 1:** merge shared realtime corrections and observability; avoid broad refactoring.
3. **Lane 3 population contract**, then **Lane 2 copy/composer** and **Lane 3 list/search** against that contract. Reset is a separate reviewed change.
4. **Questions server**, followed by **Questions client**. Keep unrelated dormant item threads disabled; verify old-client behavior.
5. **Remaining Request micro-features:** #597/#636/#474, then separately tested #479 and #268.
6. **Activity specification/redesign last.** Integrator performs the version/cache-buster bump and merged-tree verification before deployment.

| Shared area | Likely conflict | Ownership recommendation |
|---|---|---|
| `app_en.arb`, `app_ru.arb` | All lanes | Allocate keys; regenerate localization after integration |
| Constellation cubit/state, filter bar, text view | Lanes 1, 2, 3 | Lane 3 owns; others provide bounded patches |
| Forward picker/cubit and composer | Lane 2; cloud #267; #248 | Lane 2 coordinates |
| MyWork cards, Request page, People, room cubit | Lanes 1 and 4; cloud #634 | Lane 1 owns refresh contracts; Lane 4 owns actions |
| Invalidation service, realtime case, websocket delivery | Lanes 1 and 4 | Lane 1 owns transport; Questions adds scoped policy integration |
| Attention repository, Inbox/Updates, watching | Lane 4 and existing cloud work | One Activity integration owner |
| Anchor repository/store/placement protocol | Lane 3 | One owner for reset and revision semantics |
| Coordination/closure/plan | Lane 4; cloud #634/#632 | Merge race fixes before bulk-decline behavior |
| Migrations and `_migrations.dart` | Lanes 3 and 4 | Integrator assigns final monotonic versions before deployment |
| Terminology, CONTEXT, AGENTS, version/cache-buster | Lanes 2 and 4; integrator | Integrator consolidates |

