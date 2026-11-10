import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/network_reachability.dart';

/// While offline the app must find out on its own when the server is back:
/// [NetworkReachability] probes with a growing backoff (from 2 s, capped at
/// 30 s), goes online on the first probe that reaches the server, and stops
/// probing. Before this, offline lasted until some other request happened to
/// succeed, so a screen with nothing in flight stayed offline forever.
///
/// The probe is injected: it answers `true` when the server was reached.
/// Time is the fake clock of [fakeAsync].
void main() {
  const step = Duration(milliseconds: 100);
  const firstStep = Duration(seconds: 2);
  const cap = Duration(seconds: 30);

  /// Advances the fake clock in small steps for [total].
  void advance(FakeAsync async, Duration total) {
    var elapsed = Duration.zero;
    while (elapsed < total) {
      async
        ..elapse(step)
        ..flushMicrotasks();
      elapsed += step;
    }
  }

  List<Duration> gaps(Duration start, List<Duration> times) {
    final result = <Duration>[];
    var previous = start;
    for (final t in times) {
      result.add(t - previous);
      previous = t;
    }
    return result;
  }

  group('NetworkReachability probes the server while offline', () {
    test('after a transport failure it probes with a backoff that grows from '
        '2 s and never exceeds 30 s while every probe fails', () {
      fakeAsync((async) {
        final probeTimes = <Duration>[];
        final reachability = NetworkReachability.forTesting(
          probe: () async {
            probeTimes.add(async.elapsed);
            return false;
          },
        );
        final changes = <bool>[];
        final sub = reachability.onlineChanges.listen(changes.add);

        final failedAt = async.elapsed;
        reachability.reportTransportFailure();
        async.flushMicrotasks();
        expect(reachability.isOnline, isFalse);

        final onlineSamples = <bool>[];
        for (var i = 0; i < 3000; i++) {
          async
            ..elapse(step)
            ..flushMicrotasks();
          onlineSamples.add(reachability.isOnline);
        }

        expect(
          probeTimes.length,
          greaterThanOrEqualTo(6),
          reason: 'five minutes offline must keep probing the server',
        );
        final probeGaps = gaps(failedAt, probeTimes);
        expect(
          probeGaps.first,
          lessThanOrEqualTo(firstStep + step),
          reason: 'the first probe comes within the 2 s first step',
        );
        expect(
          probeGaps[1],
          lessThanOrEqualTo(firstStep * 2 + step),
          reason: 'the backoff starts from the 2 s step',
        );
        for (var i = 2; i < probeGaps.length; i++) {
          expect(
            probeGaps[i] + step,
            greaterThanOrEqualTo(probeGaps[i - 1]),
            reason: 'probe gaps never shrink while offline: $probeGaps',
          );
        }
        for (final gap in probeGaps) {
          expect(
            gap,
            lessThanOrEqualTo(cap + step),
            reason: 'no probe gap exceeds the 30 s cap: $probeGaps',
          );
        }
        expect(
          probeGaps.last,
          greaterThan(const Duration(seconds: 15)),
          reason: 'the backoff grows toward the cap: $probeGaps',
        );
        expect(onlineSamples, everyElement(isFalse));
        expect(changes, isNot(contains(true)));

        unawaited(sub.cancel());
        unawaited(reachability.dispose());
        async.flushMicrotasks();
      });
    });

    test('the first probe that reaches the server sets online, emits true '
        'once, and no probe runs afterwards', () {
      fakeAsync((async) {
        var probes = 0;
        var serverUp = false;
        final reachability = NetworkReachability.forTesting(
          probe: () async {
            probes++;
            return serverUp;
          },
        );
        final changes = <bool>[];
        final sub = reachability.onlineChanges.listen(changes.add);

        reachability.reportTransportFailure();
        advance(async, const Duration(seconds: 10));
        expect(reachability.isOnline, isFalse);
        expect(probes, greaterThanOrEqualTo(1));

        serverUp = true;
        advance(async, cap + const Duration(seconds: 1));
        expect(
          reachability.isOnline,
          isTrue,
          reason: 'a probe within one capped gap must find the server back',
        );
        expect(changes.where((online) => online), hasLength(1));

        final probesAtRecovery = probes;
        advance(async, const Duration(minutes: 5));
        expect(
          probes,
          probesAtRecovery,
          reason: 'probing stops once online',
        );
        expect(changes.where((online) => online), hasLength(1));
        expect(reachability.isOnline, isTrue);

        unawaited(sub.cancel());
        unawaited(reachability.dispose());
        async.flushMicrotasks();
      });
    });

    test(
      'a probe that throws counts as a failed probe and probing goes on',
      () {
        fakeAsync((async) {
          var probes = 0;
          final reachability = NetworkReachability.forTesting(
            probe: () async {
              probes++;
              if (probes < 3) throw Exception('Failed to fetch');
              return true;
            },
          )..reportTransportFailure();
          advance(async, const Duration(seconds: 60));

          expect(probes, 3);
          expect(reachability.isOnline, isTrue);

          unawaited(reachability.dispose());
          async.flushMicrotasks();
        });
      },
    );

    test('a request that succeeds while offline also stops probing', () {
      fakeAsync((async) {
        var probes = 0;
        final reachability = NetworkReachability.forTesting(
          probe: () async {
            probes++;
            return false;
          },
        )..reportTransportFailure();
        advance(async, const Duration(seconds: 7));
        expect(probes, greaterThanOrEqualTo(1));

        reachability.reportSuccess();
        final probesAtRecovery = probes;
        advance(async, const Duration(minutes: 5));
        expect(probes, probesAtRecovery);
        expect(reachability.isOnline, isTrue);

        unawaited(reachability.dispose());
        async.flushMicrotasks();
      });
    });

    test('an online service that never fails makes no probe calls', () {
      fakeAsync((async) {
        var probes = 0;
        final reachability = NetworkReachability.forTesting(
          probe: () async {
            probes++;
            return true;
          },
        );

        advance(async, const Duration(minutes: 5));

        expect(probes, 0);
        expect(reachability.isOnline, isTrue);

        unawaited(reachability.dispose());
        async.flushMicrotasks();
      });
    });

    test('a second offline period after recovery probes again from the 2 s '
        'step', () {
      fakeAsync((async) {
        final probeTimes = <Duration>[];
        var serverUp = false;
        final reachability =
            NetworkReachability.forTesting(
                probe: () async {
                  probeTimes.add(async.elapsed);
                  return serverUp;
                },
              )
              // First outage: long enough for the backoff to grow.
              ..reportTransportFailure();
        advance(async, const Duration(seconds: 70));
        serverUp = true;
        advance(async, cap + const Duration(seconds: 1));
        expect(reachability.isOnline, isTrue);
        advance(async, const Duration(seconds: 10));
        probeTimes.clear();

        // Second outage.
        serverUp = false;
        final failedAgainAt = async.elapsed;
        reachability.reportTransportFailure();
        advance(async, const Duration(seconds: 7));

        expect(reachability.isOnline, isFalse);
        expect(
          probeTimes,
          isNotEmpty,
          reason: 'a new outage starts probing again',
        );
        final secondGaps = gaps(failedAgainAt, probeTimes);
        expect(
          secondGaps.first,
          lessThanOrEqualTo(firstStep + step),
          reason: 'the backoff restarts from 2 s, not from the old step',
        );
        expect(
          probeTimes.length,
          greaterThanOrEqualTo(2),
          reason: 'within 7 s of a fresh outage the 2 s and 4 s probes ran',
        );

        unawaited(reachability.dispose());
        async.flushMicrotasks();
      });
    });

    test('dispose stops probing', () {
      fakeAsync((async) {
        var probes = 0;
        final reachability = NetworkReachability.forTesting(
          probe: () async {
            probes++;
            return false;
          },
        )..reportTransportFailure();
        advance(async, const Duration(seconds: 3));
        unawaited(reachability.dispose());
        async.flushMicrotasks();
        final probesAtDispose = probes;

        advance(async, const Duration(minutes: 2));
        expect(probes, probesAtDispose);
      });
    });
  });
}
