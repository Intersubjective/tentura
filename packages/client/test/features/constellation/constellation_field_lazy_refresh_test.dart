import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';
import 'package:tentura/data/service/remote_api_client/auth_loss_classifier.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
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

/// Global field hints refresh a visible field once per D8 staleness window
/// (5 min) plus a small per-account jitter.
const _lazyWindow = Duration(minutes: 5);

/// Generous bound on the per-account jitter added to [_lazyWindow].
const _jitterAllowance = Duration(seconds: 30);

/// Long enough for a pending global refresh to be due, whatever the jitter.
final _globalStalenessBound = _lazyWindow + _jitterAllowance;

void main() {
  late _RefreshHarness h;

  setUp(() async {
    h = _RefreshHarness();
    addTearDown(h.dispose);
    await h.flush();
  });

  group('lazy global constellation field invalidation', () {
    test(
      'sustained visible hints allow at most one FULL in each lazy window',
      () async {
        await h.load();
        final initialReads = h.repository.calls.length;
        final lastFullAt = h.repository.calls.last.at;

        // Fifty hints in each of three consecutive five-minute windows. Keep
        // checking the count while traffic continues, not only after it stops.
        const hintSpacing = Duration(seconds: 6);
        for (var window = 0; window < 3; window++) {
          final windowStart = h.clock.now();
          final windowEnd = windowStart.add(_lazyWindow);
          for (var hint = 0; hint < 50; hint++) {
            h.fieldHint();
            await h.advance(hintSpacing);
            final readsInWindow = h.repository.calls
                .skip(initialReads)
                .where(
                  (call) =>
                      !call.at.isBefore(windowStart) &&
                      call.at.isBefore(windowEnd),
                );
            expect(
              readsInWindow.length,
              lessThanOrEqualTo(1),
              reason:
                  'Continuous hints must not exceed one FULL in window $window.',
            );
          }
          expect(h.clock.now(), windowEnd);
        }

        expect(
          h.repository.calls.length,
          greaterThan(initialReads),
          reason:
              'A continuously stale visible field must refresh within a window.',
        );
        // Let an invalidation newer than the last dispatched FULL settle too.
        await h.advance(_globalStalenessBound);
        final lazyReads = h.repository.calls.skip(initialReads).toList();
        var previousFullAt = lastFullAt;
        for (final read in lazyReads) {
          expect(
            read.at.difference(previousFullAt),
            greaterThanOrEqualTo(_lazyWindow),
            reason: 'Spacing also holds across adjacent window boundaries.',
          );
          expect(read.projection, ConstellationProjection.full);
          previousFullAt = read.at;
        }
      },
    );

    test(
      'one visible hint dispatches its FULL after the window, not before',
      () async {
        await h.load();
        final initialReads = h.repository.calls.length;
        final hintedAt = h.clock.now();

        h.fieldHint();
        await h.advance(_lazyWindow - const Duration(seconds: 1));
        expect(h.repository.calls, hasLength(initialReads));

        await h.advance(const Duration(seconds: 1) + _jitterAllowance);
        expect(h.repository.calls, hasLength(initialReads + 1));
        final read = h.repository.calls.last;
        expect(read.at.difference(hintedAt), greaterThanOrEqualTo(_lazyWindow));
        expect(read.projection, ConstellationProjection.full);
      },
    );

    test(
      'hidden hints fetch nothing and tab return dispatches one FULL immediately',
      () async {
        await h.load();
        final initialReads = h.repository.calls.length;
        h.store.setVisible(false);
        for (var i = 0; i < 50; i++) {
          h.fieldHint();
        }
        await h.advance(const Duration(minutes: 2));
        expect(h.repository.calls, hasLength(initialReads));

        h.store.setVisible(true);
        // Flush stream delivery without advancing time: return is not debounced.
        await h.flush();
        expect(h.repository.calls, hasLength(initialReads + 1));
        expect(
          h.repository.calls.last.projection,
          ConstellationProjection.full,
        );
        await h.advance(const Duration(minutes: 1));
        expect(h.repository.calls, hasLength(initialReads + 1));
      },
    );

    test(
      'opening a stale constellation dispatches one FULL immediately',
      () async {
        await h.load();
        final initialReads = h.repository.calls.length;
        h.lease!.dispose();
        h.lease = null;
        for (var i = 0; i < 50; i++) {
          h.fieldHint();
        }
        await h.advance(const Duration(minutes: 2));
        expect(h.repository.calls, hasLength(initialReads));

        h.lease = h.store.lease();
        await h.flush();
        expect(h.repository.calls, hasLength(initialReads + 1));
        expect(
          h.repository.calls.last.projection,
          ConstellationProjection.full,
        );
        await h.advance(const Duration(minutes: 1));
        expect(h.repository.calls, hasLength(initialReads + 1));
      },
    );

    test(
      'anchor coverage never suppresses a global field FULL refresh',
      () async {
        h.repository.respond = (_, _) async => _field(anchorRevision: 100);
        await h.load();
        expect(h.store.current.coveredRevision.value, BigInt.from(100));
        final initialReads = h.repository.calls.length;

        // Field freshness is independent of the already covered anchor revision.
        h.fieldHint(revision: BigInt.one);
        await h.advance(_globalStalenessBound);
        expect(h.repository.calls, hasLength(initialReads + 1));
        expect(
          h.repository.calls.last.projection,
          ConstellationProjection.full,
        );
        expect(h.store.current.coveredRevision.value, BigInt.from(100));
      },
    );

    test(
      'field invalidation arriving during FULL remains pending after settlement',
      () async {
        await h.load();
        final gate = Completer<ConstellationField>();
        h.repository.respond = (_, _) => gate.future;
        unawaited(h.store.requestRefresh(ConstellationRefreshReason.load));
        await h.flush();
        final inFlightReads = h.repository.calls.length;
        for (var i = 0; i < 50; i++) {
          h.fieldHint();
        }
        await h.flush();
        expect(h.repository.calls, hasLength(inFlightReads));

        h.repository.respond = (_, _) async => _field();
        gate.complete(_field());
        await h.flush();
        await h.advance(_globalStalenessBound);
        expect(h.repository.calls, hasLength(inFlightReads + 1));
        expect(h.repository.maxInFlight, 1);
        expect(
          h.repository.calls.last.projection,
          ConstellationProjection.full,
        );
      },
    );
  });

  group('FULL refresh coalescing', () {
    test(
      'in-flight FULL satisfies resume and catch-up without a newer invalidation',
      () async {
        final gate = Completer<ConstellationField>();
        h.repository.respond = (_, _) => gate.future;
        h.lease = h.store.lease();
        unawaited(h.store.requestRefresh(ConstellationRefreshReason.load));
        await h.flush();
        expect(h.repository.calls, hasLength(1));

        for (var i = 0; i < 20; i++) {
          h.sync.port.emitCatchUp(connectionEpoch: i + 2);
          unawaited(h.store.requestRefresh(ConstellationRefreshReason.resume));
        }
        await h.flush();
        expect(h.repository.calls, hasLength(1));

        h.repository.respond = (_, _) async => _field();
        gate.complete(_field());
        await h.flush();
        await h.advance(const Duration(minutes: 1));
        expect(
          h.repository.calls,
          hasLength(1),
          reason: 'No invalidation arrived after the in-flight FULL started.',
        );
        expect(h.repository.maxInFlight, 1);
      },
    );
  });

  group('immutable FULL retry deadline', () {
    test(
      'repeated field hints neither shorten nor postpone RETRY_LATER',
      () async {
        await h.load();
        final hint = _retryLater(retryAfterMs: 7300);
        DateTime? rejectedAt;
        h.repository.respond = (_, _) async {
          if (rejectedAt == null) {
            rejectedAt = h.clock.now();
            throw hint.failure;
          }
          return _field();
        };
        await h.store.requestRefresh(ConstellationRefreshReason.load);
        await h.flush();
        expect(rejectedAt, isNotNull);
        final retryDeadline = rejectedAt!.add(hint.advertisedDelay);
        final readsAtRejection = h.repository.calls.length;

        final lastMomentBeforeRetry = retryDeadline.subtract(
          const Duration(milliseconds: 1),
        );
        while (h.clock.now().isBefore(lastMomentBeforeRetry)) {
          h.fieldHint();
          final remaining = lastMomentBeforeRetry.difference(h.clock.now());
          await h.advance(
            remaining > const Duration(milliseconds: 100)
                ? const Duration(milliseconds: 100)
                : remaining,
          );
          expect(h.clock.now().isBefore(retryDeadline), isTrue);
          expect(h.repository.calls, hasLength(readsAtRejection));
        }
        expect(h.clock.now(), lastMomentBeforeRetry);
        expect(h.repository.calls, hasLength(readsAtRejection));

        // The final pre-deadline hint must neither dispatch early nor restart
        // backoff. Cross the deadline explicitly, then keep hints arriving.
        h.fieldHint();
        await h.advance(const Duration(milliseconds: 1));
        expect(h.clock.now(), retryDeadline);
        for (
          var i = 0;
          i < 50 && h.repository.calls.length == readsAtRejection;
          i++
        ) {
          h.fieldHint();
          await h.advance(const Duration(milliseconds: 5));
        }
        expect(
          h.repository.calls,
          hasLength(readsAtRejection + 1),
          reason:
              'Hints must not postpone the pending retry past its original deadline.',
        );
        final retry = h.repository.calls.last;
        expect(retry.at.isBefore(retryDeadline), isFalse);
        expect(
          retry.at.isAfter(
            retryDeadline.add(const Duration(milliseconds: 250)),
          ),
          isFalse,
        );
        expect(retry.projection, ConstellationProjection.full);
        await h.advance(const Duration(minutes: 1));
        expect(h.repository.calls, hasLength(readsAtRejection + 1));
      },
    );

    test('resume and reconnect catch-up cannot bypass RETRY_LATER', () async {
      await h.load();
      final hint = _retryLater(retryAfterMs: 8700);
      DateTime? firstRejectionAt;
      h.repository.respond = (_, _) async {
        firstRejectionAt ??= h.clock.now();
        throw hint.failure;
      };
      await h.store.requestRefresh(ConstellationRefreshReason.load);
      await h.flush();
      final readsAtRejection = h.repository.calls.length;
      final retryDeadline = firstRejectionAt!.add(hint.advertisedDelay);
      final lastMomentBeforeRetry = retryDeadline.subtract(
        const Duration(milliseconds: 1),
      );
      var connectionEpoch = 2;

      while (h.clock.now().isBefore(lastMomentBeforeRetry)) {
        h.store.setVisible(false);
        h.fieldHint();
        await h.flush();
        h.store.setVisible(true);
        unawaited(h.store.requestRefresh(ConstellationRefreshReason.resume));
        h.sync.port.emitCatchUp(connectionEpoch: connectionEpoch++);
        final remaining = lastMomentBeforeRetry.difference(h.clock.now());
        await h.advance(
          remaining > const Duration(seconds: 1)
              ? const Duration(seconds: 1)
              : remaining,
        );
        expect(
          h.repository.calls,
          hasLength(readsAtRejection),
          reason:
              'Visibility and reconnect triggers must preserve advertised backoff.',
        );
      }
      await h.advance(const Duration(milliseconds: 1));
      await h.advance(const Duration(seconds: 1));
      expect(h.repository.calls, hasLength(readsAtRejection + 1));
      expect(h.repository.calls.last.at.isBefore(retryDeadline), isFalse);
    });

    test(
      'reconnect and resume bound rejected FULL attempts and eventually catch up',
      () async {
        await h.load();
        final initialReads = h.repository.calls.length;
        final hint = _retryLater(retryAfterMs: 12500);
        const triggerWindow = Duration(seconds: 35);
        DateTime? latestRejectionAt;
        h.repository.respond = (_, _) async {
          latestRejectionAt = h.clock.now();
          throw hint.failure;
        };
        await h.store.requestRefresh(ConstellationRefreshReason.load);
        await h.flush();

        for (var second = 0; second < triggerWindow.inSeconds; second++) {
          for (var i = 0; i < 5; i++) {
            h.fieldHint();
            h.sync.port.emitCatchUp(connectionEpoch: second * 5 + i + 2);
            unawaited(
              h.store.requestRefresh(ConstellationRefreshReason.resume),
            );
          }
          await h.advance(const Duration(seconds: 1));
        }

        final attempts = h.repository.calls.skip(initialReads).toList();
        // Include the explicit first attempt, then at most one additional
        // attempt for each advertised backoff interval in the trigger window.
        // Longer permitted backoff may yield fewer attempts; there is no
        // minimum retry count before the subsequent recovery assertion.
        final maximumAttempts =
            1 +
            triggerWindow.inMicroseconds ~/ hint.advertisedDelay.inMicroseconds;
        expect(attempts, isNotEmpty);
        expect(attempts.length, lessThanOrEqualTo(maximumAttempts));
        for (var i = 1; i < attempts.length; i++) {
          expect(
            attempts[i].at.difference(attempts[i - 1].at),
            greaterThanOrEqualTo(hint.advertisedDelay),
          );
        }
        expect(h.repository.maxInFlight, 1);
        expect(
          attempts.every((c) => c.projection == ConstellationProjection.full),
          isTrue,
        );

        // Stop rejecting without sending another trigger. The pending retry
        // itself must fetch and adopt the current field after its deadline.
        final readsBeforeRecovery = h.repository.calls.length;
        final recoveryDeadline = latestRejectionAt!.add(hint.advertisedDelay);
        h.repository.respond = (_, _) async => _field(
          anchorRevision: 2,
          context: 'caught-up',
        );
        final remainingBackoff = recoveryDeadline.difference(h.clock.now());
        await h.advance(
          (remainingBackoff > Duration.zero
                  ? remainingBackoff
                  : Duration.zero) +
              _globalStalenessBound,
        );
        expect(h.repository.calls, hasLength(readsBeforeRecovery + 1));
        expect(h.repository.calls.last.at.isBefore(recoveryDeadline), isFalse);
        expect(
          h.repository.calls.last.projection,
          ConstellationProjection.full,
        );
        expect(h.store.current.field?.context, 'caught-up');
        expect(h.store.current.coveredRevision.value, BigInt.from(2));
        expect(h.repository.maxInFlight, 1);
        await h.advance(const Duration(seconds: 35));
        expect(h.repository.calls, hasLength(readsBeforeRecovery + 1));
      },
    );

    test(
      'retry dispatch rechecks visibility and returns once after its deadline',
      () async {
        await h.load();
        final hint = _retryLater(retryAfterMs: 9100);
        DateTime? rejectedAt;
        h.repository.respond = (_, _) async {
          if (rejectedAt == null) {
            rejectedAt = h.clock.now();
            throw hint.failure;
          }
          return _field();
        };
        await h.store.requestRefresh(ConstellationRefreshReason.load);
        await h.flush();
        final readsAtRejection = h.repository.calls.length;
        h.store.setVisible(false);
        await h.advance(hint.advertisedDelay + const Duration(seconds: 1));
        expect(h.repository.calls, hasLength(readsAtRejection));

        h.store.setVisible(true);
        await h.flush();
        expect(h.repository.calls, hasLength(readsAtRejection + 1));
        expect(
          h.repository.calls.last.at.isBefore(
            rejectedAt!.add(hint.advertisedDelay),
          ),
          isFalse,
        );
        await h.advance(const Duration(minutes: 1));
        expect(h.repository.calls, hasLength(readsAtRejection + 1));
      },
    );
  });
}

