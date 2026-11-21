import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';

import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/op_id_service.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import 'package:tentura/domain/port/op_id_port.dart';
import 'package:tentura/domain/use_case/post_bud_case.dart';
import 'package:tentura/env.dart';

import '../../features/beacon_create/fake_beacon_ports.dart';
import '../../features/beacon_create/post_bud_fakes.dart';
import '../../features/my_work/my_work_test_support.dart'
    show buildStubAttentionCase;
import '../../support/attention_case_factory.dart';
import '../../support/beacon_create_case_factory.dart';
import '../../support/remote_wire_harness.dart';
import 'fake_beacon_hierarchy_ports.dart';

final class _CountingOpIds implements OpIdPort {
  int calls = 0;

  @override
  String newOpId() => 'op-${++calls}';
}

void main() {
  group('domain cases mint operation ids through OpIdPort', () {
    test(
      'BeaconHierarchyCase stores the injected id for a new child',
      () async {
        final opIds = _CountingOpIds();
        final store = InMemoryBeaconChildCommandStore();
        final write = FakeBeaconWritePort();
        final sut = buildBeaconHierarchyCaseForTest(
          FakeBeaconHierarchyRepositoryPort(),
          createCase: buildBeaconCreateCase(beacons: write),
          beacons: write,
          commandStore: store,
          opIds: opIds,
        );
        const context = BeaconCreationContextChild(parentBeaconId: 'parent-1');

        final session = await sut.openComposer(creationContext: context);
        final again = await sut.openComposer(creationContext: context);

        expect(session.clientCommandId, 'op-1');
        expect(again.clientCommandId, 'op-1');
        expect(await store.read(context), 'op-1');
        expect(opIds.calls, 1);
      },
    );

    test('PostBudCase returns a fresh injected id per session', () {
      final opIds = _CountingOpIds();
      final sut = PostBudCase(
        FakePostBudPort(),
        opIds,
        env: const Env(),
        logger: Logger('op-id-port-injection-test'),
      );

      expect(sut.newClientCommandId(), 'op-1');
      expect(sut.newClientCommandId(), 'op-2');
    });

    test('production OpIdService still mints uuid v4 strings', () {
      final id = OpIdService().newOpId();

      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });
  });

  group('AttentionCase operation ids', () {
    late _CountingOpIds opIds;
    late _RecordingAttentionRepository repository;
    late AttentionCase attention;

    setUp(() {
      opIds = _CountingOpIds();
      repository = _RecordingAttentionRepository();
      attention = _buildAttention(repository, opIds);
      addTearDown(attention.dispose);
    });

    test('sends and returns the injected id for a receipt clear', () async {
      final sent = <WireSent>[];
      await withRemoteWire(
        const {},
        sent,
        (remote) async {
          final wireOpIds = _CountingOpIds();
          final wireAttention = _buildAttention(
            AttentionRepository(remote),
            wireOpIds,
          );
          try {
            final result = await wireAttention.clearReceipt(receiptId: 'r1');
            final clear = sent.singleWhere(
              (request) => request.operationName == 'AttentionClear',
            );
            expect(clear.variables['operationId'], 'op-1');
            expect(result.operationId, 'op-1');
            expect(wireOpIds.calls, 1);
          } finally {
            await wireAttention.dispose();
          }
        },
        responseFor: (request) async => switch (request.operationName) {
          'AttentionClearSnapshot' => {
            'attentionClearSnapshot': {
              'snapshotToken': 'receipt-snapshot',
              'receiptIds': ['r1'],
              'outcomeGeneration': 0,
              'decisionRevision': 0,
            },
          },
          'AttentionClear' => {
            'attentionClear': {
              'operationId': request.variables['operationId'],
              'status': 'complete',
              'appliedReceiptIds': ['r1'],
              'skippedReceiptIds': <String>[],
              'deniedReceiptIds': <String>[],
            },
          },
          _ => throw StateError(
            'Unexpected operation ${request.operationName}',
          ),
        },
      );
    });

    test('sends and returns the injected id for a Request clear', () async {
      final result = await attention.clearBeacon(beaconId: 'b1');

      expect(repository.clearOperationIds, ['op-1']);
      expect(result.operationId, 'op-1');
      expect(opIds.calls, 1);
    });

    test('sends and returns the injected id when opening a Request', () async {
      final result = await attention.clearRequestOpen(beaconId: 'b1');

      expect(repository.clearOperationIds, ['op-1']);
      expect(result.operationId, 'op-1');
      expect(opIds.calls, 1);
    });

    test('successive receipt clears get distinct injected ids', () async {
      final first = await attention.clearReceipt(receiptId: 'r1');
      final second = await attention.clearReceipt(receiptId: 'r2');

      expect(repository.clearOperationIds, ['op-1', 'op-2']);
      expect([first.operationId, second.operationId], ['op-1', 'op-2']);
      expect(opIds.calls, 2);
    });

    test('starting a dismissal sweep uses one injected id', () async {
      final result = await attention.dismissAll();

      expect(repository.sweepOperationIds, ['op-1']);
      expect(result.operationId, 'op-1');
      expect(opIds.calls, 1);
    });

    test('resuming a sweep preserves its id and the next fresh id', () async {
      final resumed = await attention.dismissAll(operationId: 'resume-7');
      expect(repository.sweepOperationIds, ['resume-7']);
      expect(resumed.operationId, 'resume-7');
      expect(opIds.calls, 0);

      final fresh = await attention.dismissAll();
      expect(repository.sweepOperationIds, ['resume-7', 'op-1']);
      expect(fresh.operationId, 'op-1');
      expect(opIds.calls, 1);
    });

    test('fixture callers can omit the operation ID override', () async {
      final sharedRepository = _RecordingAttentionRepository();
      final myWorkRepository = _RecordingAttentionRepository();
      final shared = buildAttentionCase(repository: sharedRepository);
      addTearDown(shared.dispose);
      final myWork = buildStubAttentionCase(repository: myWorkRepository);
      addTearDown(myWork.dispose);

      for (final (fixture, fixtureRepository) in [
        (shared, sharedRepository),
        (myWork, myWorkRepository),
      ]) {
        final result = await fixture.clearReceipt(receiptId: 'r1');
        expect(result.isComplete, isTrue);
        expect(result.appliedReceiptIds, ['r1']);
        expect(result.operationId, isNotEmpty);
        expect(fixtureRepository.clearOperationIds, [result.operationId]);
      }

      // The legacy UUID path already clears successfully. Require the new
      // override contract as well, so these calls exercise the fixture default.
      expect(buildAttentionCase, isA<_AttentionFactoryWithOpIds>());
    });
  });
}

typedef _AttentionFactoryWithOpIds =
    AttentionCase Function({
      AttentionRepositoryPort? repository,
      OpIdPort opIds,
    });

AttentionCase _buildAttention(
  AttentionRepositoryPort repository,
  OpIdPort opIds,
) {
  const Function factory = buildAttentionCase;
  // Keep the baseline runnable so it exposes the UUID sent by the real case.
  return factory is _AttentionFactoryWithOpIds
      ? factory(repository: repository, opIds: opIds)
      : buildAttentionCase(repository: repository);
}

final class _RecordingAttentionRepository extends StubAttentionRepository {
  final clearOperationIds = <String>[];
  final sweepOperationIds = <String>[];

  @override
  Future<AttentionClearResult> clear({
    required String snapshotToken,
    required String operationId,
  }) {
    clearOperationIds.add(operationId);
    return super.clear(snapshotToken: snapshotToken, operationId: operationId);
  }

  @override
  Future<AttentionDismissAllResult> dismissAll({
    required String operationId,
    int? maxBatches,
    bool includeOutcomes = true,
  }) async {
    sweepOperationIds.add(operationId);
    return AttentionDismissAllResult(
      operationId: operationId,
      status: AttentionOperationStatus.complete,
    );
  }
}
