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

    test('applies user_presence subscription events to snapshot', () async {
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
