import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/trust_ledger_port.dart';
import 'package:tentura_server/domain/trust/ledger_evidence.dart';

@Singleton(
  as: TrustLedgerPort,
  env: [Environment.test],
  order: 1,
)
class TrustLedgerRepositoryMock implements TrustLedgerPort {
  @override
  Future<void> record(List<LedgerEvidence> evidence) => Future.value();

  @override
  Future<void> retract(String sourceKey) => Future.value();

  @override
  Future<void> unretract(String sourceKey) => Future.value();

  @override
  Future<bool> exists(String sourceKey) => Future.value(false);

  @override
  Future<bool> hasLiveUsefulForwardSince(
    String subjectId,
    String objectId,
    DateTime since,
  ) => Future.value(false);

  @override
  Future<void> lockPair(String subjectId, String objectId) => Future.value();

  @override
  Future<void> project(List<(String, String)> pairs) => Future.value();
}
