import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/features/beacon_room/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'items_tab_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

class ItemsTabCubit extends Cubit<ItemsTabState> {
  ItemsTabCubit({
    required String beaconId,
    CoordinationItemCase? coordinationItemCase,
    InvalidationService? invalidationService,
  })  : _beaconId = beaconId,
        _case = coordinationItemCase ?? GetIt.I<CoordinationItemCase>(),
        super(const ItemsTabState()) {
    _invalidationSub = (invalidationService ?? GetIt.I<InvalidationService>())
        .beaconRoomInvalidations
        .where(
          (e) =>
              e.beaconId == beaconId &&
              e.entityType == BeaconRoomEntityType.coordinationItem,
        )
        .listen((_) => fetch());
  }

  final String _beaconId;
  final CoordinationItemCase _case;
  late final StreamSubscription<BeaconRoomInvalidation> _invalidationSub;

  Future<void> fetch() async {
    try {
      emit(state.copyWith(status: const StateIsLoading()));
      final items = await _case.listByBeacon(_beaconId);
      final open = <CoordinationItem>[];
      final closed = <CoordinationItem>[];
      for (final item in items) {
        if (item.isActive) {
          open.add(item);
        } else {
          closed.add(item);
        }
      }
      emit(state.copyWith(
        openItems: open,
        closedItems: closed,
        status: const StateIsSuccess(),
      ));
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> resolveBlocker(String itemId) async {
    try {
      await _case.resolveBlocker(itemId: itemId);
      await fetch();
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> cancelBlocker(String itemId) async {
    try {
      await _case.cancelBlocker(itemId: itemId);
      await fetch();
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> acceptAsk(String itemId) async {
    try {
      await _case.acceptAsk(itemId: itemId);
      await fetch();
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> resolveAsk(String itemId) async {
    try {
      await _case.resolveAsk(itemId: itemId);
      await fetch();
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> cancelAsk(String itemId) async {
    try {
      await _case.cancelAsk(itemId: itemId);
      await fetch();
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> resolvePlanStep(String itemId) async {
    try {
      await _case.resolvePlanStep(itemId: itemId);
      await fetch();
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
