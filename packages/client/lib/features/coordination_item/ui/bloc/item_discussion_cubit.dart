import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_room/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'item_discussion_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

class ItemDiscussionCubit extends Cubit<ItemDiscussionState> {
  ItemDiscussionCubit({
    required CoordinationItem item,
    CoordinationItemCase? coordinationItemCase,
    InvalidationService? invalidationService,
  })  : _case = coordinationItemCase ?? GetIt.I<CoordinationItemCase>(),
        super(ItemDiscussionState(item: item)) {
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

  final CoordinationItemCase _case;
  late final StreamSubscription<BeaconRoomInvalidation> _invalidationSub;

  Future<void> fetchMessages() async {
    try {
      emit(state.copyWith(status: const StateIsLoading()));
      final messages = await _case.listMessages(state.item.id);
      emit(state.copyWith(
        messages: messages,
        status: const StateIsSuccess(),
      ));
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> sendMessage(String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    try {
      await _case.appendMessage(itemId: state.item.id, body: trimmed);
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

  @override
  Future<void> close() async {
    await _invalidationSub.cancel();
    return super.close();
  }
}
