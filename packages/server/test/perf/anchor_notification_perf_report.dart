import 'dart:convert';
import 'dart:io';

import 'perf_report.dart';

/// Name of the fixture, and so of `build/perf/<name>.json`.
const anchorNotificationPerfFixture = 'anchor_notification_triggers';

/// Commit latencies of one variant (triggers disabled or enabled) and the
/// number of anchor hints the listener received while it ran. The count is what
/// tells a run whose triggers never fired from a real measurement.
final class AnchorCommitSamples {
  const AnchorCommitSamples({
    required this.latencies,
    required this.hintsDelivered,
  });

  final List<Duration> latencies;
  final int hintsDelivered;
}

/// A LISTEN consumer slower than the notifications it is sent.
final class AnchorListenerBacklog {
  const AnchorListenerBacklog({
    required this.listenerDelay,
    required this.notificationsSent,
    required this.peakBacklog,
    required this.drainTime,
  });

  /// Time the consumer spends on each notification.
  final Duration listenerDelay;
  final int notificationsSent;

  /// Most notifications received but not yet handled at any moment.
  final int peakBacklog;

  /// From the last notifying commit until the consumer handled everything.
  final Duration drainTime;
}

/// The JSON written to `build/perf/anchor_notification_triggers.json`.
final class AnchorNotificationPerfReport {
  AnchorNotificationPerfReport({
    required this.withoutTriggers,
    required this.withTriggers,
    required this.concurrentWriters,
    required this.concurrentTransactionBody,
    required this.concurrentCommit,
    required this.listenerBacklog,
    this.parameters = const {},
  }) {
    for (final (name, samples) in [
      ('withoutTriggers', withoutTriggers.latencies),
      ('withTriggers', withTriggers.latencies),
      ('concurrentTransactionBody', concurrentTransactionBody),
      ('concurrentCommit', concurrentCommit),
    ]) {
      if (samples.isEmpty) {
        throw ArgumentError.value(samples, name, 'needs at least one sample');
      }
    }
  }

  final AnchorCommitSamples withoutTriggers;
  final AnchorCommitSamples withTriggers;
  final int concurrentWriters;
  final List<Duration> concurrentTransactionBody;
  final List<Duration> concurrentCommit;
  final AnchorListenerBacklog listenerBacklog;
  final Map<String, Object?> parameters;

  Map<String, Object?> toJson() {
    final without = _distribution(withoutTriggers.latencies);
    final withTrig = _distribution(withTriggers.latencies);
    return {
      'fixture': anchorNotificationPerfFixture,
      'parameters': parameters,
      'commitLatencyMs': {
        'withoutTriggers': {
          ...without,
          'hintsDelivered': withoutTriggers.hintsDelivered,
        },
        'withTriggers': {
          ...withTrig,
          'hintsDelivered': withTriggers.hintsDelivered,
        },
        'overheadP50': _round((withTrig['p50']! - without['p50']!).toDouble()),
        'overheadP95': _round((withTrig['p95']! - without['p95']!).toDouble()),
      },
      'concurrentCommits': {
        'writers': concurrentWriters,
        'transactionBodyMs': _distribution(concurrentTransactionBody),
        'commitMs': _distribution(concurrentCommit),
      },
      'listenerBacklog': {
        'listenerDelayMs': _ms(listenerBacklog.listenerDelay),
        'notificationsSent': listenerBacklog.notificationsSent,
        'peakBacklog': listenerBacklog.peakBacklog,
        'drainMs': _ms(listenerBacklog.drainTime),
      },
    };
  }

  /// Writes `<fixture>.json` into [directory], creating it when needed.
  File writeTo(Directory directory) {
    directory.createSync(recursive: true);
    return File('${directory.path}/$anchorNotificationPerfFixture.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(toJson())}\n',
      );
  }

  static double _ms(Duration d) => d.inMicroseconds / 1000;

  static double _round(double ms) => (ms * 1000).round() / 1000;

  static Map<String, num> _distribution(List<Duration> samples) {
    final ms = [for (final s in samples) _ms(s)];
    return {
      'samples': ms.length,
      'p50': nearestRankPercentile(ms, 0.50),
      'p95': nearestRankPercentile(ms, 0.95),
      'max': nearestRankPercentile(ms, 1),
    };
  }
}
