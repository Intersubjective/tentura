import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/attention_expiry_repository_port.dart';

import '../database/tentura_db.dart';

@LazySingleton(as: AttentionExpiryRepositoryPort)
class AttentionExpiryRepository implements AttentionExpiryRepositoryPort {
  const AttentionExpiryRepository(
    // Kept for DI/call-site arity; m0203 (A6) dropped `beacon_review_window`,
    // so no review window can ever be due. A18 deletes this call path.
    // ignore: avoid_unused_constructor_parameters
    TenturaDb database,
  );

  /// Post-m0203 there are no review windows, so the expired set is empty by
  /// construction.
  @override
  Future<List<String>> lockExpiredReviewWindowBeaconIds(DateTime now) =>
      Future.value(const []);
}
