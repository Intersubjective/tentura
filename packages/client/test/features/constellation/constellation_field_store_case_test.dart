import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
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

/// Contract exercised here (the read side of the constellation store):
///
/// * `ConstellationFieldStoreCase(repository, account, clock, wakeUp,
///   realtimeSyncCase, env:, logger:)` follows `ConstellationAccountPort`
///   independently of screen leases.
/// * `lease()` returns a `StoreLease` with `setVisible(bool)` and `dispose()`;
///   the store's own `setVisible(bool)` is the browser-tab visibility.
/// * `requestRefresh(ConstellationRefreshReason)` and
///   `setMembershipFilters(filters)` / `setProjectionParams(params)` schedule
///   the single-flight FULL refresh.
/// * `current` / `changes` expose a `ConstellationFieldStoreState` with
///   `field`, `coveredRevision` and `generation`.

/// Global (non-urgent) hints refresh a visible field once per D8 staleness
/// window (5 min) plus a small per-account jitter.
const _stalenessWindow = Duration(minutes: 5);

ConstellationAnchorRevision _revision(int value) =>
    ConstellationAnchorRevision(BigInt.from(value));

ConstellationField _field({
  required String postId,
  int anchorRevision = 1,
}) => ConstellationField(
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

typedef _FetchCall = ({
  ConstellationProjection projection,
  ConstellationFieldMembershipFilters filters,
});

final class _ScriptedRepository implements ConstellationRepositoryPort {
  _ScriptedRepository(this._respond);

  final Future<ConstellationField> Function(int index, _FetchCall call)
  _respond;

  final calls = <_FetchCall>[];
  var _inFlight = 0;
  int maxInFlight = 0;

  int count(ConstellationProjection projection) =>
      calls.where((c) => c.projection == projection).length;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    final call = (projection: projection, filters: membershipFilters);
    final index = calls.length;
    calls.add(call);
    _inFlight++;
    if (_inFlight > maxInFlight) {
      maxInFlight = _inFlight;
    }
    try {
      return await _respond(index, call);
    } finally {
      _inFlight--;
    }
  }
}

