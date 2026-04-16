import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/evaluation_repository_port.dart';

@Injectable(order: 2)
final class EvaluationDraftPurger {
  EvaluationDraftPurger(this._evaluationRepository);

  final EvaluationRepositoryPort _evaluationRepository;

  Future<void> purgeDraftsOutsideVisibility(String beaconId) async {
    final allowed = await _evaluationRepository.listAllVisibility(beaconId);
    final allowedSet = {
      for (final v in allowed) '${v.evaluatorId}\x00${v.participantId}',
    };
    final drafts = await _evaluationRepository.listDraftRowsForBeacon(beaconId);
    for (final d in drafts) {
      final key = '${d.evaluatorId}\x00${d.evaluatedUserId}';
      if (!allowedSet.contains(key)) {
        await _evaluationRepository.deleteEvaluationRow(
          beaconId: beaconId,
          evaluatorId: d.evaluatorId,
          evaluatedUserId: d.evaluatedUserId,
        );
      }
    }
  }
}
