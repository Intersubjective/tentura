import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_account_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';

import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';

// A FULL refresh that the server turns away with its admission backoff is
// retried by the store once the advertised delay has passed. A loader that
// reads in parallel reports that rejection wrapped in a ParallelWaitError, so
// the store must see through the wrapper.

const _retryAfter = Duration(seconds: 30);

final _loaded = ConstellationField(
  loadedAt: DateTime.utc(2026, 10, 15),
  context: '',
  posts: [
    ConstellationPost(
      id: 'p-after-retry',
      authorId: 'ego',
      rootExcerpt: '',
      lastActivityAt: DateTime.utc(2026, 10, 15),
    ),
  ],
);

Future<Never> _busy(Duration retryAfter) =>
    Future<Never>.error(RemoteApiRetryLaterException(retryAfter));

Future<Never> _parallelBusy(List<Duration> retryAfters) async {
  await [for (final d in retryAfters) _busy(d)].wait;
  throw StateError('unreachable: every future above fails');
}

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

  Future<void> advance(Duration by) async {
    var left = by;
    while (left > Duration.zero) {
      final step = left > const Duration(seconds: 1)
          ? const Duration(seconds: 1)
          : left;
      clock.advance(step);
      wakeUp.elapse(step);
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      left -= step;
    }
  }

  Future<void> build(
    Future<ConstellationField> Function(int index) respond,
  ) async {
    account = BehaviorSubject<String>.seeded('account-a');
    clock = FakeClockPort(DateTime.utc(2026, 10, 15));
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
      logger: Logger('ConstellationFieldStoreRetryLaterTest'),
    )..lease();
    await advance(const Duration(milliseconds: 100));
  }

  tearDown(() async {
    await account.close();
    await sync.port.dispose();
  });

  group('constellation store refresh on server admission backoff', () {
    test(
      'a rejected refresh is retried only after the advertised delay',
      () async {
        await build(
          (index) => index == 0 ? _busy(_retryAfter) : Future.value(_loaded),
        );

        unawaited(store.requestRefresh(ConstellationRefreshReason.load));
        await advance(const Duration(seconds: 10));
        expect(
          repository.fetches,
          1,
          reason: 'no retry before the hint elapses',
        );

        await advance(const Duration(seconds: 30));
        expect(repository.fetches, 2);
        expect(store.current.field?.posts.single.id, 'p-after-retry');
      },
    );

    test('a refresh rejected in a parallel wait with only retry-later causes '
        'is retried after the advertised delay', () async {
      await build(
        (index) => index == 0
            ? _parallelBusy(const [_retryAfter, _retryAfter])
            : Future.value(_loaded),
      );

      unawaited(store.requestRefresh(ConstellationRefreshReason.load));
      await advance(const Duration(seconds: 10));
      expect(repository.fetches, 1, reason: 'no retry before the hints elapse');

      await advance(const Duration(seconds: 30));
      expect(repository.fetches, 2);
      expect(store.current.field?.posts.single.id, 'p-after-retry');
    });
  });
}
