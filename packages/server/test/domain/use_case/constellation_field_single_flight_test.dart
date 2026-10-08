import 'dart:async';
import 'dart:isolate';

import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/use_case/constellation_field_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/gated_constellation_field_repository.dart';

void main() {
  group('FULL snapshot single-flight', () {
    test(
      'same viewer and equal parameters share one database computation',
      () async {
        final repository = GatedConstellationFieldRepository();
        final fieldCase = _fieldCase(repository);
        final leader = _readFull(fieldCase);
        await repository.firstReadStarted.future;
        // A separate filters instance must still identify the same flight.
        final follower = _readFull(fieldCase);
        final reads = Future.wait([leader, follower]);
        await Future<void>.delayed(Duration.zero);
        repository.completePendingReads();
        final snapshots = await reads;

        expect(repository.readSnapshotCalls, 1);
        expect(snapshots, hasLength(2));
        expect(snapshots[1], same(snapshots[0]));
      },
    );

    test(
      'load and explicit FULL read share the same in-flight computation',
      () async {
        final repository = GatedConstellationFieldRepository();
        final fieldCase = _fieldCase(repository);
        final leader = fieldCase.load(viewerId: 'Uviewer', context: '');
        await repository.firstReadStarted.future;
        final follower = _readFull(fieldCase);
        final reads = Future.wait([leader, follower]);
        await Future<void>.delayed(Duration.zero);
        repository.completePendingReads();
        final snapshots = await reads;

        expect(repository.readSnapshotCalls, 1);
        expect(snapshots[1], same(snapshots[0]));
      },
    );

    test('followers join before repository admission', () async {
      final repository = GatedConstellationFieldRepository(
        maxConcurrentReads: 1,
      );
      final fieldCase = _fieldCase(repository);
      final leader = _readFull(fieldCase);
      await repository.firstReadStarted.future;
      final follower = _readFull(fieldCase);
      // Attach the matcher before yielding so admission rejection is observed.
      final completed = expectLater(
        Future.wait([leader, follower]),
        completion(hasLength(2)),
      );
      await Future<void>.delayed(Duration.zero);
      repository.completePendingReads();
      await completed;

      expect(repository.readSnapshotCalls, 1);
      expect(repository.activeReads, 0);
    });

    final distinctKeys =
        <
          String,
          Future<ConstellationFieldSnapshot> Function(ConstellationFieldCase)
        >{
          'different viewers': (fieldCase) =>
              _readFull(fieldCase, viewerId: 'Uother'),
          'different contexts': (fieldCase) =>
              _readFull(fieldCase, context: 'other-context'),
          'different showClosed filters': (fieldCase) => _readFull(
            fieldCase,
            filters: const ConstellationFieldMembershipFilters(
              showClosed: true,
            ),
          ),
          'different participatedOnly filters': (fieldCase) => _readFull(
            fieldCase,
            filters: const ConstellationFieldMembershipFilters(
              participatedOnly: true,
            ),
          ),
          'ANCHORS and FULL projections': (fieldCase) => fieldCase.readSnapshot(
            viewerId: 'Uviewer',
            context: '',
            params: (
            filters: ConstellationFieldMembershipFilters.defaults,
              projection: ConstellationProjection.anchors,
            ),
          ),
        };
    for (final entry in distinctKeys.entries) {
      test('${entry.key} have independent flights', () async {
        final repository = GatedConstellationFieldRepository();
        final fieldCase = _fieldCase(repository);
        final leader = _readFull(fieldCase);
        await repository.firstReadStarted.future;
        final reads = Future.wait([
          leader,
          _readFull(fieldCase),
          entry.value(fieldCase),
        ]);
        await Future<void>.delayed(Duration.zero);
        repository.completePendingReads();
        final snapshots = await reads;

        expect(repository.readSnapshotCalls, 2);
        expect(snapshots[1], same(snapshots[0]));
        expect(snapshots[2], isNot(same(snapshots[0])));
      });
    }

    test(
      'completed FULL flights do not cache snapshots for later reads',
      () async {
        final repository = GatedConstellationFieldRepository();
        final fieldCase = _fieldCase(repository);
        final leader = _readFull(fieldCase);
        await repository.firstReadStarted.future;
        final overlapping = Future.wait([leader, _readFull(fieldCase)]);
        await Future<void>.delayed(Duration.zero);
        repository.completePendingReads();
        final firstSnapshots = await overlapping;

        repository.visibleGeneration++;
        final nextRead = _readFull(fieldCase);
        await Future<void>.delayed(Duration.zero);
        repository.completePendingReads();
        final nextSnapshot = await nextRead;

        expect(nextSnapshot.peers.single.id, 'generation-1');
        expect(nextSnapshot, isNot(same(firstSnapshots.first)));
        expect(repository.readSnapshotCalls, 2);
      },
    );

    test(
      'two isolates perform at most two computations for the same FULL key',
      () async {
        final ports = [ReceivePort(), ReceivePort()];
        final messages = ports.map(StreamIterator<dynamic>.new).toList();
        final isolates = <Isolate>[];
        addTearDown(() async {
          for (final isolate in isolates) {
            isolate.kill(priority: Isolate.immediate);
          }
          for (final iterator in messages) {
            await iterator.cancel();
          }
          for (final port in ports) {
            port.close();
          }
        });
        for (var i = 0; i < ports.length; i++) {
          isolates.add(
            await Isolate.spawn(
              _readOnIsolate,
              ports[i].sendPort,
              debugName: 'full-worker-$i',
              onError: ports[i].sendPort,
            ),
          );
        }

        await Future.wait(messages.map((iterator) => iterator.moveNext()));
        final started = messages
            .map((iterator) => iterator.current as _StartedRead)
            .toList();
        // Each worker reports only after all four calls have returned their
        // still-pending read futures. Neither worker may finish a computation
        // until both workers have reached this caller barrier.
        try {
          for (final worker in started) {
            expect(worker.joinedCalls, 4);
            expect(worker.completedCalls, 0);
            expect(worker.activeComputations, greaterThanOrEqualTo(1));
            expect(worker.key, (
              viewerId: 'Uviewer',
              context: '',
              showClosed: false,
              participatedOnly: false,
              projection: 'FULL',
            ));
          }
        } finally {
          for (final worker in started) {
            worker.release.send(null);
          }
        }
        await Future.wait(messages.map((iterator) => iterator.moveNext()));
        final completed = messages
            .map((iterator) => iterator.current as _CompletedRead)
            .toList();

        expect(
          started.map((worker) => worker.isolateName).toSet(),
          hasLength(2),
        );
        final computations = started.fold<int>(
          0,
          (sum, worker) => sum + worker.calls,
        );
        expect(computations, 2);
        for (var i = 0; i < completed.length; i++) {
          expect(started[i].calls, 1);
          final worker = completed[i];
          expect(worker.snapshots, 4);
          expect(worker.sharedSnapshot, isTrue);
          expect(worker.calls, 1);
        }
      },
    );
  });
}

