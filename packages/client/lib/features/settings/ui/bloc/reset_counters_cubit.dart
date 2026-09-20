// `resetCounters` returns its future so a caller — and every test in this
// feature — can await one run without polling the state.
// ignore_for_file: prefer_void_public_cubit_methods

import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/port/attention_reconcile_port.dart';

import 'reset_counters_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'reset_counters_state.dart';

/// Settings **Reset counters** — D15.
///
/// Rechecks the account's updates and outstanding actions against their
/// source state and adopts whatever the server says is true. It erases
/// nothing, and the result it reports is never a claim that the user has no
/// work: [ResetCountersOutcome.refreshed] is what a repair *that still found
/// work* returns too.
class ResetCountersCubit extends Cubit<ResetCountersState> {
  ResetCountersCubit({AttentionReconcilePort? attention})
    : _attention = attention ?? GetIt.I<AttentionReconcilePort>(),
      super(const ResetCountersState());

  final AttentionReconcilePort _attention;

  static final _log = Logger('ResetCountersCubit');

  Future<void> resetCounters() async {
    // One repair at a time. A double tap would otherwise race two adoptions
    // of two summaries, and the later answer is not necessarily the fresher.
    if (state.isRunning) return;
    emit(state.copyWith(isRunning: true));
    try {
      await _attention.reconcile();
      _finish(ResetCountersOutcome.refreshed);
    } catch (error, stackTrace) {
      // Honest failure: the counters were not refreshed, so nothing pretends
      // they were.
      _log.warning('Reset counters failed', error, stackTrace);
      _finish(ResetCountersOutcome.failed);
    }
  }

  void _finish(ResetCountersOutcome outcome) {
    if (isClosed) return;
    emit(
      state.copyWith(
        isRunning: false,
        outcome: outcome,
        outcomeSerial: state.outcomeSerial + 1,
      ),
    );
  }
}
