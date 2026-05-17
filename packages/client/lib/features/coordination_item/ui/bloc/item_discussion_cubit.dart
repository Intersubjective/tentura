import 'dart:async';

import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_room/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'item_discussion_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

class ItemDiscussionCubit extends Cubit<ItemDiscussionState> {
  ItemDiscussionCubit({
    required CoordinationItem item,
    CoordinationItemCase? coordinationItemCase,
    InvalidationService? invalidationService,
    ProfileCubit? profileCubit,
    bool listenToInvalidation = true,
  })  : _case = coordinationItemCase ?? GetIt.I<CoordinationItemCase>(),
        super(
          ItemDiscussionState(
            item: item,
            myUserId: (profileCubit ?? GetIt.I<ProfileCubit>()).state.profile.id,
          ),
        ) {
    if (listenToInvalidation) {
      _invalidationSub = (invalidationService ?? GetIt.I<InvalidationService>())
          .beaconRoomInvalidations
          .where(
            (e) =>
                e.beaconId == item.beaconId &&
                (e.entityType == BeaconRoomEntityType.coordinationItem ||
                    e.entityType ==
                        BeaconRoomEntityType.coordinationItemMessage),
          )
          .listen((_) => fetchMessages());
    }
  }

  final CoordinationItemCase _case;
  StreamSubscription<BeaconRoomInvalidation>? _invalidationSub;

  bool _markSeenEmittedThisVisit = false;
  bool _loadInProgress = false;

  Future<void> markSeenNowIfNeeded() async {
    if (_markSeenEmittedThisVisit) return;
    if (_loadInProgress) return;
    try {
      await _case.markItemSeenIfAllowed(state.item.id);
      _markSeenEmittedThisVisit = true;
      if (!isClosed) {
        emit(state.copyWith(pendingMarkSeen: false));
      }
    } on Object {
      /* non-fatal */
    }
  }

  Future<void> fetchMessages() async {
    _loadInProgress = true;
    try {
      emit(state.copyWith(status: const StateIsLoading()));
      final messages = await _case.listMessages(state.item.id);
      if (isClosed) return;

      var anchor = state.unreadAnchorAt;
      if (anchor == null) {
        anchor = state.item.lastSeenAt;
      }

      emit(state.copyWith(
        messages: messages,
        unreadAnchorAt: anchor,
        pendingMarkSeen: !_markSeenEmittedThisVisit,
        status: const StateIsSuccess(),
      ));
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    } finally {
      _loadInProgress = false;
    }
  }

  Future<void> deleteMessage({required String messageId}) async {
    final previous = List.of(state.messages);
    emit(
      state.copyWith(
        messages: state.messages.where((m) => m.id != messageId).toList(),
      ),
    );
    try {
      await _case.deleteMessage(
        itemId: state.item.id,
        messageId: messageId,
      );
    } on Object catch (e) {
      emit(state.copyWith(messages: previous, status: StateHasError(e)));
    }
  }

  Future<void> sendMessage(String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    try {
      await _case.appendMessage(itemId: state.item.id, body: trimmed);
      _markSeenEmittedThisVisit = false;
      await markSeenNowIfNeeded();
      if (!isClosed) {
        final seenAt = DateTime.timestamp();
        emit(
          state.copyWith(
            unreadAnchorAt: seenAt,
            item: state.item.copyWith(lastSeenAt: seenAt),
          ),
        );
      }
      await fetchMessages();
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> resolveBlocker() async {
    try {
      final updated = await _case.resolveBlocker(itemId: state.item.id);
      emit(state.copyWith(item: updated));
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> cancelBlocker() async {
    try {
      final updated = await _case.cancelBlocker(itemId: state.item.id);
      emit(state.copyWith(item: updated));
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> acceptAsk() async {
    try {
      final updated = await _case.acceptAsk(itemId: state.item.id);
      emit(state.copyWith(item: updated));
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> resolveAsk() async {
    try {
      final updated = await _case.resolveAsk(itemId: state.item.id);
      emit(state.copyWith(item: updated));
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> cancelAsk() async {
    try {
      final updated = await _case.cancelAsk(itemId: state.item.id);
      emit(state.copyWith(item: updated));
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> acceptResolution() async {
    try {
      final updated = await _case.acceptResolution(itemId: state.item.id);
      emit(state.copyWith(item: updated));
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> rejectResolution() async {
    try {
      final updated = await _case.rejectResolution(itemId: state.item.id);
      emit(state.copyWith(item: updated));
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  @override
  Future<void> close() async {
    await markSeenNowIfNeeded();
    await _invalidationSub?.cancel();
    return super.close();
  }
}
