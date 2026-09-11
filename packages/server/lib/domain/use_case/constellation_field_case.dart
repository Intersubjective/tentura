import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/port/constellation_field_repository_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class ConstellationFieldCase extends UseCaseBase {
  ConstellationFieldCase(
    this._repository, {
    required super.env,
    required super.logger,
  });

  final ConstellationFieldRepositoryPort _repository;

  Future<ConstellationFieldSnapshot> load({
    required String viewerId,
    required String context,
  }) =>
      readSnapshot(
        viewerId: viewerId,
        context: context,
        params: (
          filters: ConstellationFieldMembershipFilters.defaults,
          projection: ConstellationProjection.full,
        ),
      );

  Future<ConstellationFieldSnapshot> readSnapshot({
    required String viewerId,
    required String context,
    required ConstellationFieldReadParams params,
  }) {
    if (viewerId.trim().isEmpty) {
      final loadedAt = DateTime.now().toUtc();
      return Future.value(
        ConstellationFieldSnapshot(
          loadedAt: loadedAt,
          context: context,
          peers: const [],
          edges: const [],
          requests: const [],
          peersCapped: false,
          requestsCapped: false,
        ),
      );
    }
    return _repository.readSnapshot(
      viewerId: viewerId,
      context: context,
      params: params,
    );
  }
}
