import 'dart:async';
import 'dart:isolate';

import 'package:sentry/sentry.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/service/constellation_db_scheduler.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

import '../../support/sentry_trace_capture.dart';

const _admissionWait = 'db.admission.wait';

ConstellationDbScheduler _scheduler({
  int maxConcurrent = 1,
  Duration queueDeadline = const Duration(seconds: 30),
}) => ConstellationDbScheduler(
  config: ConstellationDbSchedulerConfig(
    maxConcurrent: maxConcurrent,
    queueDeadline: queueDeadline,
  ),
);

DateTime _now() => DateTime.now().toUtc();

void main() {
  final capture = SentryTraceCapture();

  setUp(capture.start);
  tearDown(capture.stop);

  group('Constellation admission wait span', () {
    test('an admitted request records one admission span under its '
        'transaction that ends before the body starts', () async {
      final request = capture.beginRequest();
      final scheduler = _scheduler();

      late DateTime bodyStartedAt;
      await scheduler.run(ConstellationDbWorkKind.full, () async {
        bodyStartedAt = _now();
      });

      final sent = await capture.finish(request);
      final waits = sent.spansWithOperation(_admissionWait);
      expect(waits, hasLength(1));
      expect(waits.single.context.parentSpanId, request.context.spanId);
      expect(waits.single.status, const SpanStatus.ok());
      expect(
        waits.single.endTimestamp!.isAfter(bodyStartedAt),
        isFalse,
        reason: 'queue time must end when the body is admitted, so it is not '
            'folded into SQL time',
      );
    });

    test('the span of a queued request lasts until a running one releases '
        'its slot, while work admitted at once ends before that', () async {
      final request = capture.beginRequest();
      final scheduler = _scheduler();
      final firstAdmitted = Completer<DateTime>();
      final release = Completer<void>();
      late DateTime secondBodyStartedAt;

      final first = scheduler.run(ConstellationDbWorkKind.full, () {
        firstAdmitted.complete(_now());
        return release.future;
      });
      final firstBodyStartedAt = await firstAdmitted.future;
      final second = scheduler.run(ConstellationDbWorkKind.full, () async {
        secondBodyStartedAt = _now();
      });
      // The second request is still queued behind the first: the slot is held
      // until `release`, so nothing can admit it earlier.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final releasedAt = _now();
      release.complete();
      await Future.wait([first, second]);

      final sent = await capture.finish(request);
      final waits = sent.spansWithOperation(_admissionWait)
        ..sort((a, b) => a.startTimestamp.compareTo(b.startTimestamp));
      expect(waits, hasLength(2));
      final (admittedAtOnce, queued) = (waits.first, waits.last);
      expect(
        admittedAtOnce.endTimestamp!.isAfter(firstBodyStartedAt),
        isFalse,
        reason: 'work admitted at once stops waiting when its body starts',
      );
      expect(
        queued.startTimestamp.isAfter(releasedAt),
        isFalse,
        reason: 'the queued request began waiting while the slot was held',
      );
      expect(
        queued.endTimestamp!.isBefore(releasedAt),
        isFalse,
        reason: 'the queued request must show how long it waited for a slot',
      );
      expect(queued.endTimestamp!.isAfter(secondBodyStartedAt), isFalse);
    });

    test('the span is tagged with the work class and the GraphQL '
        'operation', () async {
      final request = capture.beginRequest(graphqlOperation: 'ConstellationApply');
      final scheduler = _scheduler(maxConcurrent: 3);

      await scheduler.run(ConstellationDbWorkKind.apply, () async {});
      await scheduler.run(ConstellationDbWorkKind.anchors, () async {});
      await scheduler.run(ConstellationDbWorkKind.full, () async {});

      final sent = await capture.finish(request);
      final waits = sent.spansWithOperation(_admissionWait);
      expect(
        waits.map((s) => s.tags['work.class']),
        ['apply', 'anchors', 'full'],
      );
      expect(
        waits.map((s) => s.tags['graphql.operation']),
        everyElement('ConstellationApply'),
      );
    });

    test('the span names the isolate that admitted the work', () async {
      final request = capture.beginRequest();

      await _scheduler().run(ConstellationDbWorkKind.full, () async {});

      final sent = await capture.finish(request);
      final wait = sent.spansWithOperation(_admissionWait).single;
      final isolate = wait.tags['isolate'];
      expect(isolate, isNotNull, reason: 'the isolate must be tagged');
      expect(isolate, isNotEmpty);
      if (Isolate.current.debugName case final name?) {
        expect(isolate, name);
      }
    });

    test('a request refused after its queue deadline shows the wait that '
        'ended by deadline, not by the running work finishing', () async {
      final request = capture.beginRequest();
      final scheduler = _scheduler(
        queueDeadline: const Duration(milliseconds: 40),
      );
      final release = Completer<void>();

      final running = scheduler.run(
        ConstellationDbWorkKind.full,
        () => release.future,
      );
      final refusal = await scheduler
          .run(ConstellationDbWorkKind.full, () async {})
          .then<Object?>((_) => null, onError: (Object e) => e);
      final releasedAt = _now();
      release.complete();
      await running;

      expect(refusal, isA<ConstellationException>());
      expect(
        (refusal! as ConstellationException).code.codeNumber,
        ConstellationExceptionCodes.codeSpace +
            ConstellationExceptionCode.retryLater.index,
      );

      final sent = await capture.finish(request);
      final refused = sent
          .spansWithOperation(_admissionWait)
          .where((s) => s.status != const SpanStatus.ok())
          .single;
      expect(refused.finished, isTrue);
      expect(refused.status, isNot(const SpanStatus.ok()));
      expect(refused.throwable, same(refusal));
      expect(
        refused.endTimestamp!.isAfter(releasedAt),
        isFalse,
        reason: 'the span ended when the queue deadline fired, while the '
            'running work still held the only slot',
      );
    });

    test('work admitted outside any Sentry transaction runs unchanged', () async {
      expect(Sentry.getSpan(), isNull);
      final result = await _scheduler().run(
        ConstellationDbWorkKind.apply,
        () async => 11,
      );
      expect(result, 11);
    });
  });
}
