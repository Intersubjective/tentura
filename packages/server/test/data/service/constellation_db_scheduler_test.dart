import 'dart:async';

import 'package:test/test.dart';

import 'package:tentura_server/data/service/constellation_db_scheduler.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/constellation_db_admission_port.dart';
import 'package:tentura_server/env.dart';

const _ms = Duration(milliseconds: 1);
const _defaultRetryAfter = Duration(seconds: 2);

ConstellationDbScheduler _scheduler({
  int maxConcurrent = 1,
  int maxQueued = 100,
  Duration queueDeadline = const Duration(seconds: 30),
  double reservedRefreshShare = 0.3,
  Duration retryAfter = _defaultRetryAfter,
}) => ConstellationDbScheduler(
  config: ConstellationDbSchedulerConfig(
    maxConcurrent: maxConcurrent,
    maxQueued: maxQueued,
    queueDeadline: queueDeadline,
    reservedRefreshShare: reservedRefreshShare,
    retryAfter: retryAfter,
  ),
);

/// Work whose body only finishes when the test releases it, so the order and
/// concurrency of admission are observable.
final class _Gate {
  _Gate(this.name, this.log);

  final String name;
  final List<String> log;
  final _release = Completer<void>();
  Future<String> body() async {
    log.add(name);
    await _release.future;
    return name;
  }

  void release() => _release.complete();
}

