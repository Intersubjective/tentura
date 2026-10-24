import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
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
  }) async {
    if (ops.length > kConstellationAnchorBatchCap) {
      throw ConstellationException(
        constellationCode: ConstellationExceptionCode.invalidTarget,
        description:
            'An anchor batch may contain at most '
            '$kConstellationAnchorBatchCap operations',
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
    return _repository.applyBatch(viewerId: viewerId, ops: ops);
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
    String? baseRevisionWire,
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
      position:
          xUnits == null || yUnits == null || coordinateSpaceVersion == null
          ? null
          : _parsePosition(
              xUnits: xUnits,
              yUnits: yUnits,
              coordinateSpaceVersion: coordinateSpaceVersion,
            ),
      ifRevision: ifRevision,
      baseRevision: baseRevisionWire == null
          ? null
          : _parseRevision(baseRevisionWire),
    );
  }

  /// Resets every anchor of [viewerId] (#251); a retry with the same
  /// [clientOpId] returns the recorded outcome without writing again.
  Future<AnchorResetResult> reset({
    required String viewerId,
    required String clientOpId,
  }) {
    if (clientOpId.isEmpty || clientOpId.length > 64) {
      throw ConstellationException(
        constellationCode: ConstellationExceptionCode.invalidTarget,
        description: 'A reset needs an operation id of 1 to 64 characters',
      );
    }
    return _repository.resetAll(viewerId: viewerId, clientOpId: clientOpId);
  }

  ConstellationAnchorRevision _parseRevision(String wire) {
    final parsed = ConstellationAnchorRevision.parseDecimalString(wire);
    if (parsed is! ConstellationAnchorRevisionParsed) {
      throw ConstellationException(
        constellationCode: ConstellationExceptionCode.invalidTarget,
      );
    }
    return parsed.revision;
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
