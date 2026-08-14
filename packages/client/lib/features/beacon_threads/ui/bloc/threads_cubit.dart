import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'threads_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

class ThreadsCubit extends Cubit<ThreadsState> {
  ThreadsCubit({
    required String beaconId,
    CoordinationItemCase? coordinationItemCase,
    BeaconThreadsCase? beaconThreadsCase,
  }) : _beaconId = beaconId,
       _coordination = coordinationItemCase ?? GetIt.I<CoordinationItemCase>(),
       _threads = beaconThreadsCase ?? GetIt.I<BeaconThreadsCase>(),
       super(
         ThreadsState(
           myUserId: GetIt.I<ProfileCubit>().state.profile.id,
         ),
       ) {
    _invalidationSub = _threads.beaconRoomInvalidations
        .where(
          (e) =>
              e.beaconId == beaconId &&
              (e.entityType == BeaconRoomEntityType.coordinationItem ||
                  e.entityType == BeaconRoomEntityType.roomMessage ||
                  e.entityType == BeaconRoomEntityType.participant ||
                  e.entityType == BeaconRoomEntityType.factCard ||
                  e.entityType == BeaconRoomEntityType.roomSeen),
        )
        .listen(_onInvalidation);
    _watermarkSub = _threads.threadReadWatermarkChanges
        .where((key) => key.beaconId == beaconId)
        .listen((_) => _onThreadWatermarkChanged());
  }

  static const _invalidationDebounce = Duration(milliseconds: 50);

  final String _beaconId;
  final CoordinationItemCase _coordination;
  final BeaconThreadsCase _threads;

  late final StreamSubscription<BeaconRoomInvalidation> _invalidationSub;
  late final StreamSubscription<RoomReadWatermarkKey> _watermarkSub;

  Timer? _debouncedFetchTimer;
  int _fetchGeneration = 0;

  void _onInvalidation(BeaconRoomInvalidation invalidation) {
    if (isClosed) return;
    if (invalidation.entityType == BeaconRoomEntityType.roomSeen) {
      _debouncedFetchTimer?.cancel();
      _debouncedFetchTimer = null;
      unawaited(fetch(silent: true));
      return;
    }
    _scheduleDebouncedFetch();
  }

  void _scheduleDebouncedFetch() {
    _debouncedFetchTimer?.cancel();
    _debouncedFetchTimer = Timer(_invalidationDebounce, () {
      _debouncedFetchTimer = null;
      if (!isClosed) {
        unawaited(fetch(silent: true));
      }
    });
  }

  void _onThreadWatermarkChanged() {
    if (isClosed || state.threads.isEmpty) return;
    emit(
      state.copyWith(
        resolvedUnreadByThreadId: _resolveAllUnread(state.threads),
      ),
    );
  }

  Map<String, int> _resolveAllUnread(List<RequestThread> threads) => {
    for (final thread in threads)
      thread.threadId: _threads.resolveUnread(
        beaconId: _beaconId,
        threadId: thread.threadId,
        serverCount: thread.unreadCount,
        serverSeenAt: thread.lastSeenAt,
      ),
  };

  Future<void> fetch({bool silent = false}) async {
    final generation = ++_fetchGeneration;
    try {
      if (!silent) {
        emit(state.copyWith(status: const StateIsLoading()));
      }
      final threads = await _threads.listThreads(_beaconId);
      if (generation != _fetchGeneration) return;
      emit(
        state.copyWith(
          threads: threads,
          resolvedUnreadByThreadId: _resolveAllUnread(threads),
          loadError: null,
          status: const StateIsSuccess(),
        ),
      );
    } on Object catch (e) {
      if (generation != _fetchGeneration) return;
      emit(state.copyWith(loadError: e, status: const StateIsSuccess()));
    }
  }

  void setActiveForMeOnly(bool value) {
    emit(state.copyWith(activeForMeOnly: value));
  }

