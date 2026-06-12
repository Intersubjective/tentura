import 'dart:async';

import 'package:tentura/data/service/remote_api_client/graphql_v2_exceptions.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_poll_data.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/coordination_item_room_sync.dart';
import '../../domain/entity/room_seen_outcome.dart';
import '../../domain/use_case/beacon_room_case.dart';
import '../message/beacon_room_fact_messages.dart';
import 'room_message_reaction_local.dart';
import 'room_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'room_state.dart';

class RoomCubit extends Cubit<RoomState> {
  RoomCubit({
    required String beaconId,
    String? threadItemId,
    DateTime? initialUnreadAnchorAt,
    BeaconRoomCase? beaconRoomCase,
    CoordinationItemRoomSync? coordinationItemRoomSync,
  }) : _case = beaconRoomCase ?? GetIt.I<BeaconRoomCase>(),
       _itemSync = coordinationItemRoomSync ?? GetIt.I<CoordinationItemRoomSync>(),
       super(
         RoomState(
           beaconId: beaconId,
           threadItemId: threadItemId,
           unreadAnchorAt: initialUnreadAnchorAt,
           myUserId: GetIt.I<ProfileCubit>().state.profile.id,
           status: const StateIsLoading(),
         ),
       ) {
    _refreshSub = _case.beaconRoomRefresh.listen(_onRemoteRefresh);
    if (threadItemId == null) {
      _itemSyncSub = _itemSync.changes
          .where((item) => item.beaconId == beaconId)
          .listen(applyCoordinationItemSnapshot);
    }
    unawaited(load());
  }

  final BeaconRoomCase _case;

  final CoordinationItemRoomSync _itemSync;

  late final StreamSubscription<String> _refreshSub;

  StreamSubscription<CoordinationItem>? _itemSyncSub;

  String? _pendingThreadMessageId;
  String? _pendingThreadItemId;

  bool _markSeenEmittedThisVisit = false;
  bool _initialLoadDone = false;
  bool _loadInProgress = false;
  bool _loadQueued = false;

  void _onRemoteRefresh(String id) {
    if (isClosed) return;
    if (id == state.beaconId) {
      unawaited(reloadMessages(silent: true));
    }
  }

  /// Patches joined item snapshots on all messages referencing [item].
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

