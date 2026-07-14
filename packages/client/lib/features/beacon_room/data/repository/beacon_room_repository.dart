import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:injectable/injectable.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/data/gql/tentura_v2_upload.dart';
import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/domain/contacts/contact_name_overlay.dart';
import 'package:tentura/features/beacon_room/domain/beacon_room_local_change_bus.dart';
import 'package:tentura/features/beacon_room/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';

import '../gql/_g/beacon_participant_list.req.gql.dart';
import '../gql/_g/beacon_participant_room_seen.req.gql.dart';
import '../gql/_g/mark_beacon_room_seen.req.gql.dart';
import '../gql/_g/room_message_mark_semantic_done.req.gql.dart';
import '../gql/_g/beacon_participant_offer_help.req.gql.dart';
import '../gql/_g/beacon_room_admit.req.gql.dart';
import '../gql/_g/beacon_room_state_get.req.gql.dart';
import '../gql/_g/beacon_steward_promote.req.gql.dart';
import '../gql/_g/room_message_attachment_add.req.gql.dart';
import '../gql/_g/room_message_create.req.gql.dart';
import '../gql/_g/room_message_delete.req.gql.dart';
import '../gql/_g/room_message_edit.req.gql.dart';
import '../gql/_g/room_message_list.req.gql.dart';
import '../gql/_g/room_message_reaction_toggle.req.gql.dart';
import '../gql/_g/room_poll_create.req.gql.dart';

@Singleton(env: [Environment.dev, Environment.prod])
class BeaconRoomRepository {
  BeaconRoomRepository(
    this._remoteApiService,
    this._localChangeBus,
    InvalidationService invalidationService,
  ) {
    _remoteRoomInvSub = invalidationService.beaconRoomInvalidations.listen(
      _onRoomInvalidation,
    );
    _localRoomInvSub = _localChangeBus.changes.listen(_onRoomInvalidation);
  }

  static const _label = 'BeaconRoom';

  final RemoteApiService _remoteApiService;

  final BeaconRoomLocalChangeBus _localChangeBus;

  late final StreamSubscription<BeaconRoomInvalidation> _remoteRoomInvSub;

  late final StreamSubscription<BeaconRoomInvalidation> _localRoomInvSub;

  final _roomRefreshController = StreamController<String>.broadcast();

  final _roomInvalidationController =
      StreamController<BeaconRoomInvalidation>.broadcast();

  /// Beacon ids where room state changed remotely or through an own write.
  Stream<String> get beaconRoomRefresh => _roomRefreshController.stream;

  /// Room invalidations from both the WebSocket path and confirmed local writes.
  Stream<BeaconRoomInvalidation> get beaconRoomInvalidations =>
      _roomInvalidationController.stream;

  void _onRoomInvalidation(BeaconRoomInvalidation inv) {
    if (!_roomInvalidationController.isClosed) {
      _roomInvalidationController.add(inv);
    }
    if (_roomRefreshController.isClosed) return;
    if (inv.entityType == BeaconRoomEntityType.roomMessage ||
        inv.entityType == BeaconRoomEntityType.roomReaction ||
        inv.entityType == BeaconRoomEntityType.roomPoll ||
        inv.entityType == BeaconRoomEntityType.participant ||
        inv.entityType == BeaconRoomEntityType.factCard ||
        inv.entityType == BeaconRoomEntityType.blocker ||
        inv.entityType == BeaconRoomEntityType.coordinationItem ||
        inv.entityType == BeaconRoomEntityType.roomSeen) {
      _roomRefreshController.add(inv.beaconId);
    }
  }

  void _notifyLocalChange(
    String beaconId,
    BeaconRoomEntityType entityType,
  ) {
    _localChangeBus.notifyBeaconChanged(
      beaconId: beaconId,
      entityType: entityType,
    );
  }

  void notifyLocalChange({
    required String beaconId,
    required BeaconRoomEntityType entityType,
  }) {
    _notifyLocalChange(beaconId, entityType);
  }

