@Tags(['repo-files'])
library;

import 'dart:io';
import 'dart:isolate';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

// These tests intentionally reference the new batch contract on the domain
// port. Until that contract exists, this file must fail to load, not skip.
void main() {
  const viewer = 'Ubatchviewer';
  late _RecordingAnchorRepository repository;
  late ConstellationAnchorCase case_;

  AnchorApplyOp upsert(String opId, String targetId) => AnchorApplyOp(
    clientOpId: opId,
    kind: AnchorOpKind.upsert,
    target: ConstellationAnchorTarget.person(targetId),
    position: const ConstellationAnchorPosition(
      xUnits: 1,
      yUnits: -2,
      coordinateSpaceVersion: 1,
    ),
  );

  Future<void> expectInvalidEnvelope(List<AnchorApplyOp> ops) async {
    await expectLater(
      case_.apply(
        viewerId: viewer,
        ops: ops,
      ),
      throwsA(isA<ConstellationException>()),
    );
    expect(repository.batchCalls, 0, reason: 'Reject before repository IO.');
  }

  setUp(() {
    repository = _RecordingAnchorRepository();
    case_ = ConstellationAnchorCase(
      repository,
      env: Env(environment: Environment.test),
      logger: Logger('ConstellationAnchorBatchValidationTest'),
    );
  });

  group('anchor batch envelope validation', () {
    test('accepts a 65-operation batch through the port', () async {
      final ops = [
        for (var i = 0; i < 65; i++) upsert('limit-$i', 'Ulimit$i'),
      ];
      final result = await case_.apply(
        viewerId: viewer,
        ops: ops,
      );

      expect(repository.batchCalls, 1);
      _expectEquivalentOps(repository.lastOps, ops);
      _expectEquivalentBatchResult(result, repository.result);
    });

    test('accepts exactly 64 distinct operations through the port', () async {
      final ops = [
        for (var i = 0; i < 64; i++) upsert('limit-$i', 'Ulimit$i'),
      ];
      final result = await case_.apply(
        viewerId: viewer,
        ops: ops,
      );

      expect(repository.batchCalls, 1);
      expect(repository.lastViewerId, viewer);
      _expectEquivalentOps(repository.lastOps, ops);
      _expectEquivalentBatchResult(result, repository.result);
    });

    test('rejects more than 400 operations before repository IO', () async {
      await expectInvalidEnvelope([
        for (var i = 0; i < 401; i++) upsert('cap-$i', 'Ucap$i'),
      ]);
    });

    test('accepts exactly 400 distinct operations through the port', () async {
      final ops = [
        for (var i = 0; i < 400; i++) upsert('cap-$i', 'Ucap$i'),
      ];
      final result = await case_.apply(
        viewerId: viewer,
        ops: ops,
      );

      expect(repository.batchCalls, 1);
      _expectEquivalentOps(repository.lastOps, ops);
      _expectEquivalentBatchResult(result, repository.result);
    });

    test('rejects repeated operation ids across distinct targets', () async {
      await expectInvalidEnvelope([
        upsert('repeated-id', 'Upeerone'),
        upsert('repeated-id', 'Upeertwo'),
      ]);
    });

    for (final target in [
      ConstellationAnchorTarget.person('Upeerone'),
      ConstellationAnchorTarget.beacon('Bbeaconone'),
    ]) {
      test(
        'rejects two upserts for the same ${target.kind.wireValue.toLowerCase()} target before repository IO',
        () async {
          await expectInvalidEnvelope([
            for (final opId in ['place-first', 'place-second'])
              AnchorApplyOp(
                clientOpId: opId,
                kind: AnchorOpKind.upsert,
                target: target,
                position: const ConstellationAnchorPosition(
                  xUnits: 1,
                  yUnits: -2,
                  coordinateSpaceVersion: 1,
                ),
              ),
          ]);
        },
      );
      test(
        'rejects two deletes for the same ${target.kind.wireValue.toLowerCase()} target before repository IO',
        () async {
          await expectInvalidEnvelope([
            for (final opId in ['remove-first', 'remove-second'])
              AnchorApplyOp(
                clientOpId: opId,
                kind: AnchorOpKind.delete,
                target: target,
              ),
          ]);
        },
      );
    }

    test('rejects repeated targets across upsert and delete', () async {
      await expectInvalidEnvelope([
        upsert('place-peer', 'Upeerone'),
        AnchorApplyOp(
          clientOpId: 'remove-peer',
          kind: AnchorOpKind.delete,
          target: ConstellationAnchorTarget.person('Upeerone'),
        ),
      ]);
    });

    test('requires a position for every upsert before repository IO', () async {
      await expectInvalidEnvelope([
        upsert('valid-first', 'Upeerone'),
        AnchorApplyOp(
          clientOpId: 'missing-position',
          kind: AnchorOpKind.upsert,
          target: ConstellationAnchorTarget.person('Upeertwo'),
        ),
      ]);
    });

    test('allows a delete without a position', () async {
      final ops = [
        AnchorApplyOp(
          clientOpId: 'remove-peer',
          kind: AnchorOpKind.delete,
          target: ConstellationAnchorTarget.person('Upeerone'),
        ),
      ];
      final result = await case_.apply(
        viewerId: viewer,
        ops: ops,
      );

      expect(repository.batchCalls, 1);
      _expectEquivalentOps(repository.lastOps, ops);
      _expectEquivalentBatchResult(result, repository.result);
    });

    test('allows person and beacon upserts with the same target id', () async {
      final ops = [
        upsert('place-person', 'shared-id'),
        AnchorApplyOp(
          clientOpId: 'place-beacon',
          kind: AnchorOpKind.upsert,
          target: ConstellationAnchorTarget.beacon('shared-id'),
          position: const ConstellationAnchorPosition(
            xUnits: -1,
            yUnits: 2,
            coordinateSpaceVersion: 1,
          ),
        ),
      ];
      final result = await case_.apply(
        viewerId: viewer,
        ops: ops,
      );

      expect(repository.batchCalls, 1);
      _expectEquivalentOps(repository.lastOps, ops);
      _expectEquivalentBatchResult(result, repository.result);
    });

    test('distinguishes person and beacon targets with the same id', () async {
      final ops = [
        upsert('place-person', 'shared-id'),
        AnchorApplyOp(
          clientOpId: 'remove-beacon',
          kind: AnchorOpKind.delete,
          target: ConstellationAnchorTarget.beacon('shared-id'),
        ),
      ];
      await case_.apply(
        viewerId: viewer,
        ops: ops,
      );

      expect(repository.batchCalls, 1);
      _expectEquivalentOps(repository.lastOps, ops);
    });

    test('server domain depends on ports instead of data repositories', () async {
      final serverLibrary = await Isolate.resolvePackageUri(
        Uri.parse(
          'package:tentura_server/domain/use_case/constellation_anchor_case.dart',
        ),
      );
      expect(serverLibrary, isNotNull);
      final resolvedServerLibrary = serverLibrary!;
      expect(resolvedServerLibrary.scheme, 'file');
      final root = _repositoryRootFromServerLibrary(resolvedServerLibrary);
      final domain = Directory.fromUri(
        root.uri.resolve('packages/server/lib/domain/'),
      );
      expect(
        domain.existsSync(),
        isTrue,
        reason: 'Inspect the server domain under the resolved workspace root.',
      );
      expect(
        domain.resolveSymbolicLinksSync(),
        File.fromUri(
          resolvedServerLibrary,
        ).parent.parent.resolveSymbolicLinksSync(),
        reason: 'The inspected tree must contain the imported server use case.',
      );
      expect(
        File.fromUri(
          domain.uri.resolve('port/constellation_anchor_repository_port.dart'),
        ).existsSync(),
        isTrue,
      );
      final dartFiles = domain
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();
      expect(dartFiles, isNotEmpty);
      final violations = <String>[];
      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains('package:tentura_server/data/repository')) {
            violations.add('${file.path}:${i + 1}: ${lines[i]}');
          }
        }
      }
      expect(violations, isEmpty);
    });
  });
}