/// Typed RETRY_LATER carrying the configured backoff hint (the default
/// config hint is [_defaultRetryAfter]); every refusal, whether over the
/// limit or past a queue deadline, must tell the caller when to come back.
Matcher _retryLater({Duration retryAfter = _defaultRetryAfter}) =>
    isA<ConstellationException>()
        .having(
          (e) => e.code,
          'code',
          isA<ConstellationExceptionCodes>().having(
            (c) => c.exceptionCode,
            'exceptionCode',
            ConstellationExceptionCode.retryLater,
          ),
        )
        .having((e) => e.retryAfter, 'retryAfter', retryAfter);

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  group('ConstellationDbScheduler admission', () {
    test('implements the domain admission port', () {
      expect(_scheduler(), isA<ConstellationDbAdmissionPort>());
    });

    test('runs work and returns its result when under the limit', () async {
      final s = _scheduler();
      expect(await s.run(ConstellationDbWorkKind.full, () async => 7), 7);
      expect(await s.run(ConstellationDbWorkKind.apply, () async => 8), 8);
      expect(await s.run(ConstellationDbWorkKind.anchors, () async => 9), 9);
    });

    test('does not start a body until it is admitted', () async {
      final s = _scheduler();
      final log = <String>[];
      final first = _Gate('first', log);
      final second = _Gate('second', log);
      final f1 = s.run(ConstellationDbWorkKind.full, first.body);
      final f2 = s.run(ConstellationDbWorkKind.full, second.body);
      await _settle();
      expect(log, ['first'], reason: 'second must wait outside Drift');
      first.release();
      await _settle();
      expect(log, ['first', 'second']);
      second.release();
      await Future.wait([f1, f2]);
    });

    test('never exceeds the configured concurrency', () async {
      final s = _scheduler(maxConcurrent: 2);
      var running = 0;
      var peak = 0;
      Future<void> body() async {
        peak = ++running > peak ? running : peak;
        await Future<void>.delayed(_ms * 2);
        running--;
      }

      await Future.wait([
        for (var i = 0; i < 20; i++)
          s.run(
            i.isEven
                ? ConstellationDbWorkKind.apply
                : ConstellationDbWorkKind.full,
            body,
          ),
      ]);
      expect(peak, 2);
    });

    test('releases the slot when a body throws', () async {
      final s = _scheduler();
      await expectLater(
        s.run<void>(ConstellationDbWorkKind.full, () async => throw Exception('boom')),
        throwsA(isA<Exception>()),
      );
      expect(await s.run(ConstellationDbWorkKind.full, () async => 1), 1);
    });
  });

  group('ConstellationDbScheduler over the limit', () {
    // maxQueued bounds WAITING items only; work already running does not
    // count against it (one running + maxQueued waiting are all accepted).
    test('rejects admissions beyond the waiting-queue limit with RETRY_LATER '
        'and a backoff hint', () async {
      final s = _scheduler(
        maxQueued: 2,
        retryAfter: const Duration(seconds: 3),
      );
      final log = <String>[];
      final gates = [for (var i = 0; i < 3; i++) _Gate('g$i', log)];
      final admitted = [
        for (final g in gates) s.run(ConstellationDbWorkKind.full, g.body),
      ];
      await _settle();

      Object? error;
      try {
        await s.run(ConstellationDbWorkKind.full, () async => 'late');
      } catch (e) {
        error = e;
      }
      expect(error, _retryLater(retryAfter: const Duration(seconds: 3)));

      for (final g in gates) {
        g.release();
      }
      expect(await Future.wait(admitted), ['g0', 'g1', 'g2']);
    });

    test('rejected work never runs its body', () async {
      final s = _scheduler(maxQueued: 0);
      final hold = _Gate('hold', []);
      final held = s.run(ConstellationDbWorkKind.full, hold.body);
      await _settle();
      var ran = false;
      await expectLater(
        s.run(ConstellationDbWorkKind.full, () async => ran = true),
        throwsA(_retryLater()),
      );
      expect(ran, isFalse);
      hold.release();
      await held;
    });

    test('admits again once the backlog has drained', () async {
      final s = _scheduler(maxQueued: 0);
      final hold = _Gate('hold', []);
      final held = s.run(ConstellationDbWorkKind.full, hold.body);
      await _settle();
      await expectLater(
        s.run(ConstellationDbWorkKind.full, () async => 1),
        throwsA(_retryLater()),
      );
      hold.release();
      await held;
      expect(await s.run(ConstellationDbWorkKind.full, () async => 2), 2);
    });

    test('rejects an interactive write over the limit too', () async {
      final s = _scheduler(maxQueued: 0);
      final hold = _Gate('hold', []);
      final held = s.run(ConstellationDbWorkKind.apply, hold.body);
      await _settle();
      await expectLater(
        s.run(ConstellationDbWorkKind.apply, () async => 1),
        throwsA(_retryLater()),
      );
      hold.release();
      await held;
    });
  });

  group('ConstellationDbScheduler priority and fairness', () {
    test(
      'serves a waiting interactive write before an older waiting refresh',
      () async {
        final s = _scheduler();
        final log = <String>[];
        final hold = _Gate('hold', log);
        final refresh = _Gate('refresh', log);
        final write = _Gate('write', log);
        final h = s.run(ConstellationDbWorkKind.apply, hold.body);
        await _settle();
        final r = s.run(ConstellationDbWorkKind.full, refresh.body);
        await _settle();
        final w = s.run(ConstellationDbWorkKind.apply, write.body);
        await _settle();
        hold.release();
        await _settle();
        expect(log, ['hold', 'write']);
        write.release();
        await _settle();
        refresh.release();
        await Future.wait([h, r, w]);
        expect(log, ['hold', 'write', 'refresh']);
      },
    );

    test('serves waiting refresh work oldest first', () async {
      final s = _scheduler();
      final log = <String>[];
      final hold = _Gate('hold', log);
      final h = s.run(ConstellationDbWorkKind.full, hold.body);
      await _settle();
      final order = <Future<String>>[];
      for (final (i, kind) in [
        ConstellationDbWorkKind.full,
        ConstellationDbWorkKind.anchors,
        ConstellationDbWorkKind.full,
      ].indexed) {
        order.add(
          s.run(kind, () async {
            log.add('r$i');
            return 'r$i';
          }),
        );
        await _settle();
      }
      hold.release();
      await Future.wait([h, ...order]);
      expect(log, ['hold', 'r0', 'r1', 'r2']);
    });

    test('keeps the default reserved refresh share at 30%', () {
      expect(const ConstellationDbSchedulerConfig().reservedRefreshShare, 0.3);
    });

    test('reads the reserved refresh share from the environment', () {
      expect(
        ConstellationDbSchedulerConfig.fromEnv(
          Env.dev(constellationDbRefreshShare: 0.5),
        ).reservedRefreshShare,
        0.5,
      );
      expect(
        ConstellationDbSchedulerConfig.fromEnv(Env.dev()).reservedRefreshShare,
        0.3,
      );
    });

    test(
      'gives refresh work its reserved share while writes keep arriving',
      () async {
        final s = _scheduler(maxQueued: 500);
        final hold = _Gate('hold', []);
        final h = s.run(ConstellationDbWorkKind.apply, hold.body);
        await _settle();
        final order = <String>[];
        final all = <Future<void>>[];
        for (var i = 0; i < 100; i++) {
          all
            ..add(
              s.run(ConstellationDbWorkKind.apply, () async => order.add('w')),
            )
            ..add(
              s.run(ConstellationDbWorkKind.full, () async => order.add('r')),
            );
        }
        await _settle();
        hold.release();
        await Future.wait([h, ...all]);

        // Judged over a long window so rounding of the share does not matter.
        final firstHundred = order.take(100);
        final refreshes = firstHundred.where((k) => k == 'r').length;
        expect(refreshes, inInclusiveRange(25, 35), reason: '$order');
        expect(order.length, 200);
      },
    );
  });

  group('ConstellationDbScheduler queue deadlines', () {
    test('fails every waiting item past its deadline, including those that '
        'never reached the front', () async {
      final s = _scheduler(queueDeadline: _ms * 40);
      final hold = _Gate('hold', []);
      final h = s.run(ConstellationDbWorkKind.full, hold.body);
      await _settle();
      var ran = 0;
      final waiting = [
        for (var i = 0; i < 3; i++)
          s.run(ConstellationDbWorkKind.full, () async => ran++),
      ];
      final outcomes = Future.wait([
        for (final w in waiting)
          w.then<Object?>((_) => 'ok', onError: (Object e) => e),
      ]);
      expect(await outcomes, everyElement(_retryLater()));
      expect(ran, 0);
      hold.release();
      await h;
    });

    test(
      'counts time spent waiting against the deadline for writes as well',
      () async {
        final s = _scheduler(queueDeadline: _ms * 40);
        final hold = _Gate('hold', []);
        final h = s.run(ConstellationDbWorkKind.apply, hold.body);
        await _settle();
        await expectLater(
          s.run(ConstellationDbWorkKind.apply, () async => 1),
          throwsA(_retryLater()),
        );
        hold.release();
        await h;
      },
    );

    test('does not expire work that is admitted before its deadline', () async {
      final s = _scheduler(queueDeadline: _ms * 500);
      final hold = _Gate('hold', []);
      final h = s.run(ConstellationDbWorkKind.full, hold.body);
      await _settle();
      final w = s.run(ConstellationDbWorkKind.full, () async => 'done');
      await _settle();
      hold.release();
      expect(await w, 'done');
      await h;
    });
  });
}
