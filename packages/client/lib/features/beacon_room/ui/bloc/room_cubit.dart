import 'dart:async';

import 'package:tentura/data/service/remote_api_client/graphql_v2_exceptions.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_poll_data.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/use_case/beacon_room_case.dart';
import '../message/beacon_room_fact_messages.dart';
import 'room_message_reaction_local.dart';
import 'room_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'room_state.dart';

class RoomCubit extends Cubit<RoomState> {
  RoomCubit({
    required String beaconId,
    BeaconRoomCase? beaconRoomCase,
  }) : _case = beaconRoomCase ?? GetIt.I<BeaconRoomCase>(),
       super(
         RoomState(
           beaconId: beaconId,
           myUserId: GetIt.I<ProfileCubit>().state.profile.id,
           status: const StateIsLoading(),
         ),
       ) {
    _refreshSub = _case.beaconRoomRefresh.listen(_onRemoteRefresh);
    unawaited(load());
  }

  final BeaconRoomCase _case;

  late final StreamSubscription<String> _refreshSub;

  String? _pendingThreadMessageId;
  String? _pendingThreadItemId;

  bool _markSeenEmittedThisVisit = false;
  bool _loadInProgress = false;
  bool _loadQueued = false;

  void _onRemoteRefresh(String id) {
    if (isClosed) return;
    if (id == state.beaconId) {
      unawaited(load());
    }
  }

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

  Future<void> markSeenNowIfNeeded() async {
    if (_markSeenEmittedThisVisit) return;
    if (_loadInProgress) return;
    try {
      await _case.markRoomSeenIfAllowed(state.beaconId);
      _markSeenEmittedThisVisit = true;
      if (!isClosed) {
        emit(state.copyWith(pendingMarkSeen: false));
      }
    } on Object {
      /* non-fatal; retry on next bottom / exit */
    }
  }

  Future<void> load() async {
    if (isClosed) return;
    if (_loadInProgress) {
      _loadQueued = true;
      return;
    }
    _loadInProgress = true;
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      final messages = await _case.fetchMessages(beaconId: state.beaconId);
      final participants =
          await _case.fetchParticipants(state.beaconId);
      final roomState = await _case.fetchBeaconRoomState(state.beaconId);
      final factCards = await _case.fetchFactCards(state.beaconId);
      final openCoordinationBlocker =
          await _case.fetchOpenCoordinationBlocker(state.beaconId);
      final currentCoordinationPlan =
          await _case.fetchCurrentCoordinationPlan(state.beaconId);

      if (isClosed) return;

      var anchor = state.unreadAnchorAt;
      if (anchor == null) {
        final myId = GetIt.I<ProfileCubit>().state.profile.id;
        for (final p in participants) {
          if (p.userId == myId) {
            anchor = p.lastSeenRoomAt;
            break;
          }
        }
      }

      if (!isClosed) {
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
        unawaited(load());
      }
    }
  }

  Future<void> updatePlan(
    String currentPlan, {
    String body = '',
    String? targetPersonId,
    String? linkedMessageId,
  }) async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.updateRoomPlan(
        beaconId: state.beaconId,
        currentPlan: currentPlan,
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

  Future<void> participantSetNextMove({
    required String targetUserId,
    required String nextMoveText,
    int nextMoveSource = BeaconNextMoveSourceBits.self,
    int? nextMoveStatus,
  }) async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.participantSetNextMove(
        beaconId: state.beaconId,
        targetUserId: targetUserId,
        nextMoveText: nextMoveText,
        nextMoveSource: nextMoveSource,
        nextMoveStatus: nextMoveStatus,
      );
      await load();
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

  Future<void> createResolutionFromMessage({
    required String messageId,
    required String title,
    String? targetItemId,
  }) async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.createResolutionFromMessage(
        beaconId: state.beaconId,
        messageId: messageId,
        title: title,
        targetItemId: targetItemId,
      );
      await load();
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> markAskFromMessage({
    required String messageId,
    required String title,
    required String targetPersonId,
    String body = '',
  }) async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.markAskFromMessage(
        beaconId: state.beaconId,
        messageId: messageId,
        title: title,
        targetPersonId: targetPersonId,
        body: body,
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
  }) async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.markBlockerFromMessage(
        beaconId: state.beaconId,
        messageId: messageId,
        title: title,
        body: body,
        targetPersonId: targetPersonId,
      );
      await load();
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> needInfoFromMessage({
    required String messageId,
    required String targetUserId,
    required String requestText,
  }) async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.needInfoFromMessage(
        beaconId: state.beaconId,
        messageId: messageId,
        targetUserId: targetUserId,
        requestText: requestText,
      );
      await load();
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> markMessageDone({
    required String messageId,
    required bool resolveBlocker,
  }) async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.markMessageDone(
        beaconId: state.beaconId,
        messageId: messageId,
        resolveBlocker: resolveBlocker,
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
    await markSeenNowIfNeeded();
    return super.close();
  }
}
