import 'package:flutter/scheduler.dart';

import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';

import 'room_cubit.dart';
import 'thread_host_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

typedef RoomCubitFactory = RoomCubit Function({
  required String beaconId,
  String? threadItemId,
  DateTime? initialUnreadAnchorAt,
});

class ThreadHostCubit extends Cubit<ThreadHostState> {
  ThreadHostCubit({
    required String beaconId,
    RoomCubitFactory roomCubitFactory = RoomCubit.new,
  }) : _beaconId = beaconId,
       _factory = roomCubitFactory,
       super(const ThreadHostState());

  final String _beaconId;
  final RoomCubitFactory _factory;

  RoomCubit? _roomCubit;
  Future<void> _switchTail = Future<void>.value();
  int _windowClassTransitionGeneration = 0;

  RoomCubit? get roomCubit => _roomCubit;

  void _cancelWindowClassTransition() {
    _windowClassTransitionGeneration++;
  }

  /// Schedules [action] once after the next frame. Superseded when a newer
  /// transition is scheduled or when [select]/[clear] runs.
  void scheduleWindowClassTransition(void Function() action) {
    final generation = ++_windowClassTransitionGeneration;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      if (isClosed || generation != _windowClassTransitionGeneration) return;
      action();
    });
  }

  Future<void> select(RequestThread thread) async {
    _cancelWindowClassTransition();
    final generation = state.selectionGeneration + 1;
    emit(state.copyWith(switching: true, selectionGeneration: generation));
    final operation = _switchTail.then((_) async {
      if (isClosed || generation != state.selectionGeneration) return;
      final old = _roomCubit;
      _roomCubit = null;
      if (old != null && !old.isClosed) await old.close();
      if (isClosed || generation != state.selectionGeneration) return;
      final itemId = thread.threadId == RequestThread.generalId
          ? null
          : thread.threadId;
      _roomCubit = _factory(
        beaconId: thread.item?.beaconId ?? _beaconId,
        threadItemId: itemId,
        initialUnreadAnchorAt: thread.lastSeenAt,
      );
      emit(
        state.copyWith(
          openThreadId: thread.threadId,
          switching: false,
        ),
      );
    });
    _switchTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<void> clear() async {
    _cancelWindowClassTransition();
    final generation = state.selectionGeneration + 1;
    emit(state.copyWith(switching: true, selectionGeneration: generation));
    final operation = _switchTail.then((_) async {
      if (isClosed || generation != state.selectionGeneration) return;
      final old = _roomCubit;
      _roomCubit = null;
      if (old != null && !old.isClosed) await old.close();
      if (isClosed || generation != state.selectionGeneration) return;
      emit(state.copyWith(openThreadId: null, switching: false));
    });
    _switchTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  @override
  Future<void> close() async {
    final generation = state.selectionGeneration + 1;
    emit(state.copyWith(selectionGeneration: generation));
    await _switchTail;
    final owned = _roomCubit;
    _roomCubit = null;
    if (owned != null && !owned.isClosed) {
      await owned.close();
    }
    return super.close();
  }
}