  Future<void> resolveBlocker(String itemId) async {
    try {
      emit(state.copyWith(status: const StateIsSuccess()));
      await _coordination.resolveBlocker(itemId: itemId);
      await fetch(silent: true);
    } on Object catch (e) {
      emit(state.copyWith(loadError: e, status: const StateIsSuccess()));
    }
  }

  Future<void> cancelBlocker(String itemId) async {
    try {
      emit(state.copyWith(status: const StateIsSuccess()));
      await _coordination.cancelBlocker(itemId: itemId);
      await fetch(silent: true);
    } on Object catch (e) {
      emit(state.copyWith(loadError: e, status: const StateIsSuccess()));
    }
  }

  Future<void> acceptAsk(String itemId) async {
    try {
      emit(state.copyWith(status: const StateIsSuccess()));
      await _coordination.acceptAsk(itemId: itemId);
      await fetch(silent: true);
    } on Object catch (e) {
      emit(state.copyWith(loadError: e, status: const StateIsSuccess()));
    }
  }

  Future<void> resolveAsk(String itemId) async {
    try {
      emit(state.copyWith(status: const StateIsSuccess()));
      await _coordination.resolveAsk(itemId: itemId);
      await fetch(silent: true);
    } on Object catch (e) {
      emit(state.copyWith(loadError: e, status: const StateIsSuccess()));
    }
  }

  Future<void> cancelAsk(String itemId) async {
    try {
      emit(state.copyWith(status: const StateIsSuccess()));
      await _coordination.cancelAsk(itemId: itemId);
      await fetch(silent: true);
    } on Object catch (e) {
      emit(state.copyWith(loadError: e, status: const StateIsSuccess()));
    }
  }

  Future<void> acceptPromise(String itemId) async {
    try {
      emit(state.copyWith(status: const StateIsSuccess()));
      await _coordination.acceptPromise(itemId: itemId);
      await fetch(silent: true);
    } on Object catch (e) {
      emit(state.copyWith(loadError: e, status: const StateIsSuccess()));
    }
  }

  Future<void> resolvePromise(String itemId) async {
    try {
      emit(state.copyWith(status: const StateIsSuccess()));
      await _coordination.resolvePromise(itemId: itemId);
      await fetch(silent: true);
    } on Object catch (e) {
      emit(state.copyWith(loadError: e, status: const StateIsSuccess()));
    }
  }

  Future<void> cancelPromise(String itemId) async {
    try {
      emit(state.copyWith(status: const StateIsSuccess()));
      await _coordination.cancelPromise(itemId: itemId);
      await fetch(silent: true);
    } on Object catch (e) {
      emit(state.copyWith(loadError: e, status: const StateIsSuccess()));
    }
  }

  Future<void> resolvePlanStep(String itemId) async {
    try {
      emit(state.copyWith(status: const StateIsSuccess()));
      await _coordination.resolvePlanStep(itemId: itemId);
      await fetch(silent: true);
    } on Object catch (e) {
      emit(state.copyWith(loadError: e, status: const StateIsSuccess()));
    }
  }

  Future<void> updateItem({
    required String itemId,
    required String title,
    String? body,
  }) async {
    try {
      emit(state.copyWith(status: const StateIsSuccess()));
      await _coordination.updateItem(
        itemId: itemId,
        title: title,
        body: body,
      );
      await fetch(silent: true);
    } on Object catch (e) {
      emit(state.copyWith(loadError: e, status: const StateIsSuccess()));
    }
  }

  Future<void> remindItem(String itemId) async {
    try {
      emit(state.copyWith(status: const StateIsSuccess()));
      await _coordination.remindItem(itemId: itemId);
      await fetch(silent: true);
    } on Object catch (e) {
      emit(state.copyWith(loadError: e, status: const StateIsSuccess()));
    }
  }

  @override
  Future<void> close() async {
    _debouncedFetchTimer?.cancel();
    await _invalidationSub.cancel();
    await _watermarkSub.cancel();
    return super.close();
  }
}
