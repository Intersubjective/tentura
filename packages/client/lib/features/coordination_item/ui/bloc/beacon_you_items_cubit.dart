import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'beacon_you_items_state.dart';

export 'beacon_you_items_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

class BeaconYouItemsCubit extends Cubit<BeaconYouItemsState> {
  BeaconYouItemsCubit({
    required String beaconId,
    CoordinationItemCase? coordinationItemCase,
  })  : _beaconId = beaconId,
        _case = coordinationItemCase ?? GetIt.I<CoordinationItemCase>(),
        super(const BeaconYouItemsState()) {
    unawaited(fetch());
  }

  final String _beaconId;
  final CoordinationItemCase _case;

  Future<void> fetch() async {
    try {
      emit(state.copyWith(status: const StateIsLoading()));
      final items = await _case.fetchMyResponsibilityItems(_beaconId);
      emit(
        state.copyWith(
          items: items,
          status: const StateIsSuccess(),
        ),
      );
    } on Object catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> resolveAsk(String itemId) async {
    await _case.resolveAsk(itemId: itemId);
    await fetch();
  }

  Future<void> cancelAsk(String itemId) async {
    await _case.cancelAsk(itemId: itemId);
    await fetch();
  }

  Future<void> resolvePromise(String itemId) async {
    await _case.resolvePromise(itemId: itemId);
    await fetch();
  }

  Future<void> cancelPromise(String itemId) async {
    await _case.cancelPromise(itemId: itemId);
    await fetch();
  }

  Future<void> resolveBlocker(String itemId) async {
    await _case.resolveBlocker(itemId: itemId);
    await fetch();
  }

  Future<void> acceptResolution(String itemId) async {
    await _case.acceptResolution(itemId: itemId);
    await fetch();
  }

  Future<void> rejectResolution(String itemId) async {
    await _case.rejectResolution(itemId: itemId);
    await fetch();
  }
}

List<CoordinationItem> groupYouItemsByKind(List<CoordinationItem> items) {
  const order = [
    CoordinationItemKind.ask,
    CoordinationItemKind.promise,
    CoordinationItemKind.blocker,
    CoordinationItemKind.resolution,
  ];
  final out = <CoordinationItem>[];
  for (final kind in order) {
    out.addAll(items.where((e) => e.kind == kind));
  }
  return out;
}