  /// Parses V2 `reactorsJson`: `{ emoji: [{ id, title, hasPicture, imageId, blurHash, picHeight, picWidth }] }`.
  static Map<String, List<Profile>> parseReactorsJson(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const {};
      }
      final out = <String, List<Profile>>{};
      for (final e in decoded.entries) {
        final key = e.key;
        if (key is! String) {
          continue;
        }
        final listVal = e.value;
        if (listVal is! List) {
          continue;
        }
        final profiles = <Profile>[];
        for (final item in listVal) {
          if (item is! Map) {
            continue;
          }
          final map = Map<String, Object?>.from(item);
          final id = map['id'] as String? ?? '';
          if (id.isEmpty) {
            continue;
          }
          final displayName = map['displayName'] as String? ?? '';
          final hasPicture = map['hasPicture'] as bool? ?? false;
          final imageId = map['imageId'] as String? ?? '';
          final blurHash = map['blurHash'] as String? ?? '';
          final picHeight = (map['picHeight'] as num?)?.toInt() ?? 0;
          final picWidth = (map['picWidth'] as num?)?.toInt() ?? 0;
          profiles.add(
            Profile(
              id: id,
              displayName: displayName,
              contactName: contactNameOf(id),
              image: hasPicture && imageId.isNotEmpty
                  ? ImageEntity(
                      id: imageId,
                      authorId: id,
                      blurHash: blurHash,
                      height: picHeight,
                      width: picWidth,
                    )
                  : null,
            ),
          );
        }
        if (profiles.isNotEmpty) {
          out[key] = profiles;
        }
      }
      return out;
    } on Object catch (_) {
      return const {};
    }
  }

  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
    String? threadItemId,
  }) async {
    final r = await _remoteApiService
        .request(
          GRoomMessageListReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..beforeIso = beforeIso
              ..threadItemId = threadItemId,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link);
    final raw = r.dataOrThrow(label: _label).RoomMessageList.toList();
    final sorted = [...raw]
      ..sort(
        (a, b) => DateTime.parse(a.createdAt).compareTo(
          DateTime.parse(b.createdAt),
        ),
      );
    return sorted.map(
      (m) {
        final reactionCounts = <String, int>{};
        final rawJson = m.reactionsJson;
        if (rawJson != null && rawJson.isNotEmpty) {
          final decoded = jsonDecode(rawJson);
          if (decoded is Map) {
            for (final e in decoded.entries) {
              final k = e.key;
              final v = e.value;
              if (k is String && v is num) {
                reactionCounts[k] = v.toInt();
              }
            }
          }
        }
        final author = Profile(
          id: m.authorId,
          displayName: m.authorTitle,
          contactName: contactNameOf(m.authorId),
          image: m.authorHasPicture && m.authorImageId.isNotEmpty
              ? ImageEntity(
                  id: m.authorImageId,
                  authorId: m.authorId,
                  blurHash: m.authorBlurHash,
                  height: m.authorPicHeight,
                  width: m.authorPicWidth,
                )
              : null,
        );
        return RoomMessage(
          id: m.id,
          beaconId: m.beaconId,
          authorId: m.authorId,
          body: m.body,
          createdAt: DateTime.parse(m.createdAt),
          editedAt: m.editedAt != null ? DateTime.parse(m.editedAt!) : null,
          author: author,
          reactionCounts: reactionCounts,
          myReaction: m.myReaction,
          reactors: BeaconRoomRepository.parseReactorsJson(m.reactorsJson),
          semanticMarker: m.semanticMarker,
          linkedBlockerId: m.linkedBlockerId,
          linkedFactCardId: m.linkedFactCardId,
          linkedPollingId: m.linkedPollingId,
          linkedItemId: m.linkedItemId,
          linkedEventKind: m.linkedEventKind,
          linkedItemKind: m.linkedItemKind,
          linkedItemStatus: m.linkedItemStatus,
          linkedItemTitle: m.linkedItemTitle,
          linkedItemBody: m.linkedItemBody,
          linkedItemCreatorId: m.linkedItemCreatorId,
          linkedItemTargetPersonId: m.linkedItemTargetPersonId,
          linkedItemCreatedAt: m.linkedItemCreatedAt != null
              ? DateTime.parse(m.linkedItemCreatedAt!)
              : null,
          linkedItemUpdatedAt: m.linkedItemUpdatedAt != null
              ? DateTime.parse(m.linkedItemUpdatedAt!)
              : null,
          linkedItemLinkedMessageId: m.linkedItemLinkedMessageId,
          linkedItemResolvedAt: m.linkedItemResolvedAt != null
              ? DateTime.parse(m.linkedItemResolvedAt!)
              : null,
          pollDataJson: m.pollDataJson,
          systemPayloadJson: m.systemPayloadJson,
          attachments: parseRoomMessageAttachmentsJson(m.attachmentsJson),
          mentions: m.mentions.toList(),
          threadItemId: m.threadItemId,
        );
      },
    ).toList();
  }

  Future<BeaconRoomState> fetchBeaconRoomState(String beaconId) async {
    final r = await _remoteApiService
        .request(GBeaconRoomStateGetReq((b) => b.vars.beaconId = beaconId))
        .firstWhere((e) => e.dataSource == DataSource.Link);
    final row = r.dataOrThrow(label: _label).BeaconRoomStateGet;
    return BeaconRoomState(
      beaconId: row.beaconId,
      currentLine: row.currentLine,
      openBlockerId: row.openBlockerId,
      openBlockerTitle: row.openBlockerTitle,
      lastRoomMeaningfulChange: row.lastRoomMeaningfulChange,
      updatedAt: DateTime.parse(row.updatedAt),
      updatedBy: row.updatedBy,
    );
  }

  Future<DateTime> markRoomSeen({
    required String beaconId,
    required DateTime readThroughAt,
    String? threadItemId,
  }) async {
    final readThroughIso = readThroughAt.toUtc().toIso8601String();
    if (threadItemId == null) {
      final row = await _remoteApiService
          .request(
            GBeaconParticipantRoomSeenReq(
              (b) => b.vars
                ..beaconId = beaconId
                ..readThroughAt = readThroughIso,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r.dataOrThrow(label: _label).BeaconParticipantRoomSeen);
      return DateTime.parse(row.seenAt).toUtc();
    }
    final row = await _remoteApiService
        .request(
          GMarkBeaconRoomSeenReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..threadItemId = threadItemId
              ..readThroughAt = readThroughIso,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).MarkBeaconRoomSeen);
    return DateTime.parse(row.seenAt).toUtc();
  }

  Future<bool> markMessageSemanticDone({
    required String beaconId,
    required String messageId,
  }) async {
    final ok = await _remoteApiService
        .request(
          GRoomMessageMarkSemanticDoneReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..messageId = messageId,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then(
          (r) => r.dataOrThrow(label: _label).RoomMessageMarkSemanticDone,
        );
    if (ok) {
      _notifyLocalChange(beaconId, BeaconRoomEntityType.roomMessage);
    }
    return ok;
  }

  Future<List<BeaconParticipant>> fetchParticipants(String beaconId) async {
    final r = await _remoteApiService
        .request(
          GBeaconParticipantListReq((b) => b.vars.beaconId = beaconId),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link);
    final rows = r.dataOrThrow(label: _label).BeaconParticipantList;
    return rows
        .map(
          (p) => BeaconParticipant(
            id: p.id,
            beaconId: p.beaconId,
            userId: p.userId,
            role: p.role,
            status: p.status,
            roomAccess: p.roomAccess,
            createdAt: DateTime.parse(p.createdAt),
            updatedAt: DateTime.parse(p.updatedAt),
            userTitle: p.userTitle,
            handle: p.userHandle ?? '',
            userHasPicture: p.userHasPicture,
            userPicHeight: p.userPicHeight,
            userPicWidth: p.userPicWidth,
            userBlurHash: p.userBlurHash,
            userImageId: p.userImageId,
            offerNote: p.offerNote ?? '',
            nextMoveText: p.nextMoveText,
            nextMoveStatus: p.nextMoveStatus,
            nextMoveSource: p.nextMoveSource,
            linkedMessageId: p.linkedMessageId,
            helpType: p.helpType,
            lastSeenRoomAt:
                p.lastSeenRoomAt == null || p.lastSeenRoomAt!.isEmpty
                ? null
                : DateTime.parse(p.lastSeenRoomAt!),
          ),
        )
        .toList();
  }

  Future<String> createMessage({
    required String beaconId,
    required String body,
    String? replyToMessageId,
    String? threadItemId,
    RoomPendingUpload? firstAttachment,
  }) async {
    final multipart = firstAttachment == null
        ? null
        : TenturaV2Upload(
            filename: firstAttachment.fileName,
            mimeType: firstAttachment.mimeType,
            bytes: firstAttachment.bytes,
          );
    final r = await _remoteApiService
        .request(
          GRoomMessageCreateReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..body = body
              ..replyToMessageId = replyToMessageId
              ..threadItemId = threadItemId
              ..file = multipart,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link);
    final id = r.dataOrThrow(label: _label).RoomMessageCreate.id;
    _notifyLocalChange(beaconId, BeaconRoomEntityType.roomMessage);
    return id;
  }

  Future<void> addMessageAttachment({
    required String beaconId,
    required String messageId,
    required RoomPendingUpload upload,
  }) async {
    final file = TenturaV2Upload(
      filename: upload.fileName,
      mimeType: upload.mimeType,
      bytes: upload.bytes,
    );
    await _remoteApiService
        .request(
          GRoomMessageAttachmentAddReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..messageId = messageId
              ..file = file,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).RoomMessageAttachmentAdd);
    _notifyLocalChange(beaconId, BeaconRoomEntityType.roomMessage);
  }

  Future<void> editMessage({
    required String beaconId,
    required String messageId,
    required String body,
  }) async {
    await _remoteApiService
        .request(
          GRoomMessageEditReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..messageId = messageId
              ..body = body,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).RoomMessageEdit);
    _notifyLocalChange(beaconId, BeaconRoomEntityType.roomMessage);
  }

  Future<void> deleteMessage({
    required String beaconId,
    required String messageId,
  }) async {
    await _remoteApiService
        .request(
          GRoomMessageDeleteReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..messageId = messageId,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).RoomMessageDelete);
    _notifyLocalChange(beaconId, BeaconRoomEntityType.roomMessage);
  }

  Future<Uint8List> downloadRoomAttachmentBytes(String attachmentId) =>
      _remoteApiService.fetchAuthenticatedBytes(
        Uri.parse('$kServerName$kPathRoomAttachmentDownload/$attachmentId'),
      );

  Future<bool> participantOfferHelp({
    required String beaconId,
    required String note,
  }) async {
    final ok = await _remoteApiService
        .request(
          GBeaconParticipantOfferHelpReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..body = note,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).BeaconParticipantOfferHelp);
    if (ok) {
      _notifyLocalChange(beaconId, BeaconRoomEntityType.participant);
    }
    return ok;
  }

  Future<bool> admit({
    required String beaconId,
    required String participantUserId,
  }) async {
    final ok = await _remoteApiService
        .request(
          GBeaconRoomAdmitReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..participantUserId = participantUserId,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).BeaconRoomAdmit);
    if (ok) {
      _notifyLocalChange(beaconId, BeaconRoomEntityType.participant);
    }
    return ok;
  }

  Future<bool> promoteSteward({
    required String beaconId,
    required String stewardUserId,
  }) async {
    final ok = await _remoteApiService
        .request(
          GBeaconStewardPromoteReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..stewardUserId = stewardUserId,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).BeaconStewardPromote);
    if (ok) {
      _notifyLocalChange(beaconId, BeaconRoomEntityType.participant);
    }
    return ok;
  }

  Future<bool> toggleReaction({
    required String beaconId,
    required String messageId,
    required String emoji,
  }) async {
    final ok = await _remoteApiService
        .request(
          GRoomMessageReactionToggleReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..messageId = messageId
              ..emoji = emoji,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).RoomMessageReactionToggle);
    if (ok) {
      _notifyLocalChange(beaconId, BeaconRoomEntityType.roomReaction);
    }
    return ok;
  }

  Future<void> createPoll({
    required String beaconId,
    required String question,
    required List<String> variants,
    String pollType = 'single',
    bool isAnonymous = true,
    bool allowRevote = true,
  }) async {
    await _remoteApiService
        .request(
          GRoomPollCreateReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..question = question
              ..variants.replace(variants)
              ..pollType = pollType
              ..isAnonymous = isAnonymous
              ..allowRevote = allowRevote,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).RoomPollCreate);
    _notifyLocalChange(beaconId, BeaconRoomEntityType.roomPoll);
  }

  @disposeMethod
  Future<void> dispose() async {
    await _remoteRoomInvSub.cancel();
    await _localRoomInvSub.cancel();
    await _roomInvalidationController.close();
    await _roomRefreshController.close();
  }
}