Directory _repositoryRootFromServerLibrary(Uri serverLibrary) {
  var candidate = File.fromUri(serverLibrary).parent;
  final rootName = RegExp(r'^name:\s*tentura_root\s*$', multiLine: true);
  while (true) {
    final rootPubspec = File.fromUri(candidate.uri.resolve('pubspec.yaml'));
    final serverPubspec = File.fromUri(
      candidate.uri.resolve('packages/server/pubspec.yaml'),
    );
    if (rootPubspec.existsSync() &&
        serverPubspec.existsSync() &&
        rootName.hasMatch(rootPubspec.readAsStringSync())) {
      return Directory(candidate.resolveSymbolicLinksSync());
    }
    final parent = candidate.parent;
    if (parent.path == candidate.path) {
      throw StateError('Tentura workspace root not found for $serverLibrary');
    }
    candidate = parent;
  }
}

void _expectEquivalentOps(
  List<AnchorApplyOp>? actual,
  List<AnchorApplyOp> expected,
) {
  expect(actual, isNotNull);
  List<Object> values(List<AnchorApplyOp> ops) => [
    for (final op in ops)
      (op.clientOpId, op.kind, op.target, op.position, op.ifRevision),
  ];
  expect(values(actual!), values(expected));
}

void _expectEquivalentBatchResult(
  AnchorApplyBatchResult actual,
  AnchorApplyBatchResult expected,
) {
  expect(actual.beforeRevision, expected.beforeRevision);
  expect(actual.afterRevision, expected.afterRevision);
  expect(
    [
      for (final result in actual.results)
        (
          result.clientOpId,
          result.status,
          result.reason,
          result.resultingTargetRevision,
          result.position,
          result.anchor,
          result.replayed,
        ),
    ],
    [
      for (final result in expected.results)
        (
          result.clientOpId,
          result.status,
          result.reason,
          result.resultingTargetRevision,
          result.position,
          result.anchor,
          result.replayed,
        ),
    ],
  );
}

final class _RecordingAnchorRepository
    implements ConstellationAnchorRepositoryPort {
  final result = AnchorApplyBatchResult(
    beforeRevision: ConstellationAnchorRevision(BigInt.from(3)),
    afterRevision: ConstellationAnchorRevision(BigInt.from(4)),
    results: const [],
  );
  int batchCalls = 0;
  String? lastViewerId;
  List<AnchorApplyOp>? lastOps;

  @override
  Future<AnchorApplyBatchResult> applyBatch({
    required String viewerId,
    required List<AnchorApplyOp> ops,
  }) async {
    batchCalls++;
    lastViewerId = viewerId;
    lastOps = List.of(ops);
    return result;
  }

  @override
  Future<ConstellationAnchorRevision> readWatermark(String viewerId) =>
      throw StateError('The batch result supplies its revisions.');

  @override
  Future<AnchorResetResult> resetAll({
    required String viewerId,
    required String clientOpId,
  }) => throw UnimplementedError('not used by this test');
}