  Future<void> reloadMessages({bool silent = false}) =>
      _fetchRoomData(silent: silent);

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
    if (state.threadItemId == null) {
      _case.observeReadThrough(state.beaconId, latest);
    }
  }

  /// Advances the read watermark to the newest loaded message and flushes seen
  /// to the server. Called when the user reaches the bottom of the list.
  Future<void> markReadToBottom() async {
    if (state.messages.isEmpty) return;

    _advanceReadAnchorToLatestLoaded();
    await markSeenNowIfNeeded();
  }

  Future<void> markSeenNowIfNeeded() async {
    if (_markSeenEmittedThisVisit) {
      return;
    }
    if (!_initialLoadDone) {
      return;
    }
    try {
      final readThrough = state.unreadAnchorAt ?? state.messages.last.createdAt;
      final outcome = await _case.markRoomSeenIfAllowed(
        beaconId: state.beaconId,
        threadItemId: state.threadItemId,
        readThroughAt: readThrough,
      );
      switch (outcome) {
        case RoomSeenSucceeded():
          _markSeenEmittedThisVisit = true;
          if (!isClosed) {
            _advanceReadAnchorToLatestLoaded();
            emit(state.copyWith(pendingMarkSeen: false));
          }
        case RoomSeenDenied():
        case RoomSeenFailed():
      }
    } on Object {
      /* non-fatal; retry on next bottom / exit */
    }
  }

  Future<void> load() => _fetchRoomData(silent: false);

  Future<void> _fetchRoomData({required bool silent}) async {
    if (isClosed) return;
    if (_loadInProgress) {
      _loadQueued = true;
      return;
    }
    _loadInProgress = true;
    if (!silent) {
      emit(state.copyWith(status: const StateIsLoading()));
    }
    try {
      final inThread = state.threadItemId != null;
      final messages = await _case.fetchMessages(
        beaconId: state.beaconId,
        threadItemId: state.threadItemId,
      );
      final participants = inThread
          ? const <BeaconParticipant>[]
          : await _case.fetchParticipants(state.beaconId);
      final roomState = inThread
          ? null
          : await _case.fetchBeaconRoomState(state.beaconId);
      final factCards =
          inThread ? const <BeaconFactCard>[] : await _case.fetchFactCards(state.beaconId);
      final openCoordinationBlocker = inThread
          ? null
          : await _case.fetchOpenCoordinationBlocker(state.beaconId);
      final currentCoordinationPlan = inThread
          ? null
          : await _case.fetchCurrentCoordinationPlan(state.beaconId);

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
        if (anchor == null) {
          anchor = serverSeen;
        } else if (serverSeen != null && serverSeen.isAfter(anchor)) {
          anchor = serverSeen;
        }
      }

      if (!isClosed) {
        _initialLoadDone = true;
        emit(
          state.copyWith(
            messages: messages,
            participants: participants,
            factCards: factCards,
            roomState: roomState,
            openCoordinationBlocker: openCoordinationBlocker,
            currentCoordinationPlan: currentCoordinationPlan,
            unreadAnchorAt: anchor,
            myUserId: GetIt.I<ProfileCubit>().state.profile.id,
            pendingMarkSeen: !_markSeenEmittedThisVisit,
            status: const StateIsSuccess(),
          ),
        );
        if (!isClosed) {
          _applyPendingThreadScroll(messages);
        }
      }
    } on Object catch (e) {
      if (!isClosed) {
        emit(state.copyWith(status: StateHasError(e)));
      }
    } finally {
      _loadInProgress = false;
      if (_loadQueued && !isClosed) {
        _loadQueued = false;
        unawaited(_fetchRoomData(silent: silent));
      }
    }
  }

  Future<void> updatePlan(
    String currentLine, {
    String body = '',
    String? targetPersonId,
    String? linkedMessageId,
  }) async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.updateRoomPlan(
        beaconId: state.beaconId,
        currentLine: currentLine,
        body: body,
        targetPersonId: targetPersonId,
        linkedMessageId: linkedMessageId,
      );
      await load();
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> pinFactFromMessage({
    required String sourceMessageId,
    required String factText,
    required int visibility,
  }) async {
    final existing = state.factCards.where(
      (f) => f.sourceMessageId == sourceMessageId,
    ).firstOrNull;
    if (existing != null) {
      emit(
        state.copyWith(
          status: StateIsMessaging(
            BeaconFactAlreadyPinnedSnackMessage(
              onOpenFacts: () => emit(
                state.copyWith(
                  pendingFactsFocusFactId: existing.id,
                  status: const StateIsSuccess(),
                ),
              ),
            ),
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
      emit(
        state.copyWith(
          status: StateIsMessaging(const BeaconFactPinSuccessMessage()),
        ),
      );
    } on BeaconFactAlreadyPinnedRemoteException catch (e) {
      emit(
        state.copyWith(
          status: StateIsMessaging(
            BeaconFactAlreadyPinnedSnackMessage(
              onOpenFacts: () => emit(
                state.copyWith(
                  pendingFactsFocusFactId: e.factCardId,
                  status: const StateIsSuccess(),
                ),
              ),
            ),
          ),
        ),
      );
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> correctFact({
    required String factCardId,
    required String newText,
  }) async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.correctFact(
        beaconId: state.beaconId,
        factCardId: factCardId,
        newText: newText,
      );
      await load();
      emit(
        state.copyWith(
          status: StateIsMessaging(const BeaconFactEditSuccessMessage()),
        ),
      );
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> removeFact({required String factCardId}) async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.removeFact(
        beaconId: state.beaconId,
        factCardId: factCardId,
      );
      await load();
      emit(
        state.copyWith(
          status: StateIsMessaging(const BeaconFactRemoveSuccessMessage()),
        ),
      );
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> setFactVisibility({
    required String factCardId,
    required int visibility,
  }) async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.setFactVisibility(
        beaconId: state.beaconId,
        factCardId: factCardId,
        visibility: visibility,
      );
      await load();
      emit(
        state.copyWith(
          status: StateIsMessaging(const BeaconFactVisibilitySuccessMessage()),
        ),
      );
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> sendMessage({
    required String body,
    List<RoomPendingUpload> uploads = const [],
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty && uploads.isEmpty) {
      return;
    }
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.createMessage(
        beaconId: state.beaconId,
        body: trimmed,
        threadItemId: state.threadItemId,
        uploads: uploads,
      );
      _markSeenEmittedThisVisit = false;
      await markSeenNowIfNeeded();
      if (!isClosed) emit(state.copyWith(unreadAnchorAt: null));
      await load();
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> toggleReaction({
    required String messageId,
    required String emoji,
  }) async {
    final idx = state.messages.indexWhere((m) => m.id == messageId);
    final previousMessages =
        idx >= 0 ? List<RoomMessage>.from(state.messages) : null;

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
        emit(
          state.copyWith(
            messages: previousMessages,
            status: StateHasError(e),
          ),
        );
      } else {
        emit(state.copyWith(status: StateHasError(e)));
      }
    }
  }

  Future<void> editMessage({
    required String messageId,
    required String newBody,
  }) async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.editMessage(
        beaconId: state.beaconId,
        messageId: messageId,
        body: newBody,
      );
      await load();
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> deleteMessage({required String messageId}) async {
    final previousMessages = List<RoomMessage>.from(state.messages);
    emit(
      state.copyWith(
        messages: state.messages.where((m) => m.id != messageId).toList(),
      ),
    );
    try {
      await _case.deleteMessage(
        beaconId: state.beaconId,
        messageId: messageId,
      );
    } on Object catch (e) {
      emit(state.copyWith(messages: previousMessages, status: StateHasError(e)));
    }
  }

  Future<void> markAskFromMessage({
    required String messageId,
    required String title,
    required String targetPersonId,
    String body = '',
    int? staleAfterDays,
  }) async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.markAskFromMessage(
        beaconId: state.beaconId,
        messageId: messageId,
        title: title,
        targetPersonId: targetPersonId,
        body: body,
        staleAfterDays: staleAfterDays,
      );
      await load();
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> markBlockerFromMessage({
    required String messageId,
    required String title,
    String body = '',
    String? targetPersonId,
    int? staleAfterDays,
  }) async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.markBlockerFromMessage(
        beaconId: state.beaconId,
        messageId: messageId,
        title: title,
        body: body,
        targetPersonId: targetPersonId,
        staleAfterDays: staleAfterDays,
      );
      await load();
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> markAskFromMessageAsNeedInfo({
    required String messageId,
    required String targetPersonId,
    required String title,
    String body = '',
    int? staleAfterDays,
  }) async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.markAskFromMessageAsNeedInfo(
        beaconId: state.beaconId,
        messageId: messageId,
        targetPersonId: targetPersonId,
        title: title,
        body: body,
        staleAfterDays: staleAfterDays,
      );
      await load();
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> resolveCoordinationBlocker({required String itemId}) async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.resolveCoordinationBlocker(itemId: itemId);
      await load();
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> markMessageSemanticDone({required String messageId}) async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.markMessageSemanticDone(
        beaconId: state.beaconId,
        messageId: messageId,
      );
      await load();
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> votePoll({
    required String messageId,
    required String pollingId,
    required List<String> variantIds,
    int? score,
  }) async {
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
        final optimistic = List<RoomMessage>.from(state.messages)..[idx] = updated;
        emit(state.copyWith(messages: optimistic));
      }
    }

    try {
      await _case.votePoll(
        pollingId: pollingId,
        variantIds: variantIds,
        score: score,
      );
      await load();
    } on Object catch (e) {
      emit(
        state.copyWith(
          messages: previousMessages ?? state.messages,
          status: StateHasError(e),
        ),
      );
    }
  }

  Future<void> createPoll({
    required String question,
    required List<String> variants,
    String pollType = 'single',
    bool isAnonymous = true,
    bool allowRevote = true,
  }) async {
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
      _markSeenEmittedThisVisit = false;
      await markSeenNowIfNeeded();
      if (!isClosed) emit(state.copyWith(unreadAnchorAt: null));
      await load();
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  @override
  Future<void> close() async {
    await _refreshSub.cancel();
    await _itemSyncSub?.cancel();
    await markSeenNowIfNeeded();
    return super.close();
  }
}
