import 'dart:async';

import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart'
    show ThreadHostCubit;
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart'
    show BeaconViewCubit;
import 'package:uuid/uuid.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/localizable.dart';
import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/quoted_fact.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_mention_span.dart';
import 'package:tentura/domain/entity/room_poll_data.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/entity/room_read_watermark.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../domain/coordination_item_room_sync.dart';
import '../../domain/entity/beacon_room_invalidation.dart';
import '../../domain/entity/committed_mention.dart';
import '../../domain/entity/request_thread.dart';
import '../../domain/entity/room_seen_outcome.dart';
import '../../domain/exception/beacon_fact_already_pinned_exception.dart';
import '../../domain/room_host.dart';
import '../../domain/exception/beacon_fact_card_exceptions.dart';
import '../../domain/use_case/beacon_threads_case.dart';
import '../message/beacon_room_fact_messages.dart';
import '../message/discussion_read_only_message.dart';
import '../util/room_reply_excerpt.dart';
import 'room_message_reaction_local.dart';
import 'room_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'room_state.dart';

enum _RoomRefreshScope { messages, facts, full }

/// Observations that arrived after the active refresh began (and delete
/// tombstones for that same refresh). Discarded when the refresh ends.
final class _MessageRefreshOverlay {
  final carriedById = <String, RoomMessage>{};
  final deletedIds = <String>{};
}

class RoomCubit extends Cubit<RoomState> {
  RoomCubit({
    required String beaconId,
    String? threadItemId,
    DateTime? initialUnreadAnchorAt,
    BeaconThreadsCase? beaconRoomCase,
    CoordinationItemRoomSync? coordinationItemRoomSync,
    PresenceRepository? presenceRepository,
    UiEffectPort? effects,
    this.capabilities = const RoomCapabilities.request(),
  }) : _case = beaconRoomCase ?? GetIt.I<BeaconThreadsCase>(),
       _itemSync =
           coordinationItemRoomSync ?? GetIt.I<CoordinationItemRoomSync>(),
       _presenceRepository =
           presenceRepository ?? GetIt.I<PresenceRepository>(),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(
         RoomState(
           beaconId: beaconId,
           threadItemId: threadItemId,
           unreadAnchorAt: initialUnreadAnchorAt,
           myUserId: GetIt.I<ProfileCubit>().state.profile.id,
           status: const StateIsLoading(),
         ),
       ) {
    _refreshSub = _case.beaconRoomInvalidations.listen(_onRoomInvalidation);
    _catchUpsSub = _case.catchUps.listen(
      (_) => _requestRefresh(scope: _RoomRefreshScope.full),
      cancelOnError: false,
    );
    if (threadItemId == null) {
      _itemSyncSub = _itemSync.changes
          .where((item) => item.beaconId == beaconId)
          .listen(applyCoordinationItemSnapshot);
    }
    unawaited(load());
  }

  final BeaconThreadsCase _case;

  /// Request-only fetches this room skips when a capability is off.
  final RoomCapabilities capabilities;

  final CoordinationItemRoomSync _itemSync;

  final PresenceRepository _presenceRepository;

  final UiEffectPort _effects;

  void _showMessage(LocalizableMessage message) {
    _effects.emit(ShowMessage(message));
  }

  void _showSnackError(Object error) {
    _effects.emit(ShowError(error));
    if (!isClosed) {
      emit(state.copyWith(status: const StateIsSuccess(), loadError: null));
    }
  }

  /// Sync lifecycle from [BeaconViewCubit] (via [ThreadHostCubit]). Clears an
  /// in-progress reply when writes become locked.
  void syncBeaconStatus(BeaconStatus status) {
    if (isClosed) return;
    final wasWritable = state.canWriteDiscussion;
    final clearReply =
        wasWritable &&
        !status.allowsDiscussionWrites &&
        state.replyTarget != null;
    emit(
      state.copyWith(
        beaconStatus: status,
        replyTarget: clearReply ? null : state.replyTarget,
      ),
    );
  }

  /// Null status → let the server decide (tests / before content load).
  bool get _blocksDiscussionWrite {
    final s = state.beaconStatus;
    if (s == null) return false;
    return !s.allowsDiscussionWrites;
  }

  bool get _blocksPlanUpdate {
    final s = state.beaconStatus;
    if (s == null) return false;
    return !s.allowsCoordination || !state.isPlanEditor;
  }

  bool _rejectIfDiscussionReadOnly() {
    if (!_blocksDiscussionWrite) return false;
    _showMessage(const DiscussionReadOnlyMessage());
    return true;
  }

  bool _rejectIfPlanUpdateBlocked() {
    if (!_blocksPlanUpdate) return false;
    _showMessage(const DiscussionPlanUpdateBlockedMessage());
    return true;
  }

  late final StreamSubscription<BeaconRoomInvalidation> _refreshSub;

  late final StreamSubscription<void> _catchUpsSub;

  StreamSubscription<CoordinationItem>? _itemSyncSub;

  String? _pendingThreadMessageId;
  String? _pendingThreadItemId;

  static const _uuid = Uuid();

  final Set<String> _pendingLocalMessageIds = {};

  final Map<String, RoomMessage> _deferredOwnPaintByServerId = {};

  _MessageRefreshOverlay? _activeMessageRefreshOverlay;

  final Set<String> _pendingLocalDeleteIds = {};

  static const _kMaxPinnedOffWindow = 20;

  final _pinnedOffWindowMessages = <String, RoomMessage>{};

  /// Wall-clock time of the last bottom-of-list callback (`markReadToBottom`).
  DateTime? _atBottomSince;

  /// Wall-clock time when the newest peer-authored message was first observed.
  DateTime? _lastInboundAt;

  bool _initialLoadDone = false;
  bool _refreshInProgress = false;
  _RoomRefreshScope? _queuedRefreshScope;
  bool _queuedRefreshSilent = true;

