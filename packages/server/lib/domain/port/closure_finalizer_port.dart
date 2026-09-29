import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/closure/finalize_reason.dart';

abstract interface class ClosureFinalizerPort {
  Future<void> finalize({
    required String beaconId,
    required int epoch,
    required FinalizeReason reason,
  });
}

/// Placeholder until A14 registers [ClosureFinalizeCase] as [ClosureFinalizerPort].
@Singleton(as: ClosureFinalizerPort)
final class UnimplementedClosureFinalizer implements ClosureFinalizerPort {
  @override
  Future<void> finalize({
    required String beaconId,
    required int epoch,
    required FinalizeReason reason,
  }) async {
    throw UnimplementedError('ClosureFinalizerPort until A14');
  }
}
