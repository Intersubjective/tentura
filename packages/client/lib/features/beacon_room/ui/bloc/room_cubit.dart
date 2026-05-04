import 'dart:async';

import 'package:tentura/data/service/remote_api_client/graphql_v2_exceptions.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
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
       super(RoomState(beaconId: beaconId, status: const StateIsLoading())) {
    _refreshSub = _case.beaconRoomRefresh.listen(_onRemoteRefresh);
    unawaited(load());
  }

  final BeaconRoomCase _case;

  late final StreamSubscription<String> _refreshSub;

  bool _markSeenEmittedThisVisit = false;

  void _onRemoteRefresh(String id) {
    if (id == state.beaconId) {
      unawaited(load());
    }
  }

  /// Active or corrected fact originating from [message].
  BeaconFactCard? factForRoomMessage(RoomMessage message) {
    final lid = message.linkedFactCardId;
    if (lid != null && lid.isNotEmpty) {
      for (final f in state.factCards) {
        if (f.id == lid) {
          return f;
        }
      }
    }
    for (final f in state.factCards) {
      if (f.sourceMessageId == message.id) {
        return f;
      }
    }
    return null;
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

  Future<void> markSeenNowIfNeeded() async {
    if (_markSeenEmittedThisVisit) return;
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

  void toggleNowCollapsed() {
    emit(state.copyWith(nowCollapsed: !state.nowCollapsed));
  }

  void toggleYouCollapsed() {
    emit(state.copyWith(youCollapsed: !state.youCollapsed));
  }

  Future<void> load() async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      final messages = await _case.fetchMessages(beaconId: state.beaconId);
      final participants =
          await _case.fetchParticipants(state.beaconId);
      final roomState = await _case.fetchBeaconRoomState(state.beaconId);
      final factCards = await _case.fetchFactCards(state.beaconId);

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

      emit(
        state.copyWith(
          messages: messages,
          participants: participants,
          factCards: factCards,
          roomState: roomState,
          unreadAnchorAt: anchor,
          pendingMarkSeen: !_markSeenEmittedThisVisit,
          status: const StateIsSuccess(),
        ),
      );
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> updatePlan(String currentPlan) async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.updateRoomPlan(
        beaconId: state.beaconId,
        currentPlan: currentPlan,
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
      await load();
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<Uint8List> downloadRoomAttachment(String attachmentId) =>
      _case.downloadRoomAttachment(attachmentId);

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

  Future<void> markBlockerFromMessage({
    required String messageId,
    required String title,
    String? affectedParticipantId,
    String? resolverParticipantId,
    int? visibility,
  }) async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.markBlockerFromMessage(
        beaconId: state.beaconId,
        messageId: messageId,
        title: title,
        affectedParticipantId: affectedParticipantId,
        resolverParticipantId: resolverParticipantId,
        visibility: visibility,
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
    required String variantId,
  }) async {
    // Optimistic update: bump vote count + set myVariantId
    final idx = state.messages.indexWhere((m) => m.id == messageId);
    List<RoomMessage>? previousMessages;
    if (idx >= 0) {
      final msg = state.messages[idx];
      final poll = RoomPollData.tryParse(msg.pollDataJson);
      if (poll != null) {
        previousMessages = List<RoomMessage>.from(state.messages);
        final updated = msg.copyWith(
          pollDataJson: _encodePollOptimisticVote(poll, variantId),
        );
        final optimistic = List<RoomMessage>.from(state.messages)..[idx] = updated;
        emit(state.copyWith(messages: optimistic));
      }
    }

    try {
      await _case.votePoll(pollingId: pollingId, variantId: variantId);
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

  static String _encodePollOptimisticVote(RoomPollData poll, String variantId) {
    final updated = poll.withOptimisticVote(variantId);
    return '{"id":"${updated.id}","question":${_jsonQuote(updated.question)},"myVariantId":"$variantId","totalVotes":${updated.totalVotes},"variants":[${updated.variants.map((v) => '{"id":"${v.id}","description":${_jsonQuote(v.description)},"votesCount":${v.votesCount}}').join(',')}]}';
  }

  static String _jsonQuote(String s) {
    return '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }

  Future<void> createPoll({
    required String question,
    required List<String> variants,
  }) async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.createPoll(
        beaconId: state.beaconId,
        question: question,
        variants: variants,
      );
      await load();
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  @override
  Future<void> close() async {
    await markSeenNowIfNeeded();
    await _refreshSub.cancel();
    return super.close();
  }
}
