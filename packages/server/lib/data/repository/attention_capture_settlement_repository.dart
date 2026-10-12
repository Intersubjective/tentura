import 'package:injectable/injectable.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/port/attention_capture_settlement_port.dart';

import 'attention_sweep_repository.dart';

/// Exposes [AttentionSweepRepository.settleAbandonedCaptures] as its own port.
/// The sweep repository is stateless over the database, so it is built here
/// rather than registered a second time under another interface.
@Singleton(as: AttentionCaptureSettlementPort)
class AttentionCaptureSettlementRepository
    implements AttentionCaptureSettlementPort {
  AttentionCaptureSettlementRepository(TenturaDb database)
    : _sweep = AttentionSweepRepository(database);

  final AttentionSweepRepository _sweep;

  @override
  Future<int> settleAbandonedCaptures({
    required Duration staleAfter,
    required Duration expireAfter,
  }) => _sweep.settleAbandonedCaptures(
    staleAfter: staleAfter,
    expireAfter: expireAfter,
  );
}
