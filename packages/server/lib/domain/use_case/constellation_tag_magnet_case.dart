import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'package:tentura_server/domain/entity/constellation_tag_magnet.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/constellation_tag_magnet_repository_port.dart';

import '_use_case_base.dart';

/// A viewer's magnets for their own tags. Only the viewer reaches them: every
/// call is scoped by the JWT subject the API layer passes in.
@Singleton(order: 2)
final class ConstellationTagMagnetCase extends UseCaseBase {
  ConstellationTagMagnetCase(
    this._repository, {
    required super.env,
    required super.logger,
  });

  final ConstellationTagMagnetRepositoryPort _repository;

  Future<List<ConstellationTagMagnet>> list({required String viewerId}) =>
      _repository.list(viewerId);

  Future<ConstellationTagMagnet> upsert({
    required String viewerId,
    required String tagId,
    required double xUnits,
    required double yUnits,
    required String clientOpId,
  }) async {
    _checkOpId(clientOpId);
    if (!ConstellationAnchorPosition.isFiniteV1Axis(xUnits) ||
        !ConstellationAnchorPosition.isFiniteV1Axis(yUnits)) {
      throw ConstellationException(
        constellationCode: ConstellationExceptionCode.invalidCoordinates,
      );
    }
    return _repository.upsert(
      viewerId: viewerId,
      tagId: tagId,
      xUnits: xUnits,
      yUnits: yUnits,
      clientOpId: clientOpId,
    );
  }

  Future<void> remove({
    required String viewerId,
    required String tagId,
    required String clientOpId,
  }) async {
    _checkOpId(clientOpId);
    return _repository.remove(
      viewerId: viewerId,
      tagId: tagId,
      clientOpId: clientOpId,
    );
  }

  void _checkOpId(String clientOpId) {
    if (clientOpId.isEmpty || clientOpId.length > 64) {
      throw ConstellationException(
        constellationCode: ConstellationExceptionCode.invalidTarget,
        description: 'A tag magnet needs an operation id of 1 to 64 characters',
      );
    }
  }
}
