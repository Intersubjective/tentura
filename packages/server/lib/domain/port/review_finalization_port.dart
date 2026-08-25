import 'package:tentura_server/domain/entity/review_finalization_result.dart';

abstract interface class ReviewFinalizationPort {
  Future<ReviewFinalizationResult> closeAndFinalize(
    String beaconId, {
    required String reason,
    String? actorUserId,
    bool requireAllRequiredPackagesSent = false,
  });
}