void main() {
  late BehaviorSubject<String> account;
  late FakeClockPort clock;
  late FakeWakeUpPort wakeUp;
  late ({RealtimeSyncCase case_, TestRealtimeSyncPort port}) sync;
  late _ScriptedRepository repository;
  late ConstellationFieldStoreCase store;
  late List<ConstellationFieldStoreState> emitted;

  /// Advances the fake clock and wake-ups in 1 s steps, letting async work
  /// settle between steps so follow-up timers are scheduled in order.
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
    Future<ConstellationField> Function(int index, _FetchCall call) respond, {
    String accountId = 'account-a',
  }) async {
    account = BehaviorSubject<String>.seeded(accountId);
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
      logger: Logger('ConstellationFieldStoreCaseTest'),
    );
    emitted = [];
    store.changes.listen(emitted.add);
    await advance(const Duration(milliseconds: 100));
    emitted.clear();
  }

  Future<void> load() async {
    unawaited(store.requestRefresh(ConstellationRefreshReason.load));
    await advance(const Duration(seconds: 3));
  }

  void hint(RealtimeEntityKind kind, String aggregateId) =>
      sync.port.emitChange(
        RealtimeEntityChange(
          kind: kind,
          aggregateId: aggregateId,
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );

  tearDown(() async {
    await account.close();
    await sync.port.dispose();
  });

  group('account lifetime', () {
    test('logout with zero leases clears the held field state', () async {
      await build((_, _) async => _field(postId: 'p1'));
      final lease = store.lease();
      await load();
      expect(store.current.field?.posts.single.id, 'p1');
      final generationBefore = store.current.generation;

      lease.dispose();
      account.add('');
      await advance(const Duration(milliseconds: 100));

      expect(store.current.field, isNull);
      expect(store.current.coveredRevision, ConstellationAnchorRevision.zero);
      expect(store.current.generation, greaterThan(generationBefore));
    });

    test('logout cancels a scheduled refresh so nothing is fetched', () async {
      await build((_, _) async => _field(postId: 'p1'));
      store.lease();
      await load();
      final fetchesBefore = repository.calls.length;

      hint(RealtimeEntityKind.beacon, 'b1');
      account.add('');
      await advance(const Duration(minutes: 1));
      hint(RealtimeEntityKind.beacon, 'b2');
      sync.port.emitCatchUp();
      await advance(const Duration(minutes: 1));

      expect(repository.calls.length, fetchesBefore);
    });

    test('a result in flight at logout is dropped, not adopted', () async {
      final gate = Completer<void>();
      await build((_, _) async {
        await gate.future;
        return _field(postId: 'old-account');
      });
      store.lease();
      unawaited(store.requestRefresh(ConstellationRefreshReason.load));
      await advance(const Duration(seconds: 1));
      expect(repository.calls, hasLength(1));

      account.add('');
      await advance(const Duration(milliseconds: 100));
      gate.complete();
      await advance(const Duration(seconds: 3));

      expect(store.current.field, isNull);
    });

    test('generation changes only on account replacement or logout', () async {
      await build((_, _) async => _field(postId: 'p1'));
      final initial = store.current.generation;

      store.lease()
        ..setVisible(false)
        ..setVisible(true)
        ..dispose();
      store.lease().dispose();
      account.add('account-a');
      await advance(const Duration(milliseconds: 100));
      expect(store.current.generation, initial);

      account.add('account-b');
      await advance(const Duration(milliseconds: 100));
      expect(store.current.generation, initial + 1);
    });
  });

  group('visibility', () {
    test('a hidden lease fetches nothing, ANCHORS included', () async {
      await build((_, _) async => _field(postId: 'p1'));
      final lease = store.lease();
      await load();
      final fetchesBefore = repository.calls.length;

      lease.setVisible(false);
      hint(RealtimeEntityKind.constellationAnchor, 'account-a');
      hint(RealtimeEntityKind.beacon, 'b1');
      hint(RealtimeEntityKind.roomMessage, 'b1');
      sync.port.emitCatchUp();
      await advance(const Duration(minutes: 1));

      expect(repository.calls.length, fetchesBefore);
      expect(repository.count(ConstellationProjection.anchors), 0);
    });

    test('showing a stale hidden lease refetches FULL once', () async {
      await build((_, _) async => _field(postId: 'p1'));
      final lease = store.lease();
      await load();
      lease.setVisible(false);
      for (var i = 0; i < 5; i++) {
        hint(RealtimeEntityKind.beacon, 'b$i');
        await advance(const Duration(seconds: 1));
      }
      final fullBefore = repository.count(ConstellationProjection.full);

      lease.setVisible(true);
      await advance(const Duration(seconds: 5));

      expect(
        repository.count(ConstellationProjection.full),
        fullBefore + 1,
      );
    });

    test('one visible lease keeps the store fetching', () async {
      await build((_, _) async => _field(postId: 'p1'));
      final hidden = store.lease();
      store.lease();
      await load();
      final fetchesBefore = repository.calls.length;

      hidden.setVisible(false);
      hint(RealtimeEntityKind.beacon, 'b1');
      await advance(const Duration(seconds: 5));

      expect(repository.calls.length, greaterThan(fetchesBefore));
    });

    test('all leases hidden, or the browser hidden, fetches nothing', () async {
      await build((_, _) async => _field(postId: 'p1'));
      final first = store.lease();
      final second = store.lease();
      await load();
      var fetches = repository.calls.length;

      first.setVisible(false);
      second.setVisible(false);
      hint(RealtimeEntityKind.beacon, 'b1');
      await advance(const Duration(seconds: 30));
      expect(repository.calls.length, fetches);

      second.setVisible(true);
      await advance(const Duration(seconds: 5));
      fetches = repository.calls.length;
      expect(fetches, greaterThan(0));

      store.setVisible(false);
      hint(RealtimeEntityKind.beacon, 'b2');
      hint(RealtimeEntityKind.constellationAnchor, 'account-a');
      await advance(const Duration(seconds: 30));
      expect(repository.calls.length, fetches);
    });

    test('disposing the only visible lease stops fetching', () async {
      await build((_, _) async => _field(postId: 'p1'));
      final hidden = store.lease();
      final visible = store.lease();
      await load();
      final fetchesBefore = repository.calls.length;

      hidden.setVisible(false);
      visible.dispose();
      hint(RealtimeEntityKind.beacon, 'b1');
      await advance(const Duration(seconds: 30));

      expect(repository.calls.length, fetchesBefore);
    });
  });

  group('refresh scheduling', () {
    test('catch-up issues exactly one FULL and no ANCHORS read', () async {
      await build((_, _) async => _field(postId: 'p1'));
      store.lease();
      await load();
      final fullBefore = repository.count(ConstellationProjection.full);
      final anchorsBefore = repository.count(ConstellationProjection.anchors);

      sync.port.emitCatchUp();
      await advance(const Duration(seconds: 10));

      expect(
        repository.count(ConstellationProjection.full),
        fullBefore + 1,
      );
      expect(
        repository.count(ConstellationProjection.anchors),
        anchorsBefore,
      );
    });

    test('catch-up issues one FULL however many leases are active', () async {
      await build((_, _) async => _field(postId: 'p1'));
      store
        ..lease()
        ..lease()
        ..lease();
      await load();
      final fullBefore = repository.count(ConstellationProjection.full);

      sync.port.emitCatchUp();
      await advance(const Duration(seconds: 10));

      expect(
        repository.count(ConstellationProjection.full),
        fullBefore + 1,
      );
    });

    test('concurrent triggers share one in-flight fetch', () async {
      final gate = Completer<void>();
      await build((_, _) async {
        await gate.future;
        return _field(postId: 'p1');
      });
      store.lease();

      unawaited(store.requestRefresh(ConstellationRefreshReason.load));
      unawaited(store.requestRefresh(ConstellationRefreshReason.load));
      hint(RealtimeEntityKind.beacon, 'b1');
      sync.port.emitCatchUp();
      await advance(const Duration(seconds: 3));
      gate.complete();
      await advance(const Duration(seconds: 10));

      expect(repository.maxInFlight, 1);
    });

    test('a steady event stream refreshes at most every 2 s', () async {
      await build((_, _) async => _field(postId: 'p1'));
      store.lease();
      await load();
      final fetchesBefore = repository.calls.length;

      for (var i = 0; i < 100; i++) {
        hint(RealtimeEntityKind.beacon, 'b1');
        await advance(const Duration(milliseconds: 100));
      }
      await advance(const Duration(seconds: 3));

      final extra = repository.calls.length - fetchesBefore;
      expect(extra, inInclusiveRange(4, 7));
    });

    test(
      'a global hint waits for the staleness window before its FULL',
      () async {
        await build((_, _) async => _field(postId: 'p1'));
        store.lease();
        await load();
        final fetchesBefore = repository.calls.length;

        hint(RealtimeEntityKind.roomMessage, 'elsewhere');
        await advance(_stalenessWindow - const Duration(seconds: 1));
        expect(repository.calls, hasLength(fetchesBefore));

        await advance(_stalenessWindow);
        expect(repository.calls, hasLength(fetchesBefore + 1));
        expect(repository.calls.last.projection, ConstellationProjection.full);
      },
    );

    test('an urgent hint is not held back by a pending global hint', () async {
      await build((_, _) async => _field(postId: 'p1'));
      store.lease();
      await load();
      final fetchesBefore = repository.calls.length;

      hint(RealtimeEntityKind.roomMessage, 'elsewhere');
      await advance(const Duration(seconds: 30));
      expect(repository.calls, hasLength(fetchesBefore));

      hint(RealtimeEntityKind.beacon, 'p1');
      await advance(const Duration(seconds: 5));

      expect(repository.calls, hasLength(fetchesBefore + 1));
    });
  });

  group('projection params binding', () {
    test('params compare context and normalized filter values', () {
      const defaults = ConstellationProjectionParams();
      final filters = defaults.membershipFilters;
      final equivalent = ConstellationProjectionParams(
        membershipFilters: ConstellationFieldMembershipFilters(
          showClosed: filters.showClosed,
          participatedOnly: filters.participatedOnly,
        ),
      );

      expect(equivalent, defaults);
      expect(equivalent.hashCode, defaults.hashCode);
      expect(defaults.copyWith(context: 'other'), isNot(defaults));
      expect(
        defaults.copyWith(
          membershipFilters: const ConstellationFieldMembershipFilters(
            participatedOnly: true,
          ),
        ),
        isNot(defaults),
      );
    });

    test('equivalent params do not refresh or emit', () async {
      await build((_, _) async => _field(postId: 'current'));
      store.lease();
      await load();
      final fetchesBefore = repository.calls.length;
      final emitsBefore = emitted.length;
      final params = store.projectionParams;

      store.setProjectionParams(
        ConstellationProjectionParams(
          context: params.context,
          membershipFilters: ConstellationFieldMembershipFilters(
            showClosed: params.membershipFilters.showClosed,
            participatedOnly: params.membershipFilters.participatedOnly,
          ),
        ),
      );
      await advance(const Duration(seconds: 3));

      expect(repository.calls.length, fetchesBefore);
      expect(emitted.length, emitsBefore);
    });

    void rebind(String binding) {
      if (binding == 'filters') {
        store
          ..setMembershipFilters(
            const ConstellationFieldMembershipFilters(showClosed: true),
          )
          ..setMembershipFilters(ConstellationFieldMembershipFilters.defaults);
      } else {
        store
          ..setProjectionParams(
            const ConstellationProjectionParams(context: 'other'),
          )
          ..setProjectionParams(const ConstellationProjectionParams());
      }
    }

    for (final binding in ['filters', 'context']) {
      test('FULL ignores an earlier $binding binding after A-B-A', () async {
        final oldGate = Completer<void>();
        final currentGate = Completer<void>();
        await build((index, _) async {
          if (index == 0) {
            await oldGate.future;
            return _field(postId: 'obsolete', anchorRevision: 9);
          }
          await currentGate.future;
          return _field(postId: 'current', anchorRevision: 2);
        });
        store.lease();
        unawaited(store.requestRefresh(ConstellationRefreshReason.load));
        await advance(const Duration(seconds: 1));
        final accountGeneration = store.current.generation;

        rebind(binding);
        await advance(const Duration(seconds: 1));
        final emitsBefore = emitted.length;
        oldGate.complete();
        await advance(const Duration(seconds: 1));

        expect(emitted.length, emitsBefore);
        expect(store.current.field, isNull);
        expect(store.current.generation, accountGeneration);
        expect(repository.count(ConstellationProjection.full), 2);
        currentGate.complete();
        await advance(const Duration(seconds: 3));
        expect(store.current.field?.posts.single.id, 'current');
        expect(store.current.coveredRevision, _revision(2));
      });

      test('ANCHORS ignores an earlier $binding binding after A-B-A', () async {
        final oldGate = Completer<void>();
        await build((_, call) async {
          if (call.projection == ConstellationProjection.anchors) {
            await oldGate.future;
            return _field(postId: 'obsolete', anchorRevision: 9);
          }
          return _field(postId: 'current', anchorRevision: 2);
        });
        store.lease();
        await load();
        hint(RealtimeEntityKind.constellationAnchor, 'account-a');
        await advance(const Duration(seconds: 1));
        expect(repository.count(ConstellationProjection.anchors), 1);

        rebind(binding);
        await advance(const Duration(seconds: 3));
        final fieldBefore = store.current.field;
        final emitsBefore = emitted.length;
        oldGate.complete();
        await advance(const Duration(seconds: 3));

        expect(emitted.length, emitsBefore);
        expect(store.current.field, same(fieldBefore));
        expect(store.current.coveredRevision, _revision(2));
      });
    }

    test('a result computed for obsolete filters is ignored', () async {
      final gate = Completer<void>();
      await build((_, call) async {
        await gate.future;
        return _field(
          postId: call.filters.showClosed ? 'closed-view' : 'open-view',
        );
      });
      store.lease();
      unawaited(store.requestRefresh(ConstellationRefreshReason.load));
      await advance(const Duration(seconds: 1));
      expect(repository.calls.first.filters.showClosed, isFalse);

      store.setMembershipFilters(
        const ConstellationFieldMembershipFilters(showClosed: true),
      );
      await advance(const Duration(seconds: 1));
      gate.complete();
      await advance(const Duration(seconds: 10));

      expect(store.current.field?.posts.single.id, 'closed-view');
      expect(
        emitted.expand((s) => s.field?.posts ?? const <ConstellationPost>[]),
        everyElement(
          predicate<ConstellationPost>((p) => p.id != 'open-view'),
        ),
      );
    });

    test('a late obsolete result never replaces the current one', () async {
      final oldGate = Completer<void>();
      await build((_, call) async {
        if (!call.filters.showClosed) {
          await oldGate.future;
          return _field(postId: 'open-view', anchorRevision: 9);
        }
        return _field(postId: 'closed-view', anchorRevision: 2);
      });
      store.lease();
      unawaited(store.requestRefresh(ConstellationRefreshReason.load));
      await advance(const Duration(seconds: 1));

      store.setMembershipFilters(
        const ConstellationFieldMembershipFilters(showClosed: true),
      );
      await advance(const Duration(seconds: 5));
      oldGate.complete();
      await advance(const Duration(seconds: 5));

      expect(store.current.field?.posts.single.id, 'closed-view');
      expect(store.current.coveredRevision, _revision(2));
    });

    test('an ignored obsolete result causes no emit', () async {
      final gate = Completer<void>();
      await build((_, call) async {
        if (!call.filters.showClosed) {
          await gate.future;
        }
        return _field(
          postId: call.filters.showClosed ? 'closed-view' : 'open-view',
        );
      });
      store.lease();
      unawaited(store.requestRefresh(ConstellationRefreshReason.load));
      await advance(const Duration(seconds: 1));
      store.setMembershipFilters(
        const ConstellationFieldMembershipFilters(showClosed: true),
      );
      await advance(const Duration(seconds: 5));
      final emitsBefore = emitted.length;

      gate.complete();
      await advance(const Duration(seconds: 5));

      expect(emitted.length, emitsBefore);
    });
  });

  group('applied changes', () {
    test('FULL freshness follows read order, not anchor revision', () async {
      await build((index, _) async {
        return index == 0
            ? _field(postId: 'first-read', anchorRevision: 5)
            : _field(postId: 'second-read', anchorRevision: 3);
      });
      store.lease();
      await load();
      expect(store.current.field?.posts.single.id, 'first-read');
      expect(store.current.coveredRevision, _revision(5));

      await load();

      expect(store.current.field?.posts.single.id, 'second-read');
      expect(store.current.coveredRevision, _revision(5));
    });

    test('one applied FULL produces exactly one emit', () async {
      await build((_, _) async => _field(postId: 'p1'));
      store.lease();

      await load();

      expect(emitted, hasLength(1));
      expect(emitted.single.field?.posts.single.id, 'p1');
    });
  });
}

final class _AccountPort implements ConstellationAccountPort {
  _AccountPort(this.currentAccountChanges);

  @override
  final Stream<String> currentAccountChanges;
}