  void _onRoomInvalidation(BeaconRoomInvalidation invalidation) {
    if (isClosed || invalidation.beaconId != state.beaconId) return;

    if (invalidation.entityType == BeaconRoomEntityType.roomMessage &&
        invalidation.operation == RealtimeOperation.delete) {
      final id = invalidation.messageId?.trim();
      if (id != null && id.isNotEmpty) {
        _applyConfirmedMessageDelete(id);
      }
      unawaited(_requestRefresh(scope: _RoomRefreshScope.messages));
      return;
    }

    if (invalidation.entityType == BeaconRoomEntityType.roomMessage &&
        invalidation.operation == RealtimeOperation.insert &&
        invalidation.paint != null) {
      final paint = invalidation.paint!;
      if (paint.threadItemId != state.threadItemId) {
        return;
      }
      final message = _case.roomMessageFromPaint(
        paint: paint,
        currentMessages: state.messages,
        participants: state.participants,
      );
      if (message.authorId == state.myUserId &&
          _pendingLocalMessageIds.isNotEmpty) {
        _deferredOwnPaintByServerId[message.id] = message;
        return;
      }
      _activeMessageRefreshOverlay?.carriedById[message.id] = message;
      _mergePaintedMessage(message);
      return;
    }

    if (invalidation.entityType == BeaconRoomEntityType.roomSeenPeer) {
      final seenPeer = invalidation.seenPeer;
      if (seenPeer != null) {
        _applyPeerWatermark(seenPeer.userId, seenPeer.lastSeenAt);
      }
      return;
    }

    final scope = switch (invalidation.entityType) {
      BeaconRoomEntityType.roomMessage ||
      BeaconRoomEntityType.roomReaction ||
      BeaconRoomEntityType.roomPoll ||
      BeaconRoomEntityType.roomBaton => _RoomRefreshScope.messages,
      BeaconRoomEntityType.factCard => _RoomRefreshScope.facts,
      _ => _RoomRefreshScope.full,
    };
    unawaited(_requestRefresh(scope: scope));
  }

  void _mergePaintedMessage(RoomMessage message) {
    if (isClosed) return;
    if (message.authorId != state.myUserId) {
      _lastInboundAt = DateTime.now().toUtc();
    }
    emit(
      state.copyWith(
        messages: _sortMessages(
          _dedupeMessages([...state.messages, message]),
        ),
      ),
    );
  }

  void _flushDeferredOwnPaints() {
    if (_deferredOwnPaintByServerId.isEmpty || isClosed) {
      return;
    }
    var messages = List<RoomMessage>.from(state.messages);
    for (final painted in _deferredOwnPaintByServerId.values) {
      _activeMessageRefreshOverlay?.carriedById[painted.id] = painted;
      messages = _replaceOrAppendMessage(messages, painted);
    }
    _deferredOwnPaintByServerId.clear();
    emit(
      state.copyWith(
        messages: _sortMessages(_dedupeMessages(messages)),
      ),
    );
  }

  void _carryAcrossActiveRefresh(RoomMessage message) {
    _activeMessageRefreshOverlay?.carriedById[message.id] = message;
  }

  void _applyConfirmedMessageDelete(String id) {
    final overlay = _activeMessageRefreshOverlay;
    if (overlay != null) {
      overlay.carriedById.remove(id);
      overlay.deletedIds.add(id);
    }
    _deferredOwnPaintByServerId.remove(id);
    _pinnedOffWindowMessages.remove(id);
    if (isClosed) return;
    final clearReply = state.replyTarget?.id == id;
    emit(
      state.copyWith(
        messages: state.messages.where((m) => m.id != id).toList(),
        pinnedJumpMessageIds: _pinnedOffWindowMessages.keys.toList(
          growable: false,
        ),
        replyTarget: clearReply ? null : state.replyTarget,
      ),
    );
  }

  Future<void> _requestRefresh({
    required _RoomRefreshScope scope,
    bool silent = true,
  }) async {
    if (isClosed) return;
    if (_refreshInProgress) {
      final alreadyQueued = _queuedRefreshScope != null;
      final queued = _queuedRefreshScope;
      _queuedRefreshScope = queued == null || queued == scope
          ? scope
          : _RoomRefreshScope.full;
      _queuedRefreshSilent = alreadyQueued
          ? _queuedRefreshSilent && silent
          : silent;
      return;
    }
    await _runRefresh(scope: scope, silent: silent);
  }

  Future<void> _runRefresh({
    required _RoomRefreshScope scope,
    required bool silent,
  }) async {
    _refreshInProgress = true;
    final overlay = _MessageRefreshOverlay();
    _activeMessageRefreshOverlay = overlay;
    try {
      switch (scope) {
        case _RoomRefreshScope.full:
          await _fetchFullSnapshot(silent: silent, overlay: overlay);
        case _RoomRefreshScope.messages:
          await _fetchMessagesSnapshot(silent: silent, overlay: overlay);
        case _RoomRefreshScope.facts:
          await _fetchFactCardsSnapshot(silent: silent);
      }
    } finally {
      if (identical(_activeMessageRefreshOverlay, overlay)) {
        _activeMessageRefreshOverlay = null;
      }
      _refreshInProgress = false;
      if (_queuedRefreshScope != null && !isClosed) {
        final nextScope = _queuedRefreshScope!;
        final nextSilent = _queuedRefreshSilent;
        _queuedRefreshScope = null;
        _queuedRefreshSilent = true;
        unawaited(_requestRefresh(scope: nextScope, silent: nextSilent));
      }
    }
  }

  /// Fact-list-only refresh (factCard invalidation, fact edits); leaves
  /// messages and participants untouched.
  Future<void> _fetchFactCardsSnapshot({required bool silent}) async {
    if (state.threadItemId != null || !capabilities.facts) return;
    try {
      final factCards = await _case.fetchFactCards(state.beaconId);
      if (!isClosed) emit(state.copyWith(factCards: factCards));
    } on Object catch (e) {
      if (!isClosed && !silent) _showSnackError(e);
    }
  }