// Use the same failure mapper as the real repository's dataOrThrow path. This
// keeps the tests executable before a typed domain retry exception exists and
// requires the server backoff metadata to survive that boundary.
({Exception failure, Duration advertisedDelay}) _retryLater({
  required int retryAfterMs,
}) {
  final hint = GraphQLError(
    message: 'RETRY_LATER',
    extensions: {'code': 'RETRY_LATER', 'retryAfterMs': retryAfterMs},
  );
  return (
    failure: mapRemoteFailure(hint),
    advertisedDelay: Duration(
      milliseconds: hint.extensions!['retryAfterMs']! as int,
    ),
  );
}

ConstellationField _field({int anchorRevision = 1, String context = ''}) =>
    ConstellationField(
      loadedAt: DateTime.utc(2026, 10, 8),
      context: context,
      anchorProjection: ConstellationAnchorProjection(
        revision: ConstellationAnchorRevision(BigInt.from(anchorRevision)),
        anchors: const [],
        pinnedPeers: const [],
        pinnedRequests: const [],
        supportPeers: const [],
        supportEdges: const [],
        serverFilteredBeaconIds: const [],
        serverFilteredBeaconCount: 0,
      ),
    );

typedef _Read = ({
  DateTime at,
  ConstellationProjection projection,
  ConstellationFieldMembershipFilters filters,
});

