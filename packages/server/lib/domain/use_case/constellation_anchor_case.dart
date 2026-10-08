import 'package:injectable/injectable.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class ConstellationAnchorCase extends UseCaseBase {
  ConstellationAnchorCase(
    this._repository, {
    required super.env,
    required super.logger,
  });

  final ConstellationAnchorRepositoryPort _repository;

  Future<AnchorApplyBatchResult> apply({
    required String viewerId,
    required List<AnchorApplyOp> ops,
    required AnchorApplyParams params,
  }) async {
    if (ops.length > 64) {
      throw ConstellationException(
        constellationCode: ConstellationExceptionCode.invalidTarget,
        description: 'An anchor batch may contain at most 64 operations',
      );
    }
    final opIds = <String>{};
    final targets = <ConstellationAnchorTarget>{};
    for (final op in ops) {
      if (!opIds.add(op.clientOpId) || !targets.add(op.target)) {
        throw ConstellationException(
          constellationCode: ConstellationExceptionCode.invalidTarget,
          description: 'Duplicate anchor operation id or target',
        );
      }
      if (op.kind == AnchorOpKind.upsert && op.position == null) {
        throw ConstellationException(
          constellationCode: ConstellationExceptionCode.invalidCoordinates,
        );
      }
    }
    return _repository.applyBatch(viewerId: viewerId, ops: ops, params: params);
  }

  /// Parses one wire-level batch operation; a missing UPSERT position is
  /// rejected later by [apply].
  AnchorApplyOp parseOp({
    required String viewerId,
    required String clientOpId,
    required String kindWire,
    required String targetKindWire,
    required String targetId,
    double? xUnits,
    double? yUnits,
    int? coordinateSpaceVersion,
    String? ifRevisionWire,
  }) {
    final kind = AnchorOpKind.values.where((k) => k.wireValue == kindWire);
    if (kind.isEmpty) {
      throw ConstellationException(
        constellationCode: ConstellationExceptionCode.invalidTarget,
      );
    }
    final target = _parseTarget(
      viewerId: viewerId,
      targetKindWire: targetKindWire,
      targetId: targetId,
    );
    final ConstellationAnchorRevision? ifRevision;
    if (ifRevisionWire == null) {
      ifRevision = null;
    } else {
      final parsed = ConstellationAnchorRevision.parseDecimalString(
        ifRevisionWire,
      );
      if (parsed is! ConstellationAnchorRevisionParsed) {
        throw ConstellationException(
          constellationCode: ConstellationExceptionCode.invalidTarget,
        );
      }
      ifRevision = parsed.revision;
    }
    return AnchorApplyOp(
      clientOpId: clientOpId,
      kind: kind.single,
      target: target,
      position: xUnits == null || yUnits == null || coordinateSpaceVersion == null
          ? null
          : _parsePosition(
              xUnits: xUnits,
              yUnits: yUnits,
              coordinateSpaceVersion: coordinateSpaceVersion,
            ),
      ifRevision: ifRevision,
    );
  }

  Future<ConstellationAnchorUpsertResult> upsert({
    required String viewerId,
    required String targetKindWire,
    required String targetId,
    required double xUnits,
    required double yUnits,
    required int coordinateSpaceVersion,
  }) {
    final target = _parseTarget(
      viewerId: viewerId,
      targetKindWire: targetKindWire,
      targetId: targetId,
    );
    final position = _parsePosition(
      xUnits: xUnits,
      yUnits: yUnits,
      coordinateSpaceVersion: coordinateSpaceVersion,
    );
    return _repository.upsertAnchor(
      viewerId: viewerId,
      context: kConstellationContext,
      target: target,
      position: position,
    );
  }

  Future<ConstellationAnchorDeleteResult> delete({
    required String viewerId,
    required String targetKindWire,
    required String targetId,
  }) {
    final target = _parseTarget(
      viewerId: viewerId,
      targetKindWire: targetKindWire,
      targetId: targetId,
    );
    return _repository.deleteAnchor(
      viewerId: viewerId,
      target: target,
    );
  }

  ConstellationAnchorTarget _parseTarget({
    required String viewerId,
    required String targetKindWire,
    required String targetId,
  }) {
    final target = ConstellationAnchorTarget.tryFromWire(
      kindWire: targetKindWire,
      targetId: targetId,
    );
    final validation = validateConstellationAnchorTarget(
      target: target,
      viewerId: viewerId,
    );
    if (validation is! ConstellationAnchorTargetValid) {
      throw ConstellationException(
        constellationCode: ConstellationExceptionCode.invalidTarget,
      );
    }
    return validation.target;
  }

  ConstellationAnchorPosition _parsePosition({
    required double xUnits,
    required double yUnits,
    required int coordinateSpaceVersion,
  }) {
    final validation = ConstellationAnchorPosition.validate(
      xUnits: xUnits,
      yUnits: yUnits,
      coordinateSpaceVersion: coordinateSpaceVersion,
    );
    switch (validation) {
      case ConstellationAnchorPositionValid(:final position):
        return position;
      case ConstellationAnchorPositionInvalid(:final reason):
        throw ConstellationException(
          constellationCode: switch (reason) {
            ConstellationAnchorPositionInvalidReason
                .unsupportedCoordinateSpace =>
              ConstellationExceptionCode.unsupportedCoordinateSpace,
            ConstellationAnchorPositionInvalidReason.nonFinite ||
            ConstellationAnchorPositionInvalidReason.outOfRange =>
              ConstellationExceptionCode.invalidCoordinates,
          },
        );
    }
  }
}
