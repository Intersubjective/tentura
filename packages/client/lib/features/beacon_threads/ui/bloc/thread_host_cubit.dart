import 'package:flutter/widgets.dart';

import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';

import 'room_cubit.dart';
import 'thread_host_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

typedef RoomCubitFactory = RoomCubit Function({
  required String beaconId,
  String? threadItemId,
  DateTime? initialUnreadAnchorAt,
});

/// Hosts the General discussion room only (plan §6.1).
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

  void scheduleWindowClassTransition(void Function() action) {
    final generation = ++_windowClassTransitionGeneration;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      if (isClosed || generation != _windowClassTransitionGeneration) return;
      action();
    });
  }

  Future<void> ensureGeneral(RequestThread generalThread) async {
    if (!generalThread.isGeneral) return;
    if (state.openThreadId == RequestThread.generalId && _roomCubit != null) {
      return;
    }
    await select(generalThread);
  }

  Future<void> select(RequestThread thread) async {
    if (!thread.isGeneral) return;
    _cancelWindowClassTransition();
    final generation = state.selectionGeneration + 1;
    emit(state.copyWith(switching: true, selectionGeneration: generation));
    final operation = _switchTail.then((_) async {
      if (isClosed || generation != state.selectionGeneration) return;
      final old = _roomCubit;
      _roomCubit = null;
      if (old != null && !old.isClosed) await old.close();
      if (isClosed || generation != state.selectionGeneration) return;
      _roomCubit = _factory(
        beaconId: _beaconId,
        threadItemId: null,
        initialUnreadAnchorAt: thread.lastSeenAt,
      );
      emit(
        state.copyWith(
          openThreadId: RequestThread.generalId,
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
