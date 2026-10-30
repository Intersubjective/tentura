# Duplication & Code Hygiene Audit Report (2026-10-30)

This audit documents duplications, copy-paste drift, dead/deprecated code, dormant-by-design paths, stale comments, and parallel abstractions across `packages/client/lib`, `packages/server/lib`, and `lib/`.

## Category Summary

| Category | Finding Count |
| :--- | :--- |
| **1. Duplicated Logic & Copy-Paste Drift** | 6 |
| **2. Dead Code & Deprecated Declarations** | 3 |
| **3. Stale Comments** | 2 |
| **4. Parallel Abstractions** | 2 |
| **5. Dormant by Design** | 2 |
| **Total** | **15** |

---

## 1. Duplicated Logic & Copy-Paste Drift

| # | Where | What | Evidence | Severity | Fix scope |
|---|---|---|---|---|---|
| 1 | `lib/consts.dart:30`<br>`packages/server/lib/consts/user_handle_consts.dart:7` | User handle validation pattern `kUserHandleRegExp` and `isValidUserHandleFormat` are duplicated verbatim between shared root consts and server consts. | `final RegExp kUserHandleRegExp = RegExp('^[a-z0-9_]{$kUserHandleMinLength,$kUserHandleMaxLength}\$');` | medium | `server` |
| 2 | `packages/server/lib/utils/sanitized_attachment_name.dart:3`<br>`packages/server/lib/domain/util/attachment_filename.dart:3` | Attachment path stripping logic `raw.split(RegExp(r'[/\\]')).last.trim()` duplicated across two utility files on server. | `var s = raw.split(RegExp(r'[/\\]')).last.trim();` | low | `server` |
| 3 | `packages/client/lib/features/beacon_threads/ui/util/room_reply_excerpt.dart:11`<br>`packages/server/lib/domain/util/room_reply_excerpt.dart:21` | Room reply body whitespace collapsing and 160-rune truncation logic duplicated between client UI util and server domain util. | `final collapsed = text.trim().replaceAll(RegExp(r'\s+'), ' ');` | medium | `shared` |
| 4 | `packages/client/lib/ui/widget/pending_attachments.dart:90`<br>`packages/server/lib/domain/use_case/beacon_room_case.dart:2172` | File extension to MIME mapping fallback table logic duplicated on client and server. | `static String _mimeFromExtension(String ext) {` | low | `shared` |
| 5 | `packages/client/lib/features/inbox/domain/entity/post_summary.dart:7`<br>`packages/server/lib/domain/entity/post_summary.dart:4` | `PostSummary` domain entity defined separately in client inbox feature and server domain with slight field naming divergence (`lastMessageAt` vs `lastActivityAt`). | `final class PostSummary {` | medium | `shared` |
| 6 | `packages/client/lib/data/service/invalidation_service.dart:242`<br>`packages/server/lib/api/controllers/websocket/path_handler/websocket_path_entity_changes.dart:17` | Revision number validation RegExp `r'^[0-9]+$'` duplicated between client invalidation service and server WS handler. | `static final _decimalRevision = RegExp(r'^[0-9]+$');` | low | `shared` |

---

## 2. Dead Code & Deprecated Declarations

| # | Where | What | Evidence | Severity | Fix scope |
|---|---|---|---|---|---|
| 1 | `packages/client/lib/design_system/tentura_responsive_scope.dart:132` | `@deprecated` wrapper function `myWorkMasterDetailSeparatorWidth` with no remaining calls in the codebase. | `double myWorkMasterDetailSeparatorWidth(TenturaTokens tt) => deskMasterDetailSeparatorWidth(tt);` | low | `client` |
| 2 | `packages/client/lib/design_system/tentura_responsive_scope.dart:121` | `deskMasterPaneWidth` and `deskFitsMasterDetail` helper functions for legacy master-detail UI where master-detail layout was removed. | `/// Master list width for expanded master–detail shells. Production Inbox/My Work no longer call this;` | low | `client` |
| 3 | `packages/client/lib/features/graph/ui/bloc/graph_cubit.dart:451` | `@deprecated` method `selectNode` / `isCurrentFocus` annotated on `GraphCubit` superseded by newer graph navigation state handlers. | `/// @deprecated Use [isCurrentFocus], [canPageMore], and [handleNodeTap].` | low | `client` |

---

## 3. Stale Comments