ConstellationFieldCase _fieldCase(
  GatedConstellationFieldRepository repository,
) => ConstellationFieldCase(
  repository,
  env: Env.test(),
  logger: Logger('ConstellationFieldSingleFlightTest'),
);

Future<ConstellationFieldSnapshot> _readFull(
  ConstellationFieldCase fieldCase, {
  String viewerId = 'Uviewer',
  String context = '',
  ConstellationFieldMembershipFilters? filters,
}) => fieldCase.readSnapshot(
  viewerId: viewerId,
  context: context,
  params: (
      filters: filters ?? ConstellationFieldMembershipFilters.defaults,
    projection: ConstellationProjection.full,
  ),
);

typedef _StartedRead = ({
  SendPort release,
  String isolateName,
  int calls,
  int joinedCalls,
  int completedCalls,
  int activeComputations,
  _FullReadKey key,
});
typedef _FullReadKey = ({
  String viewerId,
  String context,
  bool showClosed,
  bool participatedOnly,
  String projection,
});
typedef _CompletedRead = ({int calls, int snapshots, bool sharedSnapshot});

Future<void> _readOnIsolate(SendPort results) async {
  final release = ReceivePort();
  try {
    final repository = GatedConstellationFieldRepository();
    final fieldCase = _fieldCase(repository);
    final joined = List.generate(4, (_) => Completer<void>());
    var completedCalls = 0;
    final reads = Future.wait(
      List.generate(4, (i) {
        // Each acknowledgment occurs after readSnapshot has accepted this caller
        // and returned its pending future, not merely after the first DB entry.
        final read = _readFull(fieldCase);
        joined[i].complete();
        return read.whenComplete(() => completedCalls++);
      }),
    );
    await Future.wait(joined.map((caller) => caller.future));
    await repository.firstReadStarted.future;
    final firstRead = repository.reads.first;
    results.send((
      release: release.sendPort,
      isolateName: Isolate.current.debugName!,
      calls: repository.readSnapshotCalls,
      joinedCalls: joined.where((caller) => caller.isCompleted).length,
      completedCalls: completedCalls,
      activeComputations: repository.activeReads,
      key: (
        viewerId: firstRead.viewerId,
        context: firstRead.context,
        showClosed: firstRead.params.filters.showClosed,
        participatedOnly: firstRead.params.filters.participatedOnly,
        projection: firstRead.params.projection.wireValue,
      ),
    ));
    await release.first;
    repository.completePendingReads();
    final snapshots = await reads;
    results.send((
      calls: repository.readSnapshotCalls,
      snapshots: snapshots.length,
      sharedSnapshot: snapshots.every(
        (snapshot) => identical(snapshot, snapshots.first),
      ),
    ));
  } finally {
    release.close();
  }
}
