import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_room_card_hints.dart';

import 'package:tentura/features/inbox/data/gql/_g/inbox_room_context_batch.req.gql.dart';

/// V2 batch: room rows + public fact snippet for inbox / My Work cards.
@lazySingleton
class BeaconRoomHintsRepository {
  BeaconRoomHintsRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  final _seenController = StreamController<String>.broadcast();

  /// Local signal after a successful room-seen mutation (WS echo is suppressed for self).
  Stream<String> get roomSeenNotifications => _seenController.stream;

  void notifyRoomSeen(String beaconId) {
    if (!_seenController.isClosed) {
      _seenController.add(beaconId);
    }
  }

  @disposeMethod
  Future<void> dispose() => _seenController.close();

  static const _label = 'InboxRoomContextBatch';

  Future<Map<String, InboxRoomCardHints>> fetchByBeaconIds(
    Iterable<String> beaconIds,
  ) async {
    final ids = beaconIds.toSet().toList();
    if (ids.isEmpty) {
      return {};
    }
    final r = await _remoteApiService
        .request(
          GInboxRoomContextBatchReq((b) => b..vars.beaconIds.addAll(ids)),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link);
    final rows = r.dataOrThrow(label: _label).InboxRoomContextBatch;
    return {
      for (final e in rows)
        e.beaconId: InboxRoomCardHints(
          isRoomMember: e.isRoomMember,
          roomUnreadCount: e.roomUnreadCount,
          currentLineSnippet: _clip(e.currentLine ?? ''),
          lastRoomMeaningfulChange: _clip(e.lastRoomMeaningfulChange ?? ''),
          myNextMove: _clip(e.nextMoveText ?? ''),
          openBlockerTitle: _clip(e.openBlockerTitle ?? ''),
          publicFactSnippet: _clip(e.publicFactSnippet ?? ''),
        ),
    };
  }

  static String _clip(String s) {
    final t = s.trim();
    if (t.length <= 180) return t;
    return '${t.substring(0, 177)}…';
  }
}
