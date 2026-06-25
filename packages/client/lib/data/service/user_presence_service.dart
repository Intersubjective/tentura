import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';
import 'package:tentura_root/domain/enums.dart';

import 'remote_api_service.dart';

/// Live user presence from the V2 WebSocket `user_presence` subscription path.
@singleton
class UserPresenceService {
  UserPresenceService(RemoteApiService remoteApiService)
    : _testSend = null {
    _messagesSub = remoteApiService.webSocketMessages.listen(_onMessage);
    _stateSub = remoteApiService.webSocketState.listen((state) {
      if (state == WebSocketState.connected) {
        _sendWatchUpdates(remoteApiService);
      }
    });
    _remoteApiService = remoteApiService;
  }

  /// Unit tests without [RemoteApiService] / WebSocket wiring.
  @visibleForTesting
  UserPresenceService.forTesting({
    required Stream<Map<String, dynamic>> messages,
    required Stream<WebSocketState> connectionState,
    required void Function(String message) send,
  })  : _remoteApiService = null,
        _testSend = send {
    _messagesSub = messages.listen(_onMessage);
    _stateSub = connectionState.listen((state) {
      if (state == WebSocketState.connected) {
        _sendWatchUpdates(null);
      }
    });
  }

  RemoteApiService? _remoteApiService;
  final void Function(String message)? _testSend;

  final _presenceSubject =
      BehaviorSubject<Map<String, UserPresenceStatus>>.seeded({});

  final _watchSources = <String, Set<String>>{};

  late final StreamSubscription<Map<String, dynamic>> _messagesSub;
  late final StreamSubscription<WebSocketState> _stateSub;

  Stream<Map<String, UserPresenceStatus>> get presenceChanges =>
      _presenceSubject.stream;

  Map<String, UserPresenceStatus> get snapshot => _presenceSubject.value;

  void setWatchPeers(String sourceKey, Set<String> userIds) {
    _watchSources[sourceKey] = {
      for (final id in userIds)
        if (id.isNotEmpty) id,
    };
    _sendWatchUpdates(_remoteApiService);
  }

  void removeWatch(String sourceKey) {
    if (_watchSources.remove(sourceKey) != null) {
      _sendWatchUpdates(_remoteApiService);
    }
  }

  void _sendWatchUpdates(RemoteApiService? api) {
    final peerIds = _watchSources.values.expand((s) => s).toSet().toList();
    if (peerIds.isEmpty) {
      return;
    }
    final payload = jsonEncode({
      'type': 'subscription',
      'path': 'user_presence',
      'payload': {
        'intent': 'watch_updates',
        'params': {'peer_ids': peerIds},
      },
    });
    if (_testSend != null) {
      _testSend(payload);
      return;
    }
    api?.webSocketSend(payload);
  }

  void _onMessage(Map<String, dynamic> message) {
    if (message['type'] != 'subscription' || message['path'] != 'user_presence') {
      return;
    }
    final payload = _normalizeJsonObject(message['payload']);
    if (payload == null || payload['intent'] != 'watch_updates') {
      return;
    }
    final rawEvents = payload['events'];
    if (rawEvents is! List) {
      return;
    }

    final next = Map<String, UserPresenceStatus>.from(_presenceSubject.value);
    for (final raw in rawEvents) {
      final event = _normalizeJsonObject(raw);
      if (event == null) {
        continue;
      }
      final userId = event['user_id'];
      final statusRaw = event['status'];
      if (userId is! String || userId.isEmpty || statusRaw is! String) {
        continue;
      }
      final status = UserPresenceStatus.values.firstWhere(
        (e) => e.name == statusRaw,
        orElse: () => UserPresenceStatus.unknown,
      );
      next[userId] = status;
    }
    _presenceSubject.add(next);
  }

  static Map<String, dynamic>? _normalizeJsonObject(Object? value) {
    if (value == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(jsonEncode(value));
      if (decoded is! Map) {
        return null;
      }
      return Map<String, dynamic>.from(decoded);
    } on Object {
      return null;
    }
  }

  @disposeMethod
  Future<void> dispose() async {
    await _messagesSub.cancel();
    await _stateSub.cancel();
    await _presenceSubject.close();
  }
}