| # | Where | What | Evidence | Severity | Fix scope |
|---|---|---|---|---|---|
| 1 | `packages/client/lib/domain/attention/attention_case.dart:627` | Comments in attention domain logic referring to legacy `U18c` retired totals (`activityUnreadTotal`, `myWorkUnreadTotal`, `needsYouTotal`). | `// `seen_at` is not in it, so a read must not move it. (U18c retired the` | low | `client` |
| 2 | `packages/client/lib/features/graph/domain/layout/radial_hop_positions.dart:215` | Comments referring to legacy 30-degree layout steps in graph layout logic. | `/// Amenity chord matching the legacy 30° step at [ringGap].` | low | `client` |

---

## 4. Parallel Abstractions

| # | Where | What | Evidence | Severity | Fix scope |
|---|---|---|---|---|---|
| 1 | `packages/client/lib/features/graph/data/repository/forwards_graph_repository.dart:25`<br>`packages/client/lib/features/graph/data/repository/graph_repository.dart:19` | `ForwardsGraphRepository` and `GraphRepository` both implement `GraphSourceRepository`, creating two parallel graph data repositories for graph fetching. | `class ForwardsGraphRepository implements GraphSourceRepository {` | medium | `client` |
| 2 | `packages/server/lib/domain/port/coordination_item_repository_port.dart:7`<br>`packages/server/lib/domain/port/coordination_repository_port.dart:5` | Server port abstractions `CoordinationItemRepositoryPort` and `CoordinationRepositoryPort` overlap in managing coordination items and plan item state. | `abstract class CoordinationItemRepositoryPort {` | medium | `server` |

---

## 5. Dormant by Design

*Note: Per design requirements, item-thread infrastructure code (`DORMANT(item-threads)`) is deliberately retained for future sub-discussions in Requests. The Lobby branch for Request Questions is actively live.*

| # | Where | What | Evidence | Severity | Fix scope |
|---|---|---|---|---|---|
| 1 | `packages/server/lib/data/database/table/beacon_room_messages.dart:73` | Database schema column `thread_item_id` nullable support retained for item-thread scope. | `// DORMANT(item-threads): nullable column for item-thread scope (never written in production).` | N/A | `server` |
| 2 | `packages/client/lib/features/beacon_threads/data/repository/beacon_threads_repository.dart:177` | `threadItemId` filter parameter in client repository methods held dormant for non-general item threads. | `// DORMANT(item-threads): threadItemId filters item-thread messages; always null in production.` | N/A | `client` |

---

## Top 10 to fix first

1. **Unify `kUserHandleRegExp` and validation** (`lib/consts.dart:30` and `packages/server/lib/consts/user_handle_consts.dart:7`): Remove server copy and import from shared root `lib/consts.dart` to prevent handle validation rule drift.
2. **Consolidate `PostSummary` entity** (`packages/client/lib/features/inbox/domain/entity/post_summary.dart` vs `packages/server/lib/domain/entity/post_summary.dart`): Align field names (`lastMessageAt` vs `lastActivityAt`) and move shared entity definition into root `lib/domain/entity/`.
3. **Consolidate `roomReplyExcerpt` logic** (`packages/client/lib/features/beacon_threads/ui/util/room_reply_excerpt.dart` and `packages/server/lib/domain/util/room_reply_excerpt.dart`): Extract core rune truncation helper to `tentura_root` package.
4. **Clean up `attachment_filename` and `sanitized_attachment_name` duplication** (`packages/server/lib/utils/sanitized_attachment_name.dart` and `packages/server/lib/domain/util/attachment_filename.dart`): Merge file path extraction and character sanitization into single utility module.
5. **Harmonize `_mimeFromExtension` mapping** (`packages/client/lib/ui/widget/pending_attachments.dart` and `packages/server/lib/domain/use_case/beacon_room_case.dart`): Share common extension-to-MIME lookup map in root utilities.
6. **Harmonize `GraphRepository` and `ForwardsGraphRepository`** (`packages/client/lib/features/graph/`): Unify graph source repositories under single `GraphRepository` contract.
7. **Clean up obsolete master-detail helpers** (`packages/client/lib/design_system/tentura_responsive_scope.dart:121, 132`): Remove deprecated `myWorkMasterDetailSeparatorWidth` and dead `deskMasterPaneWidth`/`deskFitsMasterDetail` functions.
8. **Consolidate revision pattern `_decimalRevision`** (`packages/client/lib/data/service/invalidation_service.dart:242` and `packages/server/lib/api/controllers/websocket/path_handler/websocket_path_entity_changes.dart:17`): Place in shared constants.
9. **Review `CoordinationItemRepositoryPort` vs `CoordinationRepositoryPort`** (`packages/server/lib/domain/port/`): Refactor overlapping server repository ports to streamline domain boundaries.
10. **Clean up stale comments referencing retired `U18c` totals** (`packages/client/lib/domain/attention/attention_case.dart:627`): Update doc comments to accurately reflect current attention architecture.
