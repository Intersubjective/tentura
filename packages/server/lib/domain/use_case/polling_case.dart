import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/port/polling_act_repository_port.dart';

import 'package:tentura_server/data/repository/polling_repository.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class PollingCase extends UseCaseBase {
  PollingCase(
    this._pollingActRepository,
    this._pollingRepository, {
    required super.env,
    required super.logger,
  });

  final PollingActRepositoryPort _pollingActRepository;
  final PollingRepository _pollingRepository;

  Future<bool> create({
    required String authorId,
    required String pollingId,
    required List<String> variantIds,
    int? score,
  }) async {
    final polling = await _pollingRepository.findById(pollingId);
    if (polling == null) throw ArgumentError('Poll not found: $pollingId');

    final pollType = polling.pollType;

    if (score != null) {
      if (pollType != 'range') throw ArgumentError('score only valid for range polls');
      if (score < 0 || score > 5) throw ArgumentError('score must be 0–5');
    }
    if (pollType == 'single' && variantIds.length > 1) {
      throw ArgumentError('single polls accept exactly one variantId');
    }

    await _pollingActRepository.upsert(
      authorId: authorId,
      pollingId: pollingId,
      variantIds: variantIds,
      pollType: pollType,
      allowRevote: polling.allowRevote,
      score: score,
    );
    return true;
  }
}
