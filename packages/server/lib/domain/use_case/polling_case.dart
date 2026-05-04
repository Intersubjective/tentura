import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/port/polling_act_repository_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class PollingCase extends UseCaseBase {
  PollingCase(
    this._pollingActRepository, {
    required super.env,
    required super.logger,
  });

  final PollingActRepositoryPort _pollingActRepository;

  Future<bool> create({
    required String authorId,
    required String pollingId,
    required String variantId,
  }) async {
    await _pollingActRepository.create(
      authorId: authorId,
      pollingId: pollingId,
      variantId: variantId,
    );
    return true;
  }
}
