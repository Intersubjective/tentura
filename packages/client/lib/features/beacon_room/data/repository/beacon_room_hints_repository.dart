import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/open_blocker_cue.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_room_card_hints.dart';

import 'package:tentura/features/inbox/data/gql/_g/inbox_room_context_batch.req.gql.dart';
import 'package:tentura/features/inbox/data/gql/_g/inbox_room_context_batch.data.gql.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';

/// V2 batch: room rows + public fact snippet for inbox / My Work cards.
@lazySingleton
class BeaconRoomHintsRepository {
  BeaconRoomHintsRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

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
          lastSeenAt: _parseOptionalIso(e.lastSeenAt),
          currentLineSnippet: clipBeaconRoomCurrentLine(e.currentLine ?? ''),
          lastRoomMeaningfulChange: _clip(e.lastRoomMeaningfulChange ?? ''),
          myNextMove: _clip(e.nextMoveText ?? ''),
          openBlockerTitle: _clip(e.openBlockerTitle ?? ''),
          openBlocker: _mapOpenBlocker(e),
          publicFactSnippet: _clip(e.publicFactSnippet ?? ''),
        ),
    };
  }

  static OpenBlockerCue? _mapOpenBlocker(
    GInboxRoomContextBatchData_InboxRoomContextBatch e,
  ) {
    final title = (e.openBlockerTitle ?? '').trim();
    if (title.isEmpty) return null;

    final creatorId = (e.openBlockerCreatorId ?? '').trim();
    final target = (e.openBlockerTargetPersonId ?? '').trim();
    final responsibleRaw = (e.openBlockerResponsibleUserId ?? '').trim();
    final responsible = responsibleRaw.isNotEmpty
        ? responsibleRaw
        : OpenBlockerCue.resolveResponsibleUserId(
            creatorId: creatorId,
            targetPersonId: target.isEmpty ? null : target,
          );
    final raisedAt =
        _parseOptionalIso(e.openBlockerCreatedAt) ?? DateTime.now();

    Profile? raiser;
    if (creatorId.isNotEmpty) {
      final displayName = (e.openBlockerCreatorDisplayName ?? '').trim();
      final imageId = (e.openBlockerCreatorImageId ?? '').trim();
      final hasPicture = e.openBlockerCreatorHasPicture == true;
      raiser = Profile(
        id: creatorId,
        displayName: displayName,
        image: hasPicture && imageId.isNotEmpty
            ? ImageEntity(id: imageId)
            : null,
      );
    }

    return OpenBlockerCue(
      creatorId: creatorId,
      targetPersonId: target,
      responsibleUserId: responsible,
      title: title,
      raisedAt: raisedAt,
      raiser: raiser,
    );
  }

  static DateTime? _parseOptionalIso(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static String _clip(String s) {
    final t = s.trim();
    if (t.length <= 180) return t;
    return '${t.substring(0, 177)}…';
  }
}
