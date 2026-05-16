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
              (e.entityType == BeaconRoomEntityType.coordinationItem ||
                  e.entityType ==
                      BeaconRoomEntityType.coordinationItemMessage ||
                  e.entityType == BeaconRoomEntityType.participant ||
                  e.entityType == BeaconRoomEntityType.factCard ||
                  e.entityType == BeaconRoomEntityType.blocker),
        )
        .listen((_) => unawaited(fetch(silent: true)));
  }

  final String _beaconId;
  final CoordinationItemCase _case;
  late final StreamSubscription<BeaconRoomInvalidation> _invalidationSub;

  Future<void> fetch({bool silent = false}) async {
    try {
      if (!silent) {
        emit(state.copyWith(status: const StateIsLoading()));
      }
      final items = await _case.listByBeacon(_beaconId);
      final currentPlan = await _case.fetchCurrentRootPlan(_beaconId);
      final open = <CoordinationItem>[];
      final closed = <CoordinationItem>[];
      final drafts = <CoordinationItem>[];
      for (final item in items) {
        if (!item.published && item.kind == CoordinationItemKind.ask) {
          drafts.add(item);
          continue;
        }
        if (item.isActive) {
          open.add(item);
        } else {
          closed.add(item);
        }
      }
      emit(state.copyWith(
        openItems: open,
        closedItems: closed,
        draftAskItems: drafts,
        currentCoordinationPlan: currentPlan,
        status: const StateIsSuccess(),
      ));
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> resolveBlocker(String itemId) async {
    try {
      emit(state.copyWith(status: const StateIsSuccess()));
      await _case.resolveBlocker(itemId: itemId);
      await fetch(silent: true);
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> cancelBlocker(String itemId) async {
    try {
      emit(state.copyWith(status: const StateIsSuccess()));
      await _case.cancelBlocker(itemId: itemId);
      await fetch(silent: true);
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> acceptAsk(String itemId) async {
    try {
      emit(state.copyWith(status: const StateIsSuccess()));
      await _case.acceptAsk(itemId: itemId);
      await fetch(silent: true);
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> resolveAsk(String itemId) async {
    try {
      emit(state.copyWith(status: const StateIsSuccess()));
      await _case.resolveAsk(itemId: itemId);
      await fetch(silent: true);
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> cancelAsk(String itemId) async {
    try {
      emit(state.copyWith(status: const StateIsSuccess()));
      await _case.cancelAsk(itemId: itemId);
      await fetch(silent: true);
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> acceptResolution(String itemId) async {
    try {
      emit(state.copyWith(status: const StateIsSuccess()));
      await _case.acceptResolution(itemId: itemId);
      await fetch(silent: true);
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> rejectResolution(String itemId) async {
    try {
      emit(state.copyWith(status: const StateIsSuccess()));
      await _case.rejectResolution(itemId: itemId);
      await fetch(silent: true);
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> resolvePlanStep(String itemId) async {
    try {
      emit(state.copyWith(status: const StateIsSuccess()));
      await _case.resolvePlanStep(itemId: itemId);
      await fetch(silent: true);
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> createPlan(String title) async {
    try {
      emit(state.copyWith(status: const StateIsSuccess()));
      await _case.updatePlan(beaconId: _beaconId, title: title);
      await fetch(silent: true);
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
