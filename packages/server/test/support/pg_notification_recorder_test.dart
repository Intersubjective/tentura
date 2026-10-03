import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';

import 'pg_notification_recorder.dart';

String _payload(String entity, String id) =>
    jsonEncode({'entity': entity, 'id': id, 'event': 'update'});

void main() {
  group('PgNotificationRecorder drain barrier', () {
    late StreamController<String> source;
    late PgNotificationRecorder recorder;

    setUp(() {
      source = StreamController<String>();
      recorder = PgNotificationRecorder(source.stream);
    });

    tearDown(() async {
      await recorder.cancel();
      await source.close();
    });

    test('records decoded payloads in arrival order', () async {
      source
        ..add(_payload('beacon_hierarchy', 'A'))
        ..add(_payload('beacon_hierarchy', 'B'));
      await Future<void>.delayed(Duration.zero);

      expect(recorder.messages.map((m) => m['id']), ['A', 'B']);
    });

    test('drain discards notifications emitted before the barrier arrives',
        () async {
      source.add(_payload('beacon_hierarchy', 'late-seed'));

      await recorder.drain(
        sendBarrier: (token) async {
          source.add(_payload('barrier', token));
        },
      );

      expect(recorder.messages, isEmpty);
    });

    test('drain waits for the barrier even when it is delivered late',
        () async {
      final release = Completer<void>();
      String? barrierToken;
      var drained = false;
      final pending = recorder
          .drain(
            sendBarrier: (token) async {
              barrierToken = token;
              source.add(_payload('beacon_hierarchy', 'stale'));
            },
          )
          .then((_) => drained = true);

      await pumpEventQueue();
      expect(barrierToken, isNotNull);
      expect(drained, isFalse);

      release.complete();
      await release.future;
      source.add(_payload('barrier', barrierToken!));
      await pending;
      expect(recorder.messages, isEmpty);
    });

    test('notifications after a drain are kept and barrier is never exposed',
        () async {
      await recorder.drain(
        sendBarrier: (token) async => source.add(_payload('barrier', token)),
      );
      source.add(_payload('beacon_hierarchy', 'fresh'));
      await Future<void>.delayed(Duration.zero);

      expect(recorder.messages.map((m) => m['id']), ['fresh']);
      expect(recorder.messages.any((m) => m['entity'] == 'barrier'), isFalse);
    });

    test('drain fails with a timeout when the barrier never arrives', () async {
      await expectLater(
        recorder.drain(
          sendBarrier: (_) async {},
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
