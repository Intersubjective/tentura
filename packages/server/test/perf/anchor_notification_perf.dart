import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:postgres/postgres.dart';

import '../support/disposable_pg_target.dart';
import 'anchor_notification_perf_report.dart';
import 'perf_report.dart';

/// Anchors a viewer holds, and so row-trigger firings per notifying commit.
const _anchorsPerViewer = 8;
const _commitSamples = 60;
const _warmupCommits = 10;
const _concurrentWriters = 4;
const _concurrentCommitsPerWriter = 25;
const _backlogNotifications = 100;
const _listenerDelay = Duration(milliseconds: 5);

const _channel = 'entity_changes';

const _notifyTriggers = [
  ('constellation_anchor', 'constellation_anchor_notify_trg'),
  ('constellation_anchor_cursor', 'constellation_anchor_cursor_notify_trg'),
];

String _viewerId(int i) => 'Uanchperf${i.toString().padLeft(5, '0')}';

String _peerId(int i) => 'Uanchpeer${i.toString().padLeft(5, '0')}';

String _anchorId(String viewer, int j) =>
    'A$viewer${j.toString().padLeft(2, '0')}';

Future<Connection> _open(DisposablePgWriterSession session) => Connection.open(
  session.target.databaseEnv.pgEndpoint,
  settings: session.target.databaseEnv.pgEndpointSettings,
);

/// LISTENs on the realtime channel, counts anchor hints, and offers a barrier:
/// a notification sent after the work under test is delivered after it, so
/// once the barrier is seen every earlier hint has been counted.
final class _HintCounter {
  _HintCounter._(this._connection);

  static Future<_HintCounter> open(DisposablePgWriterSession session) async {
    final counter = _HintCounter._(await _open(session));
    await counter._connection.execute('LISTEN $_channel');
    counter._subscription = counter._connection.channels[_channel].listen(
      counter._onPayload,
    );
    return counter;
  }

  final Connection _connection;
  late final StreamSubscription<String> _subscription;
  final _barriers = <String, Completer<void>>{};
  var _barrierSeq = 0;

  int hints = 0;

  void _onPayload(String payload) {
    final message = jsonDecode(payload) as Map<String, Object?>;
    switch (message['entity']) {
      case 'barrier':
        _barriers.remove(message['id'])?.complete();
      case 'constellation_anchor':
        hints++;
    }
  }

  Future<void> sync(Connection sender) async {
    final token = 'sync-${_barrierSeq++}';
    final seen = _barriers[token] = Completer<void>();
    await sender.execute(
      Sql.named('SELECT pg_notify(@channel, @payload)'),
      parameters: {
        'channel': _channel,
        'payload': jsonEncode({'entity': 'barrier', 'id': token}),
      },
    );
    await seen.future.timeout(const Duration(seconds: 30));
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _connection.close();
  }
}

/// One notifying transaction of [viewer]: moves each of its anchors, so every
/// row fires the deferred trigger and the cursor trigger, which together still
/// publish one hint at COMMIT. The body and the COMMIT are timed apart.
Future<({Duration body, Duration commit})> _notifyingCommit(
  Connection connection,
  String viewer,
  int round,
) async {
  final body = Stopwatch()..start();
  await connection.execute('BEGIN');
  for (var j = 0; j < _anchorsPerViewer; j++) {
    await connection.execute(
      Sql.named(
        'UPDATE public.constellation_anchor SET x_units = @x '
        'WHERE id = @id',
      ),
      parameters: {
        'x': ((round % 19) - 9) + j / 100,
        'id': _anchorId(viewer, j),
      },
    );
  }
  body.stop();
  final commit = Stopwatch()..start();
  await connection.execute('COMMIT');
  commit.stop();
  return (body: body.elapsed, commit: commit.elapsed);
}

Future<void> _seed(Connection writer, List<String> viewers) async {
  final peers = [for (var j = 0; j < _anchorsPerViewer; j++) _peerId(j)];
  await writer.execute(
    Sql.named('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
SELECT id, id, 'pk-' || id, now(), now()
FROM unnest(@ids::text[]) AS id
'''),
    parameters: {
      'ids': [...viewers, ...peers],
    },
  );
  await writer.execute(
    Sql.named(
      'INSERT INTO public.constellation_anchor_cursor (viewer_id) '
      'SELECT unnest(@viewers::text[])',
    ),
    parameters: {'viewers': viewers},
  );
  for (final viewer in viewers) {
    for (var j = 0; j < _anchorsPerViewer; j++) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.constellation_anchor
  (id, viewer_id, person_id, beacon_id, x_units, y_units,
   coordinate_space_version, revision, placed_at)
VALUES (@id, @viewer, @person, NULL, 0, 0, 1, 0, now())
'''),
        parameters: {
          'id': _anchorId(viewer, j),
          'viewer': viewer,
          'person': peers[j],
        },
      );
    }
  }
}

Future<void> _setNotifyTriggers(Connection writer, {required bool on}) async {
  for (final (table, trigger) in _notifyTriggers) {
    await writer.execute(
      'ALTER TABLE public.$table ${on ? 'ENABLE' : 'DISABLE'} TRIGGER $trigger',
    );
  }
}

