# Feature-pair duplication audit (Round A2, 2026-10-30)

Method: compare analogous feature pairs/triples layer by layer (entity → repository → use case/cubit → widgets). Focus is copy-paste drift between AI-authored feature slices, not a repeat of Round A1’s repo-wide sweep.

**Issue:** [GitHub #830](https://github.com/Intersubjective/tentura/issues/830)  
**Prior round:** [`2026-10-30-duplication-audit.md`](./2026-10-30-duplication-audit.md) (A1)

## Summary counts

| Pair | Scope | Findings |
| :--- | :--- | :---: |
| **1** | Inbox / My Work / Updates | 4 |
| **2** | `beacon_view` / `post_view` / `beacon_create` | 3 |
| **3** | Forward / Post recipients & bud invite | 2 |
| **4** | Client entities vs `lib/` (`tentura_root`) vs server | 2 |
| **5** | Server repositories (SQL / visibility) | 2 |
| **6** | Shared `ui/` + `design_system` vs feature widgets | 2 |
| **Total** | | **15** |

---

## Pair 1 — Inbox / My Work / Updates

### 1.1 Scroll-triggered feed pagination

| Field | Detail |
| :--- | :--- |
| **Where** | `packages/client/lib/features/inbox/ui/widget/activity_stream_view.dart:308-319`<br>`packages/client/lib/features/updates/ui/widget/updates_feed_pane.dart:109-115` |
| **What** | Near-identical “load more when within `sectionGap` of max scroll” listeners. Activity For You chains offers pagination then Updates pagination; Updates pane only loads its cubit. |
| **Evidence** | Activity: `if (position.pixels < position.maxScrollExtent - context.tt.sectionGap) return;` then `ActivityOffersCubit().loadMore()` / `UpdatesFeedCubit().loadNextPage()`. Updates: same threshold check, `UpdatesFeedCubit().loadNextPage()` only. |
| **Drift** | Activity stream adds a second gate (`offers.hasMore`) before touching Updates; Updates pane has no analogue when embedded elsewhere. Threshold tweaks must be applied in two files. |
| **Severity** | low |
| **Fix scope** | client |
| **Suggested consolidation** | Extract `ScrollPaginationTrigger` (controller + `sectionGap` + callback) in `ui/widget/` or `design_system/`; both panes register one helper. |

### 1.2 Load-more spinner widgets

| Field | Detail |
| :--- | :--- |
| **Where** | `packages/client/lib/features/inbox/ui/widget/activity_stream_view.dart:1386-1393`<br>`packages/client/lib/features/updates/ui/widget/updates_feed_pane.dart:550-557` |
| **What** | Private `_ActivityLoadMoreIndicator` and `_LoadMoreIndicator` — same padding + `CircularProgressIndicator.adaptive()`. |
| **Evidence** | Both: `Padding(padding: context.tt.cardPadding, child: const Center(child: CircularProgressIndicator.adaptive()))`. |
| **Drift** | None functional today; cosmetic duplication only. |
| **Severity** | low |
| **Fix scope** | client |
| **Suggested consolidation** | Single `TenturaFeedLoadMoreIndicator` in design system. |

### 1.3 Empty-state implementations (three surfaces, three stacks)

| Field | Detail |
| :--- | :--- |
| **Where** | `packages/client/lib/features/inbox/ui/widget/for_you_empty_state.dart:11-14,128`<br>`packages/client/lib/features/my_work/ui/widget/my_work_empty_body.dart:11-12,80-97`<br>`packages/client/lib/features/updates/ui/widget/updates_feed_pane.dart:500-547` |
| **What** | Activity For You uses `ForYouEmptyState` + `CaughtUpPanel`; My Work uses bespoke `MyWorkEmptyBody`; Updates uses private `_EmptyUpdates` with `TenturaText` only. |
| **Evidence** | For You documents three distinct empty kinds (`nothingHere` / `nothingNew` / `noMatch`). My Work: custom `Icon` + `theme.textTheme.titleSmall` + `FilledButton.icon`. Updates: `AttentionView`-switched hint strings, no shared empty component. |
| **Drift** | My Work empty body uses legacy `kPaddingAll` / raw `TextStyle` paths while Updates uses `context.tt` tokens — design-system lint surface differs per tab. Inbox partially shares `CaughtUpPanel` with My Work (`my_work_screen.dart:591`) but not with Updates. |
| **Severity** | medium |
| **Fix scope** | client |
| **Suggested consolidation** | Parameterize `TenturaEmptyState` / `CaughtUpPanel` for filter-aware copy; migrate `MyWorkEmptyBody` and `_EmptyUpdates` to shared components with l10n-only differences. |

### 1.4 `PostSummary` mapping collapses server timestamps

| Field | Detail |
| :--- | :--- |
| **Where** | `packages/client/lib/features/inbox/data/repository/posts_repository.dart:36-49`<br>`packages/client/lib/features/inbox/domain/entity/post_summary.dart:12-16,41`<br>`packages/server/lib/domain/entity/post_summary.dart:16-17,43-44` |
| **What** | Same GraphQL/API concept mapped into divergent client vs server entities. |
| **Evidence** | Client `_toEntity`: `lastActivityAt: _parse(row.lastActivityAt) ?? _parse(row.lastMessageAt) ?? epoch`. Client entity has only `lastActivityAt`. Server entity requires both `lastMessageAt` and `lastActivityAt`. Server GraphQL `_toJson` emits both fields (`query_post.dart:50-51`). |
| **Drift** | Client silently merges two server columns; sorting or “latest message” UI cannot distinguish message time vs activity time on the client entity. Client omits `forwardedById` present on server (`post_summary.dart:33` server vs client entity has only `forwardedByName`). |
| **Severity** | medium |
| **Fix scope** | shared |
| **Suggested consolidation** | Single `PostSummary` in `lib/domain/entity/` (A1 #5); client `_toEntity` stops collapsing fields; align GraphQL fragment with server shape. |

---

## Pair 2 — `beacon_view` / `post_view` / `beacon_create`

### 2.1 Forward entry: Request nudge vs Post plain push

| Field | Detail |
| :--- | :--- |
| **Where** | `packages/client/lib/features/beacon_view/ui/widget/beacon_view_forward_overflow.dart:24-31,38-45`<br>`packages/client/lib/features/post_view/ui/screen/post_view_screen.dart:130-134,190-191` |
| **What** | Both surfaces expose forward affordances but through different helpers. |
| **Evidence** | Request: `beaconViewOpenForwardThenMaybeNudgeOfferHelp` → `ForwardBeaconRoute` then optional offer-help snackbar via `shouldNudgeOfferHelpAfterForwardVisit`. Post: `IconButton` → `_run(..., PostAction.forward)` → `context.router.push(ForwardBeaconRoute(beaconId: id))` only. |
| **Drift** | Post forward never runs the post-forward offer-help nudge path tied to `ForwardTargetProfile.post`. Product may intend that gap; if not, behavior diverges by kind. |
| **Severity** | low |
| **Fix scope** | client |
| **Suggested consolidation** | Shared `openForwardForBeacon(context, id, profile: request|post)` wrapping route push + optional nudge. |

### 2.2 Post actions declared twice (overflow ⋮ vs «О посте» sheet)

| Field | Detail |
| :--- | :--- |
| **Where** | `packages/client/lib/features/post_view/ui/screen/post_view_screen.dart:573-688`<br>`packages/client/lib/features/post_view/ui/widget/post_info_sheet.dart:204-274` |
| **What** | Mute, pin, forward, complain, leave, delete appear in both `_Overflow` popup and `post_info_sheet` quick actions / tiles. |
| **Evidence** | Overflow: `PostAction.mute`, `pin`, `budRequest`, `complain`, `leave`, `delete`. Sheet: `_QuickAction` forward/mute/pin/field plus `_ActionTile` complain/leave/delete with same `PostAction` enum. |
| **Drift** | Gating logic duplicated (`viewerIsAuthor`, `canChangeLifetime`, `canBud()` in overflow vs parallel checks in sheet). Menu changes require two edits; tests often cover only one surface. |
| **Severity** | medium |
| **Fix scope** | client |
| **Suggested consolidation** | Single `PostActionMenu.buildItems(PostViewState, …)` returning menu model consumed by overflow and sheet. |

### 2.3 Post overflow mute check uses a different clock than the screen

| Field | Detail |
| :--- | :--- |
| **Where** | `packages/client/lib/features/post_view/ui/screen/post_view_screen.dart:592-601,117-123` |
| **What** | Lifetime gating uses injected cubit clock; mute display in the same screen’s overflow uses wall clock. |
| **Evidence** | App bar / title: `cubit.now()` passed as `lifetimeNow`. `_Overflow.build`: `final now = DateTime.now();` then `summary?.isMutedAt(now)`. |
| **Drift** | Under tests or deadline refresh, mute-until labels and “can shorten lifetime” can disagree within one frame. |
| **Severity** | medium |
| **Fix scope** | client |
| **Suggested consolidation** | Pass `lifetimeNow` (or `cubit.now`) into `_Overflow`; one clock per screen. |

---

## Pair 3 — Forward vs Post recipients / bud invite

### 3.1 Request create reuses forward picker; Post bud reimplements rows

| Field | Detail |
| :--- | :--- |
| **Where** | `packages/client/lib/features/beacon_create/ui/widget/recipients_tab.dart:10-11,87-100`<br>`packages/client/lib/features/forward/ui/widget/forward_recipient_picker.dart:43-44,62-65`<br>`packages/client/lib/features/beacon_create/ui/widget/post_bud_invite_step.dart:72-88,112-178` |
| **What** | Request recipient selection embeds `ForwardRecipientPicker` + `ForwardCubit`. Post budding uses a separate checkbox list `_InviteeRow`. |
| **Evidence** | Recipients tab: `ForwardRecipientPicker(embedded: …)` with `ForwardCubit` selectors. Post bud: `for (final candidate in invitable) _InviteeRow(...)` with `CheckboxListTile` + per-invitee `TextFormField` note. |
| **Drift** | Post bud rows lack forward picker features (search, bands, lineage, capability reasons, presence). Retry/load-failed UX is parallel but not shared (`candidatesFailed` vs `ForwardCandidatesReady`). |
| **Severity** | medium |
| **Fix scope** | client |
| **Suggested consolidation** | Extract `RecipientCheckboxRow` (avatar, via-line, optional note field) used by bud step and slim forward modes; or embed a reduced `ForwardRecipientPicker` mode for post members. |

### 3.2 Parallel candidate-load state machines

| Field | Detail |
| :--- | :--- |
| **Where** | `packages/client/lib/features/forward/ui/bloc/forward_cubit.dart:59-60,100+`<br>`packages/client/lib/features/beacon_create/ui/bloc/beacon_create_cubit.dart:309-338` |
| **What** | Forward flow loads candidates via `ForwardCase` into `ForwardState.candidatesLoad`. Post bud loads via `_postBudCase.inviteStep` into `PostBudForm`. |
| **Evidence** | Forward: `unawaited(_loadCandidates())` on construct. Bud: `await _postBudCase.inviteStep(bud.postId)` with `candidatesLoaded` / `candidatesFailed` flags and pretick `selectedIds`. |
| **Drift** | Error handling differs (`ShowError` effect vs `candidatesFailed` boolean). Pretick rules live only on bud path; forward has lineage preselect — easy to fix one path and miss the other. |
| **Severity** | low |
| **Fix scope** | client |
| **Suggested consolidation** | Shared `CandidateLoadState` sealed class + mapper from forward GraphQL vs bud API responses. |

---

## Pair 4 — Client / `tentura_root` / server entities

### 4.1 `AuthorInvite` — same name, incompatible shapes

| Field | Detail |
| :--- | :--- |
| **Where** | `packages/client/lib/domain/entity/author_invite.dart:8-36`<br>`packages/server/lib/domain/entity/author_invite.dart:4-38` |
| **What** | Parallel domain types for author invites with different fields and status encoding. |
| **Evidence** | Client: Freezed `AuthorInvite` with optional `inviteeId`, `note`, `createdAt`; `AuthorInviteStatus.fromWire(String)`. Server: `AuthorInvite` requires `inviterId`, `forwardEdgeId`, `warm`, `sourcePostId`; status is `enum` with `.code` int. |
| **Drift** | Client cannot represent server-required invite lineage (`forwardEdgeId`, `warm`) without ad-hoc DTOs; status mapping string vs int risks silent mismatch if wire format changes. |
| **Severity** | medium |
| **Fix scope** | shared |
| **Suggested consolidation** | Canonical invite DTO in `lib/domain/entity/`; server entity implements mapping; client Freezed mirrors API subset explicitly. |

### 4.2 `PostSummary` triple definition (field-level drift)

| Field | Detail |
| :--- | :--- |
| **Where** | `packages/client/lib/features/inbox/domain/entity/post_summary.dart:7-26`<br>`packages/server/lib/domain/entity/post_summary.dart:4-25`<br>`packages/server/lib/data/repository/beacon_repository.dart:138-161` |
| **What** | Duplicate class name across client feature domain and server domain (also flagged in A1). |
| **Evidence** | Server row mapping sets `forwardedById`, `lastMessageAt`, `lastActivityAt` separately. Client class has no `forwardedById`; single `lastActivityAt`. |
| **Drift** | See **1.4** — client mapping hides `lastMessageAt`; server SQL and GraphQL expose both. |
| **Severity** | medium |
| **Fix scope** | shared |
| **Suggested consolidation** | Same as A1 item 2; add client fields before deleting duplicate. |

*(Positive note: `packages/client/lib/domain/entity/coordinates.dart` re-exports `tentura_root` — no drift there.)*

---

## Pair 5 — Server repository SQL duplication

### 5.1 Inbox readability guard copied for sweep undo

| Field | Detail |
| :--- | :--- |
| **Where** | `packages/server/lib/data/repository/attention_repository.dart:395-401`<br>`packages/server/lib/data/repository/attention_sweep_repository.dart:657-664` |
| **What** | Same `beacon_can_read_content` OR tombstone readability predicate for inbox rows. |
| **Evidence** | Repository eligible CTE: `public.beacon_can_read_content(ii.beacon_id, $1) OR (ii.status IN (3, 4) AND public.beacon_can_read_tombstone(...))`. Sweep `undoOutcomeReadabilityGuard`: identical AND clause with comment “re-asked at undo time in the same words”. |
| **Drift** | If visibility rules change (new status codes), one copy can lag — undo could restore rows the feed no longer shows. |
| **Severity** | high |
| **Fix scope** | server |
| **Suggested consolidation** | Move guard to `AttentionDismissibleSql` next to `visibleWithSurface`; import in sweep + repository. |

### 5.2 Ad-hoc `beacon_can_read_content` in invite repository

| Field | Detail |
| :--- | :--- |
| **Where** | `packages/server/lib/data/repository/author_invite_repository.dart:64-71`<br>`packages/server/lib/data/repository/attention_dismissible_sql.dart:107` |
| **What** | Pending author invites filter with inline readability predicate; attention SQL uses the same function in shared prelude fragments. |
| **Evidence** | Invite query: `AND public.beacon_can_read_content(i.beacon_id, $1)`. Dismissible SQL: `AND public.beacon_can_read_content(ii.beacon_id, $1)` inside `visibleWithSurface` / dismissible sets. |
| **Drift** | Invite path does not include tombstone OR branch used for dismissed inbox statuses; may be intentional, but the difference is undocumented outside SQL text. |
| **Severity** | low |
| **Fix scope** | server |
| **Suggested consolidation** | Named SQL fragment `beaconReadableOrTombstone(alias, viewer)` shared across attention + invite queries; document intentional exclusions. |

---

## Pair 6 — Shared UI vs feature-local widgets

### 6.1 My Work empty body bypasses design-system empty components

| Field | Detail |
| :--- | :--- |
| **Where** | `packages/client/lib/features/my_work/ui/widget/my_work_empty_body.dart:86-99`<br>`packages/client/lib/features/inbox/ui/widget/posts_tab_view.dart:42-47` |
| **What** | Inbox Posts tab uses `TenturaEmptyState`; My Work empty uses one-off layout. |
| **Evidence** | Posts: `TenturaEmptyState(icon: Icons.forum_outlined, title: l10n.postsTabEmpty, …)`. My Work: `Padding(padding: kPaddingAll, … Icon size 48, theme.textTheme.titleSmall`. |
| **Drift** | My Work misses centralized empty-state a11y keys / action slot behavior tested on `TenturaEmptyState`. Operational lint rules apply unevenly (`no_raw_edge_insets` uses shared const but still ad-hoc typography). |
| **Severity** | low |
| **Fix scope** | client |
| **Suggested consolidation** | Compose `TenturaEmptyState` with My Work–specific actions (inbox CTA, constellation link). |

### 6.2 Lifecycle pill: `BeaconCardPill` vs feature-local read-only pill

| Field | Detail |
| :--- | :--- |
| **Where** | `packages/client/lib/ui/widget/beacon_card_primitives.dart:571-608`<br>`packages/client/lib/features/beacon_view/ui/widget/beacon_operational_header_card.dart:325-350` |
| **What** | Shared uppercase status chip vs duplicate read-only pill in beacon view feature. |
| **Evidence** | Shared: `BeaconCardPill` with `label.toUpperCase()`, container colors from scheme. Feature: `BeaconCardPillReadOnly` — separate padding (`TenturaSpacing.cardPadding` / `iconText`), `labelMedium` w600, “read-only” copy. |
| **Drift** | Visual density and typography differ from My Work / inbox pills using `BeaconCardPill`; HUD read-only state won’t track design-system pill changes. |
| **Severity** | low |
| **Fix scope** | client |
| **Suggested consolidation** | Extend `BeaconCardPill` with `readOnly: true` variant or muted style; delete `BeaconCardPillReadOnly`. |

---

## Top 10 to consolidate first

1. **Centralize inbox readability SQL** (`attention_repository.dart:395-401` + `attention_sweep_repository.dart:657-664`) — high severity undo/feed mismatch risk.
2. **Unify `PostSummary`** (client inbox entity + server entity + `_toEntity` mapping) — stop collapsing `lastMessageAt` / missing `forwardedById`.
3. **Single clock on Post view** (`post_view_screen.dart:592` vs `cubit.now()`) — fixes mute/lifetime inconsistency.
4. **Post action menu builder** (overflow + info sheet) — one gating implementation.
5. **Shared forward opener** (Request nudge vs Post plain route) — kind-aware wrapper around `ForwardBeaconRoute`.
6. **Scroll pagination helper** (Activity stream + Updates pane) — one threshold implementation.
7. **Empty-state components** (My Work + Updates → `TenturaEmptyState` / `CaughtUpPanel` patterns).
8. **Post bud invite rows** vs forward picker primitives — shared checkbox+note row.
9. **`AuthorInvite` canonical model** in `lib/domain/entity/` — align status wire encoding.
10. **`BeaconCardPillReadOnly` → `BeaconCardPill`** — one lifecycle chip implementation.

---

## Appendix — Round A1 cross-check

| A1 finding | A2 verdict |
| :--- | :--- |
| **PostSummary duplication** (#5 A1) | **Confirmed** with new drift detail: client `_toEntity` merges timestamps; missing `forwardedById` (Pair 1.4 / 4.2). |
| **roomReplyExcerpt**, **MIME table**, **kUserHandleRegExp**, **GraphRepository pair**, **Coordination ports**, **master-detail helpers**, **revision RegExp** | Not re-listed (out of feature-pair scope); still valid per A1. |
| **Attention SQL** | **Extended**: A2 adds explicit readability-guard duplication between `attention_repository` and `attention_sweep_repository` (Pair 5.1). |

---

*Audit performed without code changes. All `Where` paths verified with `test -e` on 2026-10-30.*