  /// Patches joined item snapshots on all messages referencing the item.
  /// Patches each message's linked-item reply counts from [items] (keyed by id).
  static List<RoomMessage> _joinCoordinationCounts(
    List<RoomMessage> messages,
    List<CoordinationItem> items,
  ) {
    if (items.isEmpty) return messages;
    final byId = <String, CoordinationItem>{
      for (final it in items) it.id: it,
    };
    return [
      for (final m in messages)
        if (m.linkedItemId != null && byId[m.linkedItemId] != null)
          m.copyWith(
            linkedItemMessageCount: byId[m.linkedItemId]!.messageCount,
            linkedItemUnreadCount: byId[m.linkedItemId]!.unreadCount,
          )
        else
          m,
    ];
  }

  void applyCoordinationItemSnapshot(CoordinationItem item) {
    if (isClosed || state.threadItemId != null) return;
    final patched = state.messages.map((m) {
      if (m.linkedItemId != item.id) return m;
      return m.copyWith(
        linkedItemKind: item.kind.value,
        linkedItemStatus: item.status.value,
        linkedItemTitle: item.title,
        linkedItemBody: item.body,
        linkedItemCreatorId: item.creatorId,
        linkedItemCreatedAt: item.createdAt,
        linkedItemUpdatedAt: item.updatedAt,
        linkedItemLinkedMessageId: item.linkedMessageId,
        linkedItemResolvedAt: item.resolvedAt,
      );
    }).toList();
    emit(state.copyWith(messages: patched));
  }

  Future<void> load() =>
      _requestRefresh(scope: _RoomRefreshScope.full, silent: false);

  Future<void> reloadMessages({bool silent = false}) =>
      _requestRefresh(scope: _RoomRefreshScope.full, silent: silent);

  void clearScrollToMessageTarget() {
    if (state.scrollToMessageId != null) {
      emit(state.copyWith(scrollToMessageId: null));
    }
  }

  void clearPendingFactsFocus() {
    if (state.pendingFactsFocusFactId != null) {
      emit(state.copyWith(pendingFactsFocusFactId: null));
    }
  }

  void requestScrollToMessage(String messageId) {
    emit(state.copyWith(scrollToMessageId: messageId));
  }

  /// Ineligible when the message has no server id yet.
  static bool canReplyTo(RoomMessage m) => !m.id.startsWith('local:');

  void startReplyTo(RoomMessage message) {
    if (!canReplyTo(message)) return;
    emit(state.copyWith(replyTarget: message));
  }

  void cancelReply() {
    if (state.replyTarget != null) {
      emit(state.copyWith(replyTarget: null));
    }
  }

  void setPendingQuotedFact(BeaconFactCard card) {
    emit(
      state.copyWith(
        pendingQuotedFact: QuotedFact(
          factCardId: card.id,
          seq: card.revisionSeq,
          currentSeq: card.revisionSeq,
          status: card.status,
          factText: card.factText,
          pinnedById: card.pinnedBy,
          pinnedByTitle: card.pinnedByTitle,
          visibility: card.visibility,
          attachments: card.attachments,
        ),
      ),
    );
  }

  void clearPendingQuotedFact() {
    if (state.pendingQuotedFact != null) {
      emit(state.copyWith(pendingQuotedFact: null));
    }
  }

  Future<bool> jumpToRepliedMessage(String messageId) async {
    final id = messageId.trim();
    if (id.isEmpty) return false;
    if (state.messages.any((m) => m.id == id)) {
      requestScrollToMessage(id);
      return true;
    }
    RoomMessage? target;
    try {
      target = await _case.fetchMessageTarget(
        beaconId: state.beaconId,
        messageId: id,
      );
    } on Object {
      target = null;
    }
    if (isClosed) return false;
    if (target == null) {
      _showMessage(const RoomReplyTargetUnavailableMessage());
      return false;
    }
    _pinOffWindow(target);
    emit(
      state.copyWith(
        messages: _mergeMessages(
          serverRows: state.messages,
          overlay: _activeMessageRefreshOverlay,
        ),
        pinnedJumpMessageIds: _pinnedOffWindowMessages.keys.toList(
          growable: false,
        ),
        scrollToMessageId: id,
      ),
    );
    return true;
  }

  void _pinOffWindow(RoomMessage target) {
    if (_pinnedOffWindowMessages.containsKey(target.id)) {
      _pinnedOffWindowMessages.remove(target.id);
    } else if (_pinnedOffWindowMessages.length >= _kMaxPinnedOffWindow) {
      _pinnedOffWindowMessages.remove(_pinnedOffWindowMessages.keys.first);
    }
    _pinnedOffWindowMessages[target.id] = target;
  }

  List<RoomMessage> _mergeMessages({
    required List<RoomMessage> serverRows,
    _MessageRefreshOverlay? overlay,
  }) {
    final deleted = <String>{
      ...?overlay?.deletedIds,
      ..._pendingLocalDeleteIds,
    };
    final merged = _dedupeMessages([
      ..._pinnedOffWindowMessages.values,
      ...?overlay?.carriedById.values,
      ...serverRows,
      ...state.messages.where(
        (m) => _pendingLocalMessageIds.contains(m.id),
      ),
    ]);
    final filtered = deleted.isEmpty
        ? merged
        : [
            for (final m in merged)
              if (!deleted.contains(m.id)) m,
          ];
    return _sortMessages(filtered);
  }

  /// Queues scrolling to a coordination item’s room thread after messages load
  /// (or immediately if messages are already present). Cleared when applied.
  void prepareThreadScroll({
    String? messageId,
    String? coordinationItemId,
  }) {
    _pendingThreadMessageId = _trimOrNull(messageId);
    _pendingThreadItemId = _trimOrNull(coordinationItemId);
    if (state.messages.isNotEmpty &&
        (_pendingThreadMessageId != null || _pendingThreadItemId != null)) {
      if (_pendingThreadMessageId != null &&
          !state.messages.any((m) => m.id == _pendingThreadMessageId)) {
        unawaited(
          _requestRefresh(scope: _RoomRefreshScope.full),
        );
        return;
      }
      _applyPendingThreadScroll(state.messages);
    }
  }

