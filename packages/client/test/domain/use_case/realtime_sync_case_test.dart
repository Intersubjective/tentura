import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_watch.dart';
import 'package:tentura/domain/port/realtime_sync_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';

void main() {
  group('RealtimeSyncCase watches', () {
    test(
      're-registers opaque grant and requests fresh snapshot on reconnect',
      () {
        fakeAsync((async) {
          final port = _FakeRealtimeSyncPort();
          final now = DateTime.utc(2026, 7, 14, 12);
          final case_ = RealtimeSyncCase.forTesting(port, now: () => now);
          final refreshes = <RealtimeWatchScope>[];
          final sub = case_.watchRefreshRequests.listen(refreshes.add);
          final grant = _grant(now: now);

          port.emitStatus(_authenticated(epoch: 1));
          async.flushMicrotasks();
          case_.replaceWatch(grant);
          port.emitStatus(_authenticated(epoch: 2));
          async.flushMicrotasks();

          expect(port.replaced, [grant, grant]);
          expect(refreshes, [RealtimeWatchScope.graph]);

          unawaited(sub.cancel());
          unawaited(case_.dispose());
          unawaited(port.dispose());
        });
      },
    );

    test('requests projection refresh before a short-lived grant expires', () {
      fakeAsync((async) {
        final port = _FakeRealtimeSyncPort();
        var now = DateTime.utc(2026, 7, 14, 12);
        final case_ = RealtimeSyncCase.forTesting(port, now: () => now);
        final refreshes = <RealtimeWatchScope>[];
        final sub = case_.watchRefreshRequests.listen(refreshes.add);
        case_.replaceWatch(
          _grant(now: now, ttl: const Duration(seconds: 30)),
        );

        now = now.add(const Duration(seconds: 19));
        async.elapse(const Duration(seconds: 19));
        expect(refreshes, isEmpty);

        now = now.add(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        expect(refreshes, [RealtimeWatchScope.graph]);

        unawaited(sub.cancel());
        unawaited(case_.dispose());
        unawaited(port.dispose());
      });
    });

    test('replacement cancels prior renewal and removal is scope bounded', () {
      fakeAsync((async) {
        final port = _FakeRealtimeSyncPort();
        var now = DateTime.utc(2026, 7, 14, 12);
        final case_ = RealtimeSyncCase.forTesting(port, now: () => now);
        final refreshes = <RealtimeWatchScope>[];
        final sub = case_.watchRefreshRequests.listen(refreshes.add);
        case_
          ..replaceWatch(
            _grant(now: now, ttl: const Duration(seconds: 30)),
          )
          ..replaceWatch(
            _grant(
              now: now,
              ttl: const Duration(minutes: 3),
              token: 'replacement',
            ),
          );

        now = now.add(const Duration(seconds: 30));
        async.elapse(const Duration(seconds: 30));
        expect(refreshes, isEmpty);

        case_.removeWatch(RealtimeWatchScope.graph);
        expect(port.removed, [RealtimeWatchScope.graph]);

        unawaited(sub.cancel());
        unawaited(case_.dispose());
        unawaited(port.dispose());
      });
    });

    test('account switch discards grants from the prior account', () {
      fakeAsync((async) {
        final port = _FakeRealtimeSyncPort();
        final now = DateTime.utc(2026, 7, 14, 12);
        final case_ = RealtimeSyncCase.forTesting(port, now: () => now);
        port.emitStatus(_authenticated(epoch: 1));
        async.flushMicrotasks();
        case_.replaceWatch(_grant(now: now));

        port
          ..emitStatus(
            const RealtimeConnectionStatus(
              accountId: 'account-b',
              connectionEpoch: 2,
              phase: RealtimeConnectionPhase.connecting,
            ),
          )
          ..emitStatus(
            const RealtimeConnectionStatus(
              accountId: 'account-b',
              connectionEpoch: 2,
              phase: RealtimeConnectionPhase.authenticated,
            ),
          );
        async.flushMicrotasks();

        expect(port.replaced, hasLength(1));

        unawaited(case_.dispose());
        unawaited(port.dispose());
      });
    });
  });
}

RealtimeConnectionStatus _authenticated({required int epoch}) =>
    RealtimeConnectionStatus(
      accountId: 'account-a',
      connectionEpoch: epoch,
      phase: RealtimeConnectionPhase.authenticated,
    );

RealtimeWatchGrant _grant({
  required DateTime now,
  Duration ttl = const Duration(minutes: 2),
  String token = 'opaque',
}) => RealtimeWatchGrant(
  token: token,
  scope: RealtimeWatchScope.graph,
  authorizedSubjectIds: const {'user-a'},
  expiresAt: now.add(ttl),
);

final class _FakeRealtimeSyncPort implements RealtimeSyncPort {
  final _statuses = StreamController<RealtimeConnectionStatus>.broadcast();
  final replaced = <RealtimeWatchGrant>[];
  final removed = <RealtimeWatchScope>[];

  @override
  Stream<RealtimeCatchUp> get catchUps => const Stream.empty();

  @override
  Stream<RealtimeConnectionStatus> get connectionStatuses => _statuses.stream;

  @override
  Stream<RealtimeEntityChange> get entityChanges => const Stream.empty();

  void emitStatus(RealtimeConnectionStatus status) => _statuses.add(status);

  @override
  void removeWatch(RealtimeWatchScope scope) => removed.add(scope);

  @override
  void replaceWatch(RealtimeWatchGrant grant) => replaced.add(grant);

  @override
  void requestCatchUp(RealtimeCatchUpReason reason) {}

  Future<void> dispose() => _statuses.close();
}
