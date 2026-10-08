import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'anchor_notification_perf_report.dart';

Duration _ms(num v) => Duration(microseconds: (v * 1000).round());

AnchorNotificationPerfReport _report() => AnchorNotificationPerfReport(
  withoutTriggers: AnchorCommitSamples(
    latencies: [for (var i = 1; i <= 20; i++) _ms(i)],
    hintsDelivered: 0,
  ),
  withTriggers: AnchorCommitSamples(
    latencies: [for (var i = 1; i <= 20; i++) _ms(i + 2)],
    hintsDelivered: 20,
  ),
  concurrentWriters: 4,
  concurrentTransactionBody: [for (var i = 1; i <= 40; i++) _ms(i)],
  concurrentCommit: [for (var i = 1; i <= 40; i++) _ms(i * 0.1)],
  listenerBacklog: const AnchorListenerBacklog(
    listenerDelay: Duration(milliseconds: 5),
    notificationsSent: 50,
    peakBacklog: 31,
    drainTime: Duration(milliseconds: 280),
  ),
);

Map<String, Object?> _object(Map<String, Object?> json, String key) =>
    json[key]! as Map<String, Object?>;

void main() {
  group('anchor notification trigger perf report', () {
    test('is named after the fixture and written to the perf directory '
        'as JSON', () {
      final directory = Directory.systemTemp.createTempSync('anchor_perf_');
      addTearDown(() => directory.deleteSync(recursive: true));

      final file = _report().writeTo(directory);

      expect(
        file.path,
        '${directory.path}/$anchorNotificationPerfFixture.json',
      );
      final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      expect(json['fixture'], anchorNotificationPerfFixture);
      expect(anchorNotificationPerfFixture, 'anchor_notification_triggers');
    });

    test('records commit latency percentiles with and without the triggers '
        'and the overhead between them', () {
      final json = _report().toJson();
      final commit = _object(json, 'commitLatencyMs');

      final without = _object(commit, 'withoutTriggers');
      final withTriggers = _object(commit, 'withTriggers');
      expect(without['samples'], 20);
      expect(without['p50'], 10);
      expect(without['p95'], 19);
      expect(without['max'], 20);
      expect(withTriggers['samples'], 20);
      expect(withTriggers['p50'], 12);
      expect(withTriggers['p95'], 21);
      expect(commit['overheadP50'], 2);
      expect(commit['overheadP95'], 2);
    });

    test('records how many hints each variant delivered, so a run whose '
        'triggers did not fire cannot pass as a measurement', () {
      final commit = _object(_report().toJson(), 'commitLatencyMs');

      expect(_object(commit, 'withoutTriggers')['hintsDelivered'], 0);
      expect(_object(commit, 'withTriggers')['hintsDelivered'], 20);
    });

    test('records transaction-body and COMMIT latency under concurrent '
        'commits as separate distributions', () {
      final json = _report().toJson();
      final concurrent = _object(json, 'concurrentCommits');

      expect(concurrent['writers'], 4);
      final body = _object(concurrent, 'transactionBodyMs');
      final commit = _object(concurrent, 'commitMs');
      expect(body['samples'], 40);
      expect(body['p50'], 20);
      expect(body['p95'], 38);
      expect(commit['samples'], 40);
      expect(commit['p50'], 2);
      expect(commit['p95'], 3.8);
      expect(body['p95'], isNot(commit['p95']));
    });

    test('records the slow listener backlog and how long it took to drain', () {
      final backlog = _object(_report().toJson(), 'listenerBacklog');

      expect(backlog['listenerDelayMs'], 5);
      expect(backlog['notificationsSent'], 50);
      expect(backlog['peakBacklog'], 31);
      expect(backlog['drainMs'], 280);
    });

    test('rejects a report with no samples for a measured distribution', () {
      expect(
        () => AnchorNotificationPerfReport(
          withoutTriggers: const AnchorCommitSamples(
            latencies: [],
            hintsDelivered: 0,
          ),
          withTriggers: AnchorCommitSamples(
            latencies: [_ms(1)],
            hintsDelivered: 1,
          ),
          concurrentWriters: 2,
          concurrentTransactionBody: [_ms(1)],
          concurrentCommit: [_ms(1)],
          listenerBacklog: const AnchorListenerBacklog(
            listenerDelay: Duration(milliseconds: 5),
            notificationsSent: 1,
            peakBacklog: 1,
            drainTime: Duration.zero,
          ),
        ),
        throwsArgumentError,
      );
    });
  });
}
