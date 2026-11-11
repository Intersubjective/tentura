import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/domain/exception/server_exception.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_account_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';

// A FULL read that follows something the store was already told about (a
// reset of the Field's anchors) is not the Field screen's own load: when it
// fails nothing may escape as an uncaught error and the store keeps what it
// holds. The Field screen's own load still reports why it failed (#1110) —
// unless the account or the projection params changed under the read, in
// which case the read is no longer anyone's load and its failure is dropped.

ConstellationAnchorRevision _revision(int value) =>
    ConstellationAnchorRevision(BigInt.from(value));

const _serverError = ServerStatusException(500);

ConstellationField _field({required String postId, int anchorRevision = 1}) =>
    ConstellationField(
      loadedAt: DateTime.utc(2026, 10, 7),
      context: '',
      posts: [
        ConstellationPost(
          id: postId,
          authorId: 'ego',
          rootExcerpt: '',
          lastActivityAt: DateTime.utc(2026, 10, 7),
        ),
      ],
      anchorProjection: ConstellationAnchorProjection(
        revision: _revision(anchorRevision),
        anchors: const [],
        pinnedPeers: const [],
        pinnedRequests: const [],
        supportPeers: const [],
        supportEdges: const [],
        serverFilteredBeaconIds: const [],
        serverFilteredBeaconCount: 0,
      ),
    );

final class _ScriptedRepository implements ConstellationRepositoryPort {
  _ScriptedRepository(this._respond);

  final Future<ConstellationField> Function(int index) _respond;
  int fetches = 0;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) => _respond(fetches++);
}

final class _AccountPort implements ConstellationAccountPort {
  _AccountPort(this.currentAccountChanges);

  @override
  final Stream<String> currentAccountChanges;
}

void main() {
  late BehaviorSubject<String> account;
  late FakeClockPort clock;
  late FakeWakeUpPort wakeUp;
  late ({RealtimeSyncCase case_, TestRealtimeSyncPort port}) sync;
  late _ScriptedRepository repository;
  late ConstellationFieldStoreCase store;
  late List<ConstellationFieldStoreState> emitted;

  Future<void> settle([int rounds = 20]) async {
    for (var i = 0; i < rounds; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> advance(Duration by) async {
    var left = by;
    while (left > Duration.zero) {
      final step = left > const Duration(seconds: 1)
          ? const Duration(seconds: 1)
          : left;
      clock.advance(step);
      wakeUp.elapse(step);
      await settle(10);
      left -= step;
    }
  }

  Future<void> build(
    Future<ConstellationField> Function(int index) respond,
  ) async {
    account = BehaviorSubject<String>.seeded('account-a');
    clock = FakeClockPort(DateTime.utc(2026, 10, 7));
    wakeUp = FakeWakeUpPort();
    final realtime = buildTestRealtimeSync();
    sync = (case_: realtime.case_, port: realtime.port);
    repository = _ScriptedRepository(respond);
    store = ConstellationFieldStoreCase(
      repository,
      _AccountPort(account.stream),
      clock,
      wakeUp,
      realtime.case_,
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationFieldStoreFollowUpReadFailureTest'),
    )..lease();
    emitted = [];
    store.changes.listen(emitted.add);
    await advance(const Duration(milliseconds: 100));
    emitted.clear();
  }

  tearDown(() async {
    await account.close();
    await sync.port.dispose();
  });

  group('constellation store FULL read that follows a reset', () {
    test('a failing follow-up read raises no uncaught error and the store '
        'keeps the reset projection', () async {
      await build(
        (index) => index == 0
            ? Future.value(_field(postId: 'p1'))
            : Future<ConstellationField>.error(_serverError),
      );
      await store.requestRefresh(ConstellationRefreshReason.load);
      expect(store.current.field?.posts.single.id, 'p1');

      final uncaught = <Object>[];
      final done = Completer<void>();
      unawaited(
        runZonedGuarded(
          () async {
            store.applyReset(_revision(5));
            await advance(const Duration(seconds: 3));
            done.complete();
          },
          (error, _) => uncaught.add(error),
        ),
      );
      await done.future;
      await settle();

      expect(repository.fetches, 2, reason: 'the follow-up FULL was started');
      expect(uncaught, isEmpty);
      final projection = store.current.field?.resolvedAnchorProjection;
      expect(projection?.anchors, isEmpty);
      expect(projection?.pinnedPeers, isEmpty);
      expect(projection?.pinnedRequests, isEmpty);
      expect(store.current.coveredRevision, _revision(5));
      expect(store.current.field?.posts.single.id, 'p1');
    });
  });

  group('constellation store failed FULL load', () {
    test("the Field screen's own load still throws the read error", () async {
      await build((_) => Future<ConstellationField>.error(_serverError));

      await expectLater(
        store.requestRefresh(ConstellationRefreshReason.load),
        throwsA(isA<ServerStatusException>()),
      );
    });

    test('a load superseded by an account change completes normally and '
        'emits nothing for the failed read', () async {
      final gate = Completer<ConstellationField>();
      await build((_) => gate.future);
      Object? outcome = 'pending';
      unawaited(
        store
            .requestRefresh(ConstellationRefreshReason.load)
            .then((_) => outcome = null, onError: (Object e) => outcome = e),
      );
      await settle();
      expect(repository.fetches, 1);

      account.add('account-b');
      await settle();
      final emissionsBefore = emitted.length;
      gate.completeError(_serverError);
      await settle();

      expect(outcome, isNull, reason: 'requestRefresh completed, no error');
      expect(emitted.length, emissionsBefore);
    });

    test('a load superseded by a params change completes normally and '
        'emits nothing for the failed read', () async {
      final gate = Completer<ConstellationField>();
      await build((_) => gate.future);
      Object? outcome = 'pending';
      unawaited(
        store
            .requestRefresh(ConstellationRefreshReason.load)
            .then((_) => outcome = null, onError: (Object e) => outcome = e),
      );
      await settle();
      expect(repository.fetches, 1);

      store.setProjectionParams(
        const ConstellationProjectionParams(context: 'other'),
      );
      await settle();
      final emissionsBefore = emitted.length;
      gate.completeError(_serverError);
      await settle();

      expect(outcome, isNull, reason: 'requestRefresh completed, no error');
      expect(emitted.length, emissionsBefore);
    });
  });
}
