import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/use_case/beacon_room_case.dart';
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

  void _onRemoteRefresh(String id) {
    if (id == state.beaconId) {
      unawaited(load());
    }
  }

  Future<void> load() async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      final messages = await _case.fetchMessages(beaconId: state.beaconId);
      final participants =
          await _case.fetchParticipants(state.beaconId);
      final roomState = await _case.fetchBeaconRoomState(state.beaconId);
      final factCards = await _case.fetchFactCards(state.beaconId);
      emit(
        state.copyWith(
          messages: messages,
          participants: participants,
          factCards: factCards,
          roomState: roomState,
          status: const StateIsSuccess(),
        ),
      );
      unawaited(_case.markRoomSeenIfAllowed(state.beaconId));
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
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.pinFact(
        beaconId: state.beaconId,
        factText: factText,
        visibility: visibility,
        sourceMessageId: sourceMessageId,
      );
      await load();
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

  @override
  Future<void> close() async {
    await _refreshSub.cancel();
    return super.close();
  }
}