/// Commit latency of back-to-back notifying commits of one viewer.
Future<AnchorCommitSamples> _sequentialCommits(
  Connection writer,
  _HintCounter counter,
  String viewer,
) async {
  for (var i = 0; i < _warmupCommits; i++) {
    await _notifyingCommit(writer, viewer, i);
  }
  await counter.sync(writer);
  counter.hints = 0;

  final latencies = <Duration>[];
  for (var i = 0; i < _commitSamples; i++) {
    latencies.add((await _notifyingCommit(writer, viewer, i)).commit);
  }
  await counter.sync(writer);
  return AnchorCommitSamples(
    latencies: latencies,
    hintsDelivered: counter.hints,
  );
}

Future<({List<Duration> body, List<Duration> commit})> _concurrentCommits(
  DisposablePgWriterSession session,
  List<String> viewers,
) async {
  final connections = [
    for (final _ in viewers) await _open(session),
  ];
  try {
    final body = <Duration>[];
    final commit = <Duration>[];
    await Future.wait([
      for (var w = 0; w < viewers.length; w++)
        () async {
          for (var i = 0; i < _concurrentCommitsPerWriter; i++) {
            final timed = await _notifyingCommit(connections[w], viewers[w], i);
            body.add(timed.body);
            commit.add(timed.commit);
          }
        }(),
    ]);
    return (body: body, commit: commit);
  } finally {
    await Future.wait([for (final c in connections) c.close()]);
  }
}

/// Sends [_backlogNotifications] notifying commits to a consumer that spends
/// [_listenerDelay] on every notification it receives.
Future<AnchorListenerBacklog> _slowListenerBacklog(
  DisposablePgWriterSession session,
  String viewer,
) async {
  final listener = await _open(session);
  await listener.execute('LISTEN $_channel');
  var received = 0;
  var handled = 0;
  var peak = 0;
  var pumping = false;

  Future<void> pump() async {
    if (pumping) return;
    pumping = true;
    while (handled < received) {
      await Future<void>.delayed(_listenerDelay);
      handled++;
    }
    pumping = false;
  }

  final subscription = listener.channels[_channel].listen((payload) {
    final message = jsonDecode(payload) as Map<String, Object?>;
    if (message['entity'] != 'constellation_anchor') return;
    received++;
    peak = max(peak, received - handled);
    unawaited(pump());
  });
  try {
    final writer = session.writer;
    for (var i = 0; i < _backlogNotifications; i++) {
      await _notifyingCommit(writer, viewer, i);
    }
    final drain = Stopwatch()..start();
    final deadline = DateTime.now().add(const Duration(minutes: 1));
    while (handled < _backlogNotifications) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError(
          'slow listener handled $handled of $_backlogNotifications',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    drain.stop();
    return AnchorListenerBacklog(
      listenerDelay: _listenerDelay,
      notificationsSent: _backlogNotifications,
      peakBacklog: peak,
      drainTime: drain.elapsed,
    );
  } finally {
    await subscription.cancel();
    await listener.close();
  }
}

/// Measures what the deferred anchor notification triggers cost and writes
/// `build/perf/anchor_notification_triggers.json`.
///
/// The triggers are disabled only for the "without" run and enabled again
/// before anything else runs, also when a measurement fails.
Future<File> recordAnchorNotificationPerf({
  required DisposablePgWriterSession session,
}) async {
  final writer = session.writer;
  final sequentialViewer = _viewerId(0);
  final concurrentViewers = [
    for (var w = 0; w < _concurrentWriters; w++) _viewerId(1 + w),
  ];
  final backlogViewer = _viewerId(1 + _concurrentWriters);
  await _seed(writer, [
    sequentialViewer,
    ...concurrentViewers,
    backlogViewer,
  ]);

  final counter = await _HintCounter.open(session);
  try {
    AnchorCommitSamples without;
    await _setNotifyTriggers(writer, on: false);
    try {
      without = await _sequentialCommits(writer, counter, sequentialViewer);
    } finally {
      await _setNotifyTriggers(writer, on: true);
    }
    final withTriggers = await _sequentialCommits(
      writer,
      counter,
      sequentialViewer,
    );
    final concurrent = await _concurrentCommits(session, concurrentViewers);
    final backlog = await _slowListenerBacklog(session, backlogViewer);

    return AnchorNotificationPerfReport(
      withoutTriggers: without,
      withTriggers: withTriggers,
      concurrentWriters: _concurrentWriters,
      concurrentTransactionBody: concurrent.body,
      concurrentCommit: concurrent.commit,
      listenerBacklog: backlog,
      parameters: {
        'commitSamples': _commitSamples,
        'warmupCommits': _warmupCommits,
        'anchorsPerCommit': _anchorsPerViewer,
        'concurrentCommitsPerWriter': _concurrentCommitsPerWriter,
        'backlogNotifications': _backlogNotifications,
        'listenerDelayMs': _listenerDelay.inMilliseconds,
        'commitLatencyScope':
            'COMMIT statement of a transaction updating '
            '$_anchorsPerViewer anchors of one viewer',
      },
    ).writeTo(PerfReport.defaultOutputDirectory);
  } finally {
    await counter.close();
  }
}
