import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/service/user_presence_service.dart';

void main() {
  group('UserPresenceService', () {
    late StreamController<Map<String, dynamic>> messages;
    late StreamController<WebSocketState> connectionState;
    late List<String> sent;
    late UserPresenceService service;

    setUp(() {
      messages = StreamController<Map<String, dynamic>>.broadcast();
      connectionState = StreamController<WebSocketState>.broadcast();
      sent = [];
      service = UserPresenceService.forTesting(
        messages: messages.stream,
        connectionState: connectionState.stream,
        send: sent.add,
      );
    });

    tearDown(() async {
      await service.dispose();
      await messages.close();
      await connectionState.close();
    });

    test('setWatchPeers sends watch_updates with union peer ids', () {
      service
        ..setWatchPeers('friends', {'U1', 'U2'})
        ..setWatchPeers('room:B1', {'U2', 'U3'});

      expect(sent, hasLength(2));
      expect(sent.last, contains('"peer_ids"'));
      expect(sent.last, contains('"U1"'));
      expect(sent.last, contains('"U2"'));
      expect(sent.last, contains('"U3"'));
    });

    test('removeWatch drops a source from the union', () {
      service
        ..setWatchPeers('friends', {'U1'})
        ..setWatchPeers('room:B1', {'U2'})
        ..removeWatch('friends');

      expect(sent.last, contains('"peer_ids":["U2"]'));
    });

    test('removing the last source clears the server watch once', () {
      service
        ..removeWatch('friends')
        ..setWatchPeers('friends', const {});
      expect(sent, isEmpty, reason: 'nothing was watched yet');

      service
        ..setWatchPeers('friends', {'U1'})
        ..removeWatch('friends');
      expect(sent, hasLength(2));
      expect(sent.last, contains('"peer_ids":[]'));

      service.setWatchPeers('room:B1', const {});
      expect(sent, hasLength(2), reason: 'already cleared');
    });

    test('applies user_presence subscription events to snapshot', () async {
      service.setWatchPeers('friends', {'U1', 'U2'});
      final seen = <Map<String, UserPresenceStatus>>[];
      final sub = service.presenceChanges.listen(seen.add);

      messages.add({
        'type': 'subscription',
        'path': 'user_presence',
        'payload': {
          'intent': 'watch_updates',
          'events': [
            {
              'user_id': 'U1',
              'status': 'online',
              'last_seen_at': '2026-06-25T10:00:00.000Z',
            },
            {
              'user_id': 'U2',
              'status': 'offline',
              'last_seen_at': '2026-06-25T09:00:00.000Z',
            },
          ],
        },
      });

      await Future<void>.delayed(Duration.zero);
      expect(
        service.snapshot,
        {
          'U1': UserPresenceStatus.online,
          'U2': UserPresenceStatus.offline,
        },
      );
      await sub.cancel();
    });

    // #533: a dot whose last watcher went away must not stay lit.
    group('#533 stale presence after unwatch', () {
      Future<void> online(List<String> ids) async {
        messages.add({
          'type': 'subscription',
          'path': 'user_presence',
          'payload': {
            'intent': 'watch_updates',
            'events': [
              for (final id in ids) {'user_id': id, 'status': 'online'},
            ],
          },
        });
        await Future<void>.delayed(Duration.zero);
      }

      test('the last removeWatch empties the snapshot and emits', () async {
        service.setWatchPeers('room:B1', {'A', 'B'});
        await online(['A', 'B']);
        expect(service.snapshot.keys, unorderedEquals(['A', 'B']));

        final seen = <Map<String, UserPresenceStatus>>[];
        final sub = service.presenceChanges.skip(1).listen(seen.add);
        service.removeWatch('room:B1');
        await Future<void>.delayed(Duration.zero);

        expect(service.snapshot, isEmpty);
        expect(seen, isNotEmpty);
        expect(seen.last, isEmpty);
        await sub.cancel();
      });

      test('a peer another source still watches keeps its status', () async {
        service
          ..setWatchPeers('friends', {'A'})
          ..setWatchPeers('room:B1', {'A', 'B'});
        await online(['A', 'B']);

        service.removeWatch('room:B1');

        expect(service.snapshot, {'A': UserPresenceStatus.online});
      });

      test('narrowing a source drops the peers no one watches now', () async {
        service.setWatchPeers('room:B1', {'A', 'B'});
        await online(['A', 'B']);

        service.setWatchPeers('room:B1', {'A'});

        expect(service.snapshot, {'A': UserPresenceStatus.online});
      });

      test('an event for a peer no source watches is dropped', () async {
        service.setWatchPeers('room:B1', {'A'});
        await online(['A', 'stranger']);

        expect(service.snapshot, {'A': UserPresenceStatus.online});
      });

      test('a late snapshot after narrowing does not bring B back', () async {
        service.setWatchPeers('room:B1', {'A', 'B'});
        await online(['A', 'B']);
        service.setWatchPeers('room:B1', {'A'});

        // Sent by the server before it saw the narrowed watch.
        await online(['A', 'B']);

        expect(service.snapshot, {'A': UserPresenceStatus.online});
      });

      test('a late event after the last removeWatch stays dropped', () async {
        service
          ..setWatchPeers('room:B1', {'A'})
          ..removeWatch('room:B1');

        await online(['A']);

        expect(service.snapshot, isEmpty);
      });

      test('a peer watched again takes the next event', () async {
        service
          ..setWatchPeers('room:B1', {'A'})
          ..removeWatch('room:B1');
        await online(['A']);
        service.setWatchPeers('friends', {'A'});

        await online(['A']);

        expect(service.snapshot, {'A': UserPresenceStatus.online});
      });

      test('a source that is still watched keeps every status', () async {
        service
          ..setWatchPeers('friends', {'A'})
          ..setWatchPeers('room:B1', {'B'});
        await online(['A', 'B']);

        service.removeWatch('unknown');

        expect(service.snapshot.keys, unorderedEquals(['A', 'B']));
      });
    });

    test('re-sends watch list when socket reconnects', () async {
      service.setWatchPeers('friends', {'U1'});
      sent.clear();

      connectionState.add(WebSocketState.connected);
      await Future<void>.delayed(Duration.zero);

      expect(sent, hasLength(1));
      expect(sent.single, contains('"U1"'));
    });
  });
}
