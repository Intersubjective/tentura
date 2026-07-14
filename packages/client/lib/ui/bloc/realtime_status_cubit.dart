import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';

import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';

import 'realtime_status_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'realtime_status_state.dart';

/// Global presentation state for actionable realtime transport outages.
@singleton
final class RealtimeStatusCubit extends Cubit<RealtimeStatusState> {
  RealtimeStatusCubit(RealtimeSyncCase realtime)
    : this.forTesting(realtime, pausedDelay: const Duration(seconds: 2));

  @visibleForTesting
  RealtimeStatusCubit.forTesting(
    RealtimeSyncCase realtime, {
    required Duration pausedDelay,
    // Keep the public testing seam free of a private named parameter.
    // ignore: prefer_initializing_formals
  }) : _pausedDelay = pausedDelay,
       super(const RealtimeStatusState()) {
    _statusSub = realtime.connectionStatuses.listen(
      _onStatus,
      cancelOnError: false,
    );
  }

  final Duration _pausedDelay;
  late final StreamSubscription<RealtimeConnectionStatus> _statusSub;
  Timer? _pausedTimer;
  int _statusGeneration = 0;

  void _onStatus(RealtimeConnectionStatus status) {
    final generation = ++_statusGeneration;
    _pausedTimer?.cancel();
    final phase = status.phase;
    if (phase == RealtimeConnectionPhase.authenticated ||
        phase == RealtimeConnectionPhase.unbound ||
        status.accountId == null ||
        status.accountId!.isEmpty) {
      emit(RealtimeStatusState(phase: phase));
      return;
    }
    emit(RealtimeStatusState(phase: phase));
    _pausedTimer = Timer(_pausedDelay, () {
      if (!isClosed && generation == _statusGeneration) {
        emit(RealtimeStatusState(phase: phase, showPausedBanner: true));
      }
    });
  }

  @override
  @disposeMethod
  Future<void> close() async {
    _statusGeneration++;
    _pausedTimer?.cancel();
    await _statusSub.cancel();
    return super.close();
  }
}
