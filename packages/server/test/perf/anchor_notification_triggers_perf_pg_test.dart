// Cost of the deferred anchor/cursor notification triggers (plan U15): commit
// latency with and without them, transaction-body vs COMMIT latency under
// concurrent notifying commits, and the backlog of a slow LISTEN consumer.
// pg-only: the triggers need no MeritRank graph.
@Tags(['perf', 'pg'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../support/disposable_pg_target.dart';
import 'anchor_notification_perf.dart';
import 'anchor_notification_perf_report.dart';

Map<String, Object?> _object(Map<String, Object?> json, String key) =>
    json[key]! as Map<String, Object?>;

num _number(Map<String, Object?> json, String key) => json[key]! as num;

void _expectDistribution(
  Map<String, Object?> distribution, {
  required int samples,
  required String reason,
}) {
  expect(_number(distribution, 'samples'), samples, reason: reason);
  expect(_number(distribution, 'p50'), greaterThan(0), reason: reason);
  expect(
    _number(distribution, 'p95'),
    greaterThanOrEqualTo(_number(distribution, 'p50')),
    reason: reason,
  );
  expect(
    _number(distribution, 'max'),
    greaterThanOrEqualTo(_number(distribution, 'p95')),
    reason: reason,
  );
}

void main() {
  group('anchor notification trigger cost', () {
    late DisposablePgWriterSession session;
    late File written;
    late Map<String, Object?> report;

    setUpAll(() async {
      final target = DisposablePgTarget.fromNamedEnvironment(
        envVarName: 'TENTURA_ANCHOR_NOTIFICATION_PERF_TEST_DB',
        defaultNamePrefix: 'tentura_test_anchor_notify_perf',
      );
      session = await setUpDisposablePgWriter(target: target);

      final stale = File('build/perf/$anchorNotificationPerfFixture.json');
      if (stale.existsSync()) stale.deleteSync();
      written = await recordAnchorNotificationPerf(session: session);
      report = jsonDecode(written.readAsStringSync()) as Map<String, Object?>;
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('writes build/perf/anchor_notification_triggers.json', () {
      expect(
        written.path,
        'build/perf/$anchorNotificationPerfFixture.json',
      );
      expect(report['fixture'], anchorNotificationPerfFixture);
      expect(_object(report, 'parameters'), isNotEmpty);
    });

    test('records commit latency with and without the triggers, and the '
        'triggers really fired only in the "with" run', () {
      final commit = _object(report, 'commitLatencyMs');
      final parameters = _object(report, 'parameters');
      final samples = _number(parameters, 'commitSamples').toInt();
      expect(samples, greaterThanOrEqualTo(30));

      final without = _object(commit, 'withoutTriggers');
      final withTriggers = _object(commit, 'withTriggers');
      _expectDistribution(without, samples: samples, reason: 'without');
      _expectDistribution(withTriggers, samples: samples, reason: 'with');
      expect(_number(without, 'hintsDelivered'), 0);
      expect(_number(withTriggers, 'hintsDelivered'), samples);
      expect(commit, contains('overheadP50'));
      expect(commit, contains('overheadP95'));
    });

    test('records transaction-body and COMMIT latency of concurrent '
        'notifying commits separately', () {
      final concurrent = _object(report, 'concurrentCommits');
      final writers = _number(concurrent, 'writers').toInt();
      final perWriter = _number(
        _object(report, 'parameters'),
        'concurrentCommitsPerWriter',
      ).toInt();
      expect(writers, greaterThanOrEqualTo(2));

      final body = _object(concurrent, 'transactionBodyMs');
      final commit = _object(concurrent, 'commitMs');
      _expectDistribution(
        body,
        samples: writers * perWriter,
        reason: 'transaction body',
      );
      _expectDistribution(
        commit,
        samples: writers * perWriter,
        reason: 'COMMIT',
      );
      expect(
        _number(commit, 'p50'),
        isNot(_number(body, 'p50')),
        reason: 'body and COMMIT are timed apart, not one number twice',
      );
    });

    test('measures the backlog of a slow listener and its drain', () {
      final backlog = _object(report, 'listenerBacklog');

      expect(_number(backlog, 'listenerDelayMs'), greaterThan(0));
      expect(_number(backlog, 'notificationsSent'), greaterThan(0));
      expect(
        _number(backlog, 'peakBacklog'),
        inInclusiveRange(1, _number(backlog, 'notificationsSent')),
      );
      expect(_number(backlog, 'drainMs'), greaterThan(0));
    });

    test('leaves the production notification triggers installed and '
        'enabled', () async {
      final rows = await session.writer.execute(
        Sql.named('''
SELECT tgname, tgenabled::text
FROM pg_trigger
WHERE NOT tgisinternal
  AND tgname IN (
    'constellation_anchor_notify_trg',
    'constellation_anchor_cursor_notify_trg'
  )
ORDER BY tgname
'''),
      );

      expect(
        [for (final row in rows) (row[0], row[1])],
        [
          ('constellation_anchor_cursor_notify_trg', 'O'),
          ('constellation_anchor_notify_trg', 'O'),
        ],
      );
    });
  }, timeout: const Timeout(Duration(minutes: 20)));
}