final class _RefreshRepository implements ConstellationRepositoryPort {
  _RefreshRepository(this.clock);

  final FakeClockPort clock;
  final calls = <_Read>[];
  Future<ConstellationField> Function(int index, _Read call) respond =
      (_, _) async => _field();
  int _inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    final call = (
      at: clock.now(),
      projection: projection,
      filters: membershipFilters,
    );
    final index = calls.length;
    calls.add(call);
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      return await respond(index, call);
    } finally {
      _inFlight--;
    }
  }
}

final class _RefreshHarness {
  _RefreshHarness() {
    repository = _RefreshRepository(clock);
    store = ConstellationFieldStoreCase(
      repository,
      _AccountPort(account.stream),
      clock,
      wakeUp,
      sync.case_,
      env: const Env.fromEnvironment(),
      logger: Logger('LazyConstellationRefreshTest'),
    );
  }

  final account = BehaviorSubject<String>.seeded('account-a');
  final clock = FakeClockPort(DateTime.utc(2026, 10, 8));
  final wakeUp = FakeWakeUpPort();
  final sync = buildTestRealtimeSync();
  late final _RefreshRepository repository;
  late final ConstellationFieldStoreCase store;
  StoreLease? lease;

  Future<void> load() async {
    lease ??= store.lease();
    await store.requestRefresh(ConstellationRefreshReason.load);
    await flush();
  }

  void fieldHint({BigInt? revision}) => sync.port.emitChange(
    RealtimeEntityChange(
      kind: RealtimeEntityKind.constellationField,
      aggregateId: 'global',
      operation: RealtimeOperation.update,
      source: RealtimeChangeSource.serverInvalidation,
      revision: revision,
    ),
  );

  Future<void> flush() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> advance(Duration by) async {
    await flush();
    var remaining = by;
    while (remaining > Duration.zero) {
      final step = remaining > const Duration(seconds: 1)
          ? const Duration(seconds: 1)
          : remaining;
      clock.advance(step);
      wakeUp.elapse(step);
      await flush();
      remaining -= step;
    }
  }

  Future<void> dispose() async {
    lease?.dispose();
    await store.dispose();
    await account.close();
    await sync.port.dispose();
  }
}

final class _AccountPort implements ConstellationAccountPort {
  const _AccountPort(this.currentAccountChanges);

  @override
  final Stream<String> currentAccountChanges;
}
