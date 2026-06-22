import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_room/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_room/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';

import 'item_actions_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

class ItemActionsCubit extends Cubit<ItemActionsState> {
  ItemActionsCubit({
    required CoordinationItem item,
    CoordinationItemCase? coordinationItemCase,
    InvalidationService? invalidationService,
    CoordinationItemRoomSync? coordinationItemRoomSync,
    bool listenToInvalidation = true,
  })  : _case = coordinationItemCase ?? GetIt.I<CoordinationItemCase>(),
        _itemSync = coordinationItemRoomSync ?? GetIt.I<CoordinationItemRoomSync>(),
        super(ItemActionsState(item: item)) {
    if (listenToInvalidation) {
      _invalidationSub = (invalidationService ?? GetIt.I<InvalidationService>())
          .beaconRoomInvalidations
          .where(
            (e) =>
                e.beaconId == item.beaconId &&
                e.entityType == BeaconRoomEntityType.coordinationItem,
          )
          .listen((_) => _refreshItem());
    }
    unawaited(_refreshItem());
  }

  final CoordinationItemCase _case;
  final CoordinationItemRoomSync _itemSync;
  StreamSubscription<BeaconRoomInvalidation>? _invalidationSub;

  Future<void> _runItemMutation(
    Future<CoordinationItem> Function() mutate,
  ) async {
    if (isClosed) {
      return;
    }
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      final updated = await mutate();
      if (isClosed) {
        return;
      }
      emit(
        state.copyWith(
          item: updated,
          status: const StateIsSuccess(),
        ),
      );
      _itemSync.notifyItemUpdated(updated);
    } on Object catch (e) {
      if (!isClosed) {
        emit(state.copyWith(status: StateHasError(e)));
      }
    }
  }

  Future<void> _runVoidMutation(Future<void> Function() mutate) async {
    if (isClosed) {
      return;
    }
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await mutate();
      if (!isClosed) {
        emit(state.copyWith(status: const StateIsSuccess()));
      }
    } on Object catch (e) {
      if (!isClosed) {
        emit(state.copyWith(status: StateHasError(e)));
      }
    }
  }

  Future<void> _refreshItem() async {
    try {
      final items = await _case.listByBeacon(state.item.beaconId);
      final updated = items
          .where((i) => i.id == state.item.id)
          .cast<CoordinationItem?>()
          .firstOrNull;
      final pending = await _case.fetchPendingResolutionForItem(
        beaconId: state.item.beaconId,
        targetItemId: state.item.id,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          item: updated ?? state.item,
          pendingResolution: pending,
          status: const StateIsSuccess(),
        ),
      );
    } on Object catch (e) {
      if (!isClosed) emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> promoteResolution({
    required String title,
    String body = '',
  }) async {
    await _runVoidMutation(() async {
      final resolution = await _case.createResolution(
        beaconId: state.item.beaconId,
        title: title,
        body: body,
        targetItemId: state.item.id,
      );
      if (!isClosed) {
        emit(state.copyWith(pendingResolution: resolution));
      }
    });
  }

  Future<void> resolveBlocker() async =>
      _runItemMutation(() => _case.resolveBlocker(itemId: state.item.id));

  Future<void> cancelBlocker() async =>
      _runItemMutation(() => _case.cancelBlocker(itemId: state.item.id));

  Future<void> acceptAsk() async =>
      _runItemMutation(() => _case.acceptAsk(itemId: state.item.id));

  Future<void> resolveAsk() async =>
      _runItemMutation(() => _case.resolveAsk(itemId: state.item.id));

  Future<void> cancelAsk() async =>
      _runItemMutation(() => _case.cancelAsk(itemId: state.item.id));

  Future<void> acceptPromise() async =>
      _runItemMutation(() => _case.acceptPromise(itemId: state.item.id));

  Future<void> resolvePromise() async =>
      _runItemMutation(() => _case.resolvePromise(itemId: state.item.id));

  Future<void> cancelPromise() async =>
      _runItemMutation(() => _case.cancelPromise(itemId: state.item.id));

  Future<void> remindItem() async =>
      _runItemMutation(() => _case.remindItem(itemId: state.item.id));

  Future<void> acceptResolution() async {
    final resolutionId = state.pendingResolution?.id;
    if (resolutionId == null) {
      return;
    }
    if (isClosed) {
      return;
    }
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      await _case.acceptResolution(itemId: resolutionId);
      await _refreshItem();
    } on Object catch (e) {
      if (!isClosed) {
        emit(state.copyWith(status: StateHasError(e)));
      }
    }
  }

  Future<void> rejectResolution() async {
    final resolutionId = state.pendingResolution?.id;
    if (resolutionId == null) {
      return;
    }
    await _runVoidMutation(() async {
      await _case.rejectResolution(itemId: resolutionId);
      if (!isClosed) {
        emit(state.copyWith(pendingResolution: null));
      }
    });
  }

  @override
  Future<void> close() async {
    await _invalidationSub?.cancel();
    return super.close();
  }
}
