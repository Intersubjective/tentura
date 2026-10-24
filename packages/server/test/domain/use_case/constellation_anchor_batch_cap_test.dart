import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

/// The anchor batch limit is one named constant, and the use case enforces
/// exactly that value. The constant may live in `constellation_consts.dart` or
/// the use case file; both are imported here.
void main() {
  late _CountingRepository repository;
  late ConstellationAnchorCase case_;

  AnchorApplyOp upsert(int i) => AnchorApplyOp(
    clientOpId: 'cap-$i',
    kind: AnchorOpKind.upsert,
    target: ConstellationAnchorTarget.person('Ucapconst$i'),
    position: const ConstellationAnchorPosition(
      xUnits: 1,
      yUnits: 1,
      coordinateSpaceVersion: 1,
    ),
  );

  setUp(() {
    repository = _CountingRepository();
    case_ = ConstellationAnchorCase(
      repository,
      env: Env(environment: Environment.test),
      logger: Logger('ConstellationAnchorBatchCapConstantTest'),
    );
  });

  group('anchor batch cap', () {
    test('use case accepts a batch of exactly the cap', () async {
      await case_.apply(
        viewerId: 'Ucapconstviewer',
        ops: [for (var i = 0; i < kConstellationAnchorBatchCap; i++) upsert(i)],
      );
      expect(repository.batchCalls, 1);
    });

    test('use case refuses a batch one above the cap before IO', () async {
      await expectLater(
        case_.apply(
          viewerId: 'Ucapconstviewer',
          ops: [
            for (var i = 0; i <= kConstellationAnchorBatchCap; i++) upsert(i),
          ],
        ),
        throwsA(isA<ConstellationException>()),
      );
      expect(repository.batchCalls, 0);
    });
  });
}

final class _CountingRepository implements ConstellationAnchorRepositoryPort {
  int batchCalls = 0;

  @override
  Future<AnchorApplyBatchResult> applyBatch({
    required String viewerId,
    required List<AnchorApplyOp> ops,
  }) async {
    batchCalls++;
    return AnchorApplyBatchResult(
      beforeRevision: ConstellationAnchorRevision(BigInt.zero),
      afterRevision: ConstellationAnchorRevision(BigInt.from(ops.length)),
      results: const [],
    );
  }

  @override
  Future<ConstellationAnchorRevision> readWatermark(String viewerId) =>
      throw UnimplementedError('not used by this test');

  @override
  Future<AnchorResetResult> resetAll({
    required String viewerId,
    required String clientOpId,
  }) => throw UnimplementedError('not used by this test');
}
