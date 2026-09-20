import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/port/attention_reconcile_port.dart';

/// A reconcile that never answers.
///
/// Settings now carries **Reset counters**, so any test that renders the
/// whole screen resolves the narrow port it needs. Holding the answer keeps
/// these tests about what they were about: nothing here taps the command.
final class HangingReconcilePort implements AttentionReconcilePort {
  final List<Completer<AttentionReconcileResult>> pending = [];

  @override
  Future<AttentionReconcileResult> reconcile() {
    final completer = Completer<AttentionReconcileResult>();
    pending.add(completer);
    return completer.future;
  }
}

/// Registers [HangingReconcilePort] unless the host test already provided one,
/// and returns the teardown that undoes exactly what it did.
void Function() registerReconcilePortForScreenTest() {
  if (GetIt.I.isRegistered<AttentionReconcilePort>()) return () {};
  GetIt.I.registerSingleton<AttentionReconcilePort>(HangingReconcilePort());
  return () {
    if (GetIt.I.isRegistered<AttentionReconcilePort>()) {
      GetIt.I.unregister<AttentionReconcilePort>();
    }
  };
}
