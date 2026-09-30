import 'package:tentura_server/domain/closure/finalize_reason.dart';

abstract interface class ClosureFinalizerPort {
  Future<void> finalize({
    required String beaconId,
    required int epoch,
    required FinalizeReason reason,
  });
}