  static String? _trimOrNull(String? s) {
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  void _applyPendingThreadScroll(List<RoomMessage> messages) {
    if (_pendingThreadMessageId == null && _pendingThreadItemId == null) {
      return;
    }
    var target = _pendingThreadMessageId;
    if (target == null || !messages.any((m) => m.id == target)) {
      target = null;
      final iid = _pendingThreadItemId;
      if (iid != null) {
        for (final m in messages) {
          if (m.linkedItemId == iid) {
            target = m.id;
            break;
          }
        }
      }
    }
    if (target == null) {
      return;
    }
    _pendingThreadMessageId = null;
    _pendingThreadItemId = null;
    emit(state.copyWith(scrollToMessageId: null));
    if (!isClosed) {
      emit(state.copyWith(scrollToMessageId: target));
    }
  }

  /// Moves the read watermark to the newest loaded message (clears in-chat unread).
  void _advanceReadAnchorToLatestLoaded() {
    final messages = state.messages;
    if (messages.isEmpty || isClosed) return;
    final latest = messages.last.createdAt;
    final anchor = state.unreadAnchorAt;
    if (anchor == null || latest.isAfter(anchor)) {
      emit(state.copyWith(unreadAnchorAt: latest));
    }
    _case.observeReadThrough(
      state.beaconId,
      latest,
      threadId: state.threadItemId ?? RequestThread.generalId,
    );
  }

  /// Records when peer-authored messages first appear locally, so [close]
  /// can tell whether the reader reached the bottom after the last inbound
  /// message arrived.
  void _noteInboundMessages(
    List<RoomMessage> previous,
    List<RoomMessage> next,
  ) {
    final previousIds = {for (final message in previous) message.id};
    for (final message in next) {
      if (!previousIds.contains(message.id) &&
          message.authorId != state.myUserId) {
        _lastInboundAt = DateTime.now().toUtc();
        return;
      }
    }
  }

  /// Advances the read watermark to the newest loaded message and flushes seen
  /// to the server. Called when the user reaches the bottom of the list.
  Future<void> markReadToBottom() async {
    if (state.messages.isEmpty) return;

    _atBottomSince = DateTime.now().toUtc();
    _advanceReadAnchorToLatestLoaded();
    await markSeenNowIfNeeded();
  }

  /// Flushes the read watermark to the server when the newest loaded message
  /// is newer than the last server-confirmed watermark (idle readers keep
  /// advancing it). With [force] the watermark check is skipped — used by
  /// [close] after it has decided the reader was at the bottom.
  Future<void> markSeenNowIfNeeded({bool force = false}) async {
    if (!_initialLoadDone) {
      return;
    }
    final newestLoaded = state.messages.isEmpty
        ? null
        : state.messages.last.createdAt;
    if (!force) {
      final syncedAt = _case.syncedAt(
        state.beaconId,
        threadId: state.threadItemId ?? RequestThread.generalId,
      );
      if (newestLoaded == null ||
          (syncedAt != null && !newestLoaded.isAfter(syncedAt))) {
        return;
      }
    }
    _advanceReadAnchorToLatestLoaded();
    final readThrough = state.unreadAnchorAt ?? newestLoaded;
    if (readThrough == null) {
      return;
    }
    try {
      final outcome = await _case.markRoomSeenIfAllowed(
        beaconId: state.beaconId,
        threadItemId: state.threadItemId,
        readThroughAt: readThrough,
      );
      switch (outcome) {
        case RoomSeenSucceeded():
          if (!isClosed) {
            emit(state.copyWith(pendingMarkSeen: false));
          }
        case RoomSeenDenied():
        case RoomSeenFailed():
      }
    } on Object {
      /* non-fatal; retry on next bottom / exit */
    }
  }

  Future<void> _fetchFullSnapshot({
    required bool silent,
    required _MessageRefreshOverlay overlay,
  }) async {
    if (isClosed) return;
    if (!silent) {
      emit(state.copyWith(status: const StateIsLoading()));
    }
    try {
      final inThread = state.threadItemId != null;
      final rawMessages = await _case.fetchMessages(
        beaconId: state.beaconId,
        threadItemId: state.threadItemId,
      );
      final pendingMessageId = _pendingThreadMessageId;
      final target =
          pendingMessageId == null ||
              rawMessages.any((message) => message.id == pendingMessageId)
          ? null
          : await _case.fetchMessageTarget(
              beaconId: state.beaconId,
              messageId: pendingMessageId,
            );
      final participantsF = _case.fetchParticipants(state.beaconId);
      final roomStateF = inThread || !capabilities.plan
          ? Future<BeaconRoomState?>.value()
          : _case.fetchBeaconRoomState(state.beaconId);
      final factCardsF = inThread || !capabilities.facts
          ? Future.value(const <BeaconFactCard>[])
          : _case.fetchFactCards(state.beaconId);
      final openCoordinationBlockerF = inThread || !capabilities.blocker
          ? Future<CoordinationItem?>.value()
          : _case.fetchOpenCoordinationBlocker(state.beaconId);
      final currentCoordinationPlanF = inThread || !capabilities.plan
          ? Future<CoordinationItem?>.value()
          : _case.fetchCurrentCoordinationPlan(state.beaconId);
      // Join thread reply counts (messageCount/unreadCount) onto messages by
      // linkedItemId — these are not in the gql message snapshot.
      final coordinationItemsF = inThread || !capabilities.coordinationItems
          ? Future.value(const <CoordinationItem>[])
          : _case.fetchCoordinationItems(state.beaconId);
      // Non-fatal: a watermark failure must not fail the room load.
      final watermarksF = inThread
          ? Future<List<RoomReadWatermark>?>.value()
          : _case
                .fetchMainRoomReadWatermarks(state.beaconId)
                .then<List<RoomReadWatermark>?>(
                  (value) => value,
                  onError: (Object _) => null,
                );
      final (
        participants,
        roomState,
        factCards,
        openCoordinationBlocker,
        currentCoordinationPlan,
        coordinationItems,
        fetchedWatermarks,
      ) = await (
        participantsF,
        roomStateF,
        factCardsF,
        openCoordinationBlockerF,
        currentCoordinationPlanF,
        coordinationItemsF,
        watermarksF,
      ).wait;
      final readWatermarks = _mergeReadWatermarks(
        state.readWatermarks,
        fetchedWatermarks,
      );
      final serverRows = _joinCoordinationCounts(
        [
          ...rawMessages,
          ?target,
        ],
        coordinationItems,
      );
      final messages = _mergeMessages(
        serverRows: serverRows,
        overlay: overlay,
      );

      if (isClosed) return;

      var anchor = state.unreadAnchorAt;
      if (!inThread) {
        final localSeen = _case.readThrough(state.beaconId);
        if (localSeen != null) {
          if (anchor == null || localSeen.isAfter(anchor)) {
            anchor = localSeen;
          }
        }
        final myId = GetIt.I<ProfileCubit>().state.profile.id;
        DateTime? serverSeen;
        for (final p in participants) {
          if (p.userId == myId) {
            serverSeen = p.lastSeenRoomAt;
            break;
          }
        }
        // Authors without a participant row still get an anchor from their
        // own read watermark.
        final watermarkSeen =
            (readWatermarks ?? state.readWatermarks)[myId]?.lastSeenAt;
        if (watermarkSeen != null &&
            (serverSeen == null || watermarkSeen.isAfter(serverSeen))) {
          serverSeen = watermarkSeen;
        }
        if (serverSeen != null) {
          _case.observeServerReadThrough(state.beaconId, serverSeen);
        }
        if (anchor == null) {
          anchor = serverSeen;
        } else if (serverSeen != null && serverSeen.isAfter(anchor)) {
          anchor = serverSeen;
        }
      }

      if (!isClosed) {
        _initialLoadDone = true;
        _noteInboundMessages(state.messages, messages);
        final syncedAt = _case.syncedAt(
          state.beaconId,
          threadId: state.threadItemId ?? RequestThread.generalId,
        );
        emit(
          state.copyWith(
            messages: messages,
            participants: participants,
            participantsLoaded: true,
            readWatermarks: readWatermarks ?? state.readWatermarks,
            readWatermarksLoaded:
                state.readWatermarksLoaded || readWatermarks != null,
            factCards: factCards,
            roomState: roomState,
            openCoordinationBlocker: openCoordinationBlocker,
            currentCoordinationPlan: currentCoordinationPlan,
            unreadAnchorAt: anchor,
            myUserId: GetIt.I<ProfileCubit>().state.profile.id,
            pendingMarkSeen:
                messages.isNotEmpty &&
                (syncedAt == null || messages.last.createdAt.isAfter(syncedAt)),
            loadError: null,
            status: const StateIsSuccess(),
          ),
        );
        if (!inThread) {
          _watchRoomPresence(participants);
        }
        if (!isClosed) {
          _applyPendingThreadScroll(messages);
        }
      }
    } on Object catch (e) {
      if (!isClosed) {
        if (state.messages.isEmpty) {
          emit(state.copyWith(loadError: e, status: const StateIsSuccess()));
        } else if (!silent) {
          _showSnackError(e);
        }
      }
    } finally {
      /* refresh queue handled by _runRefresh */
    }
  }

  Future<void> _fetchMessagesSnapshot({
    required bool silent,
    required _MessageRefreshOverlay overlay,
  }) async {
    if (isClosed) return;
    try {
      final rawMessages = await _case.fetchMessages(
        beaconId: state.beaconId,
        threadItemId: state.threadItemId,
      );
      final preservedCounts = <String, ({int messageCount, int unreadCount})>{};
      for (final message in state.messages) {
        if (_pendingLocalMessageIds.contains(message.id)) {
          continue;
        }
        final linkedItemId = message.linkedItemId;
        if (linkedItemId != null) {
          preservedCounts[linkedItemId] = (
            messageCount: message.linkedItemMessageCount,
            unreadCount: message.linkedItemUnreadCount,
          );
        }
      }
      final refreshed = [
        for (final message in rawMessages)
          if (message.linkedItemId != null &&
              preservedCounts.containsKey(message.linkedItemId))
            message.copyWith(
              linkedItemMessageCount:
                  preservedCounts[message.linkedItemId!]!.messageCount,
              linkedItemUnreadCount:
                  preservedCounts[message.linkedItemId!]!.unreadCount,
            )
          else
            message,
      ];
      if (!isClosed) {
        final merged = _mergeMessages(
          serverRows: refreshed,
          overlay: overlay,
        );
        _noteInboundMessages(state.messages, merged);
        emit(
          state.copyWith(
            messages: merged,
            loadError: null,
          ),
        );
      }
    } on Object catch (e) {
      if (!isClosed && !silent) {
        _showSnackError(e);
      }
    }
  }

  /// Presence-only patch: writes max(existing, incoming) into a new map;
  /// emits only when the watermark advances.
  void _applyPeerWatermark(String userId, DateTime lastSeenAt) {
    if (isClosed) return;
    final existing = state.readWatermarks[userId];
    if (existing != null && !lastSeenAt.isAfter(existing.lastSeenAt)) {
      return;
    }
    final updated = Map<String, RoomReadWatermark>.of(state.readWatermarks);
    updated[userId] = existing == null
        ? RoomReadWatermark(userId: userId, lastSeenAt: lastSeenAt)
        : existing.copyWith(lastSeenAt: lastSeenAt);
    emit(state.copyWith(readWatermarks: updated));
  }

  /// Per-user max(fetched, existing) merge; null when [fetched] is null
  /// (watermark fetch failed or item-thread scope) so state stays untouched.
  static Map<String, RoomReadWatermark>? _mergeReadWatermarks(
    Map<String, RoomReadWatermark> existing,
    List<RoomReadWatermark>? fetched,
  ) {
    if (fetched == null) return null;
    final merged = Map<String, RoomReadWatermark>.of(existing);
    for (final watermark in fetched) {
      final current = merged[watermark.userId];
      if (current == null || watermark.lastSeenAt.isAfter(current.lastSeenAt)) {
        merged[watermark.userId] = watermark;
      }
    }
    return merged;
  }

  static List<RoomMessage> _dedupeMessages(List<RoomMessage> messages) {
    final byId = <String, RoomMessage>{};
    for (final message in messages) {
      byId[message.id] = message;
    }
    return byId.values.toList(growable: false);
  }

  static List<RoomMessage> _sortMessages(List<RoomMessage> messages) {
    final sorted = List<RoomMessage>.from(messages)
      ..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        if (byTime != 0) {
          return byTime;
        }
        return a.id.compareTo(b.id);
      });
    return sorted;
  }

  static List<RoomMessage> _replaceOrAppendMessage(
    List<RoomMessage> messages,
    RoomMessage message,
  ) {
    final idx = messages.indexWhere((m) => m.id == message.id);
    if (idx >= 0) {
      final updated = List<RoomMessage>.from(messages);
      updated[idx] = message;
      return updated;
    }
    return [...messages, message];
  }

  Future<void> updatePlan(String currentLine) async {
    if (_rejectIfPlanUpdateBlocked()) return;
    // Optimistically reflect the new pinned plan/status line so the HUD strip
    // updates instantly; load() below reconciles (and restores on error).
    final optimisticRoomState = state.roomState?.copyWith(
      currentLine: currentLine,
    );
    emit(
      state.copyWith(
        status: const StateIsLoading(),
        roomState: optimisticRoomState ?? state.roomState,
      ),
    );
    try {
      await _case.updateRoomNowLine(
        beaconId: state.beaconId,
        currentLine: currentLine,
      );
      await load();
    } on Object catch (e) {
      _showSnackError(e);
    }
  }

  Future<void> pinFactFromMessage({
    required String sourceMessageId,
    required String factText,
    required int visibility,
  }) async {
    if (_rejectIfDiscussionReadOnly()) return;
    final existing = state.factCards
        .where(
          (f) => f.sourceMessageId == sourceMessageId,
        )
        .firstOrNull;
    if (existing != null) {
      _showMessage(
        BeaconFactAlreadyPinnedSnackMessage(
          onOpenFacts: () => emit(
            state.copyWith(pendingFactsFocusFactId: existing.id),
          ),
        ),
      );
      return;
    }

    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.pinFact(
        beaconId: state.beaconId,
        factText: factText,
        visibility: visibility,
        sourceMessageId: sourceMessageId,
      );
      await load();
      _showMessage(const BeaconFactPinSuccessMessage());
    } on BeaconFactAlreadyPinnedException catch (e) {
      _showMessage(
        BeaconFactAlreadyPinnedSnackMessage(
          onOpenFacts: () => emit(
            state.copyWith(pendingFactsFocusFactId: e.factCardId),
          ),
        ),
      );
    } on Object catch (e) {
      _showSnackError(e);
    }
  }

  /// [baseRevisionSeq] is the revision of the card the edit sheet opened
  /// with, never a re-fetched one (plan §14.6).
  Future<void> correctFact({
    required String factCardId,
    required String newText,
    required int baseRevisionSeq,
    String? attachmentsJson,
  }) async {
    if (_rejectIfDiscussionReadOnly()) return;
    emit(
      state.copyWith(status: const StateIsLoading(), factEditConflict: null),
    );
    try {
      await _case.correctFact(
        beaconId: state.beaconId,
        factCardId: factCardId,
        newText: newText,
        baseRevisionSeq: baseRevisionSeq,
        attachmentsJson: attachmentsJson,
      );
      await _requestRefresh(scope: _RoomRefreshScope.facts, silent: false);
      if (!isClosed) emit(state.copyWith(status: const StateIsSuccess()));
      _showMessage(const BeaconFactEditSuccessMessage());
    } on BeaconFactEditConflictException {
      await _requestRefresh(scope: _RoomRefreshScope.facts, silent: false);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: const StateIsSuccess(),
          factEditConflict: state.factCards
              .where((f) => f.id == factCardId)
              .firstOrNull,
        ),
      );
    } on Object catch (e) {
      _showSnackError(e);
    }
  }

  void clearFactEditConflict() {
    if (state.factEditConflict != null) {
      emit(state.copyWith(factEditConflict: null));
    }
  }

  Future<void> removeFact({required String factCardId}) async {
    if (_rejectIfDiscussionReadOnly()) return;
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.removeFact(
        beaconId: state.beaconId,
        factCardId: factCardId,
      );
      await load();
      _showMessage(const BeaconFactRemoveSuccessMessage());
    } on Object catch (e) {
      _showSnackError(e);
    }
  }

  Future<void> setFactVisibility({
    required String factCardId,
    required int visibility,
  }) async {
    if (_rejectIfDiscussionReadOnly()) return;
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.setFactVisibility(
        beaconId: state.beaconId,
        factCardId: factCardId,
        visibility: visibility,
      );
      await load();
      _showMessage(const BeaconFactVisibilitySuccessMessage());
    } on Object catch (e) {
      _showSnackError(e);
    }
  }

  Future<bool> sendMessage({
    required String body,
    List<RoomPendingUpload> uploads = const [],
    List<CommittedMention> explicitMentions = const [],
  }) async {
    if (_rejectIfDiscussionReadOnly()) return false;
    final trimmed = body.trim();
    final quotedFact = state.pendingQuotedFact;
    if (trimmed.isEmpty && uploads.isEmpty && quotedFact == null) {
      return false;
    }
    final leadingTrimmedUnits = body.length - body.trimLeft().length;
    final trailingBoundary = body.trimRight().length;
    final normalizedMentions = [
      for (final mention in explicitMentions)
        if (mention.start >= leadingTrimmedUnits &&
            mention.end <= trailingBoundary)
          (
            userId: mention.userId,
            start: mention.start - leadingTrimmedUnits,
            end: mention.end - leadingTrimmedUnits,
          ),
    ];
    final target = state.replyTarget;
    final localId = 'local:${_uuid.v4()}';
    final profile = GetIt.I<ProfileCubit>().state.profile;
    final localMessage = RoomMessage(
      id: localId,
      beaconId: state.beaconId,
      authorId: profile.id,
      body: trimmed,
      createdAt: DateTime.now().toUtc(),
      author: profile,
      threadItemId: state.threadItemId,
      replyToMessageId: target?.id,
      replyToAuthorId: target?.authorId,
      replyToAuthorTitle: target?.author.shownName,
      replyToBodyExcerpt: target != null ? roomReplyExcerpt(target) : null,
      replyToHasAttachments: target?.attachments.isNotEmpty ?? false,
      mentionSpans: [
        for (final mention in normalizedMentions)
          RoomMessageMentionSpan(
            userId: mention.userId,
            offset: mention.start,
            length: mention.end - mention.start,
          ),
      ],
    );
    _pendingLocalMessageIds.add(localId);
    emit(
      state.copyWith(
        messages: _sortMessages(
          _dedupeMessages([...state.messages, localMessage]),
        ),
      ),
    );
    try {
      final serverId = await _case.createMessage(
        beaconId: state.beaconId,
        body: trimmed,
        threadItemId: state.threadItemId,
        replyToMessageId: target?.id,
        uploads: uploads,
        explicitMentionUserIds: [
          for (final mention in normalizedMentions) mention.userId,
        ],
        explicitMentionOffsets: [
          for (final mention in normalizedMentions) mention.start,
        ],
        explicitMentionLengths: [
          for (final mention in normalizedMentions) mention.end - mention.start,
        ],
        quotedFactCardId: quotedFact?.factCardId,
        quotedFactRevisionSeq: quotedFact?.seq,
      );
      _pendingLocalMessageIds.remove(localId);
      final deferred = serverId != null
          ? _deferredOwnPaintByServerId.remove(serverId)
          : null;
      final reconciled =
          deferred ?? localMessage.copyWith(id: serverId ?? localId);
      if (serverId != null) {
        _carryAcrossActiveRefresh(reconciled);
      }
      final withoutLocal = state.messages
          .where((message) => message.id != localId)
          .toList();
      final clearReply = state.replyTarget?.id == target?.id;
      final clearQuote =
          quotedFact != null &&
          state.pendingQuotedFact?.factCardId == quotedFact.factCardId;
      emit(
        state.copyWith(
          messages: _sortMessages(
            _dedupeMessages(
              _replaceOrAppendMessage(withoutLocal, reconciled),
            ),
          ),
          replyTarget: clearReply ? null : state.replyTarget,
          pendingQuotedFact: clearQuote ? null : state.pendingQuotedFact,
        ),
      );
      _flushDeferredOwnPaints();
      await markSeenNowIfNeeded();
      if (uploads.isNotEmpty) {
        unawaited(_requestRefresh(scope: _RoomRefreshScope.messages));
      }
      return true;
    } on Object catch (e) {
      _pendingLocalMessageIds.remove(localId);
      emit(
        state.copyWith(
          messages: state.messages
              .where((message) => message.id != localId)
              .toList(),
        ),
      );
      _flushDeferredOwnPaints();
      await _requestRefresh(
        scope: _RoomRefreshScope.messages,
      );
      _showSnackError(e);
      return false;
    }
  }

  Future<void> toggleReaction({
    required String messageId,
    required String emoji,
  }) async {
    if (_rejectIfDiscussionReadOnly()) return;
    final idx = state.messages.indexWhere((m) => m.id == messageId);
    final previousMessages = idx >= 0
        ? List<RoomMessage>.from(state.messages)
        : null;

    if (idx >= 0) {
      final optimistic = List<RoomMessage>.from(state.messages);
      optimistic[idx] = toggleRoomMessageReactionLocally(
        optimistic[idx],
        emoji,
        GetIt.I<ProfileCubit>().state.profile,
      );
      emit(state.copyWith(messages: optimistic));
    }

    try {
      await _case.toggleReaction(
        beaconId: state.beaconId,
        messageId: messageId,
        emoji: emoji,
      );
    } on Object catch (e) {
      if (previousMessages != null) {
        emit(state.copyWith(messages: previousMessages));
        _showSnackError(e);
      } else {
        _showSnackError(e);
      }
    }
  }

  Future<void> editMessage({
    required String messageId,
    required String newBody,
  }) async {
    if (_rejectIfDiscussionReadOnly()) return;
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.editMessage(
        beaconId: state.beaconId,
        messageId: messageId,
        body: newBody,
      );
      await load();
    } on Object catch (e) {
      _showSnackError(e);
    }
  }

  Future<void> deleteMessage({required String messageId}) async {
    if (_rejectIfDiscussionReadOnly()) return;
    final previousMessages = List<RoomMessage>.from(state.messages);
    final previousReplyTarget = state.replyTarget;
    final previousPinnedJumpIds = state.pinnedJumpMessageIds;
    final previousPinned = Map<String, RoomMessage>.from(
      _pinnedOffWindowMessages,
    );
    _pendingLocalDeleteIds.add(messageId);
    emit(
      state.copyWith(
        messages: state.messages.where((m) => m.id != messageId).toList(),
        replyTarget: state.replyTarget?.id == messageId
            ? null
            : state.replyTarget,
        pinnedJumpMessageIds: [
          for (final id in state.pinnedJumpMessageIds)
            if (id != messageId) id,
        ],
      ),
    );
    _pinnedOffWindowMessages.remove(messageId);
    try {
      await _case.deleteMessage(
        beaconId: state.beaconId,
        messageId: messageId,
      );
      _applyConfirmedMessageDelete(messageId);
      _pendingLocalDeleteIds.remove(messageId);
    } on Object catch (e) {
      _pendingLocalDeleteIds.remove(messageId);
      _pinnedOffWindowMessages
        ..clear()
        ..addAll(previousPinned);
      emit(
        state.copyWith(
          messages: previousMessages,
          replyTarget: previousReplyTarget,
          pinnedJumpMessageIds: previousPinnedJumpIds,
        ),
      );
      _showSnackError(e);
    }
  }

  Future<void> markMessageSemanticDone({required String messageId}) async {
    if (_rejectIfDiscussionReadOnly()) return;
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.markMessageSemanticDone(
        beaconId: state.beaconId,
        messageId: messageId,
      );
      await load();
    } on Object catch (e) {
      _showSnackError(e);
    }
  }

  Future<void> votePoll({
    required String messageId,
    required String pollingId,
    required List<String> variantIds,
    int? score,
  }) async {
    if (_rejectIfDiscussionReadOnly()) return;
    final idx = state.messages.indexWhere((m) => m.id == messageId);
    List<RoomMessage>? previousMessages;
    if (idx >= 0) {
      final msg = state.messages[idx];
      final poll = RoomPollData.tryParse(msg.pollDataJson);
      if (poll != null) {
        previousMessages = List<RoomMessage>.from(state.messages);
        final optimisticPoll = poll.withOptimisticVote(
          variantIds: variantIds,
          score: score,
        );
        final updated = msg.copyWith(pollDataJson: optimisticPoll.encode());
        final optimistic = List<RoomMessage>.from(state.messages)
          ..[idx] = updated;
        emit(state.copyWith(messages: optimistic));
      }
    }

    try {
      await _case.votePoll(
        pollingId: pollingId,
        variantIds: variantIds,
        score: score,
      );
      // Silent refresh: an optimistic vote is already shown, so reconcile in
      // the background without flipping to StateIsLoading — that would disable
      // the composer and block the keyboard right after voting on a poll.
      unawaited(_requestRefresh(scope: _RoomRefreshScope.messages));
    } on Object catch (e) {
      emit(
        state.copyWith(
          messages: previousMessages ?? state.messages,
        ),
      );
      _showSnackError(e);
    }
  }

  /// Author: asks [candidates] «Who'll take it?» on [messageId], then
  /// refetches so the author's card appears on the message.
  Future<void> batonCreate({
    required String messageId,
    required List<({String userId, int tier})> candidates,
  }) async {
    if (_rejectIfDiscussionReadOnly()) return;
    try {
      await _case.batonCreate(messageId: messageId, candidates: candidates);
      await _requestRefresh(scope: _RoomRefreshScope.messages);
    } on Object catch (e) {
      _showSnackError(e);
    }
  }

  /// Records the viewer's answer to a «Who'll take it?» baton, showing it
  /// at once and rolling it back when the request fails.
  Future<void> batonRespond({
    required String messageId,
    required String batonId,
    required bool canHelp,
  }) async {
    if (_rejectIfDiscussionReadOnly()) return;
    final idx = state.messages.indexWhere((m) => m.id == messageId);
    List<RoomMessage>? previousMessages;
    if (idx >= 0) {
      final msg = state.messages[idx];
      final baton = msg.baton;
      if (baton is RoomBatonCandidateData) {
        previousMessages = List<RoomMessage>.from(state.messages);
        final updated = msg.copyWith(
          baton: RoomBatonCandidateData(
            id: baton.id,
            status: baton.status,
            myResponse: canHelp
                ? RoomBatonResponse.canHelp
                : RoomBatonResponse.cantHelp,
            outcome: baton.outcome,
            taker: baton.taker,
          ),
        );
        emit(
          state.copyWith(
            messages: List<RoomMessage>.from(state.messages)..[idx] = updated,
          ),
        );
      }
    }

    try {
      await _case.batonRespond(batonId: batonId, canHelp: canHelp);
      // Silent refresh, like [votePoll]: the answer is already shown.
      unawaited(_requestRefresh(scope: _RoomRefreshScope.messages));
    } on Object catch (e) {
      emit(state.copyWith(messages: previousMessages ?? state.messages));
      _showSnackError(e);
    }
  }

  /// Author: picks who takes the baton (`null` user id = server picks), then
  /// refetches so the card shows the taker.
  Future<void> batonSelect({
    required String batonId,
    String? userId,
  }) async {
    if (_rejectIfDiscussionReadOnly()) return;
    try {
      await _case.batonSelect(batonId: batonId, userId: userId);
      await _requestRefresh(scope: _RoomRefreshScope.messages);
    } on Object catch (e) {
      _showSnackError(e);
    }
  }

  /// Author: cancels the baton, then refetches so the card goes away.
  Future<void> batonCancel({required String batonId}) async {
    if (_rejectIfDiscussionReadOnly()) return;
    try {
      await _case.batonCancel(batonId: batonId);
      await _requestRefresh(scope: _RoomRefreshScope.messages);
    } on Object catch (e) {
      _showSnackError(e);
    }
  }

  Future<void> createPoll({
    required String question,
    required List<String> variants,
    String pollType = 'single',
    bool isAnonymous = true,
    bool allowRevote = true,
  }) async {
    if (_rejectIfDiscussionReadOnly()) return;
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.createPoll(
        beaconId: state.beaconId,
        question: question,
        variants: variants,
        pollType: pollType,
        isAnonymous: isAnonymous,
        allowRevote: allowRevote,
      );
      await markSeenNowIfNeeded();
      if (!isClosed) emit(state.copyWith(unreadAnchorAt: null));
      await load();
    } on Object catch (e) {
      _showSnackError(e);
    }
  }

  void _watchRoomPresence(List<BeaconParticipant> participants) {
    final myId = state.myUserId;
    final peerIds = {
      for (final p in participants)
        if (p.userId.isNotEmpty && p.userId != myId) p.userId,
    };
    _presenceRepository.watch('room:${state.beaconId}', peerIds);
  }

  @override
  Future<void> close() async {
    _pinnedOffWindowMessages.clear();
    _pendingLocalDeleteIds.clear();
    _activeMessageRefreshOverlay = null;
    _presenceRepository.unwatch('room:${state.beaconId}');
    await _refreshSub.cancel();
    await _catchUpsSub.cancel();
    await _itemSyncSub?.cancel();
    // close() is not a read: flush only when the last bottom-of-list callback
    // happened after the last inbound message arrived.
    final atBottomSince = _atBottomSince;
    final lastInbound = _lastInboundAt;
    if (atBottomSince != null &&
        (lastInbound == null || !lastInbound.isAfter(atBottomSince))) {
      await markSeenNowIfNeeded(force: true);
    }
    return super.close();
  }
}
