import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' show MultipartFile;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:injectable/injectable.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/data/service/invalidation_service.dart';
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
import '../gql/_g/beacon_participant_set_next_move.req.gql.dart';
import '../gql/_g/beacon_participant_offer_help.req.gql.dart';
import '../gql/_g/beacon_room_admit.req.gql.dart';
import '../gql/_g/beacon_room_state_get.req.gql.dart';
import '../gql/_g/beacon_room_state_plan_update.req.gql.dart';
import '../gql/_g/beacon_steward_promote.req.gql.dart';
import '../gql/_g/room_message_attachment_add.req.gql.dart';
import '../gql/_g/room_message_create.req.gql.dart';
import '../gql/_g/room_message_list.req.gql.dart';
import '../gql/_g/room_message_reaction_toggle.req.gql.dart';

@Singleton(env: [Environment.dev, Environment.prod])
class BeaconRoomRepository {
  BeaconRoomRepository(
    this._remoteApiService,
    InvalidationService invalidationService,
  ) {
    _roomInvSub = invalidationService.beaconRoomInvalidations.listen(
      (beaconId) {
        if (!_roomRefreshController.isClosed) {
          _roomRefreshController.add(beaconId);
        }
      },
    );
  }

  static const _label = 'BeaconRoom';

  final RemoteApiService _remoteApiService;

  late final StreamSubscription<String> _roomInvSub;

  final _roomRefreshController = StreamController<String>.broadcast();

  /// Debounced beacon ids where room messages or participants changed remotely.
  Stream<String> get beaconRoomRefresh => _roomRefreshController.stream;

  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
  }) async {
    final r = await _remoteApiService
        .request(
          GRoomMessageListReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..beforeIso = beforeIso,
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
    return sorted
        .map(
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
              title: m.authorTitle,
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
              author: author,
              reactionCounts: reactionCounts,
              myReaction: m.myReaction,
              semanticMarker: m.semanticMarker,
              linkedBlockerId: m.linkedBlockerId,
              linkedFactCardId: m.linkedFactCardId,
              systemPayloadJson: m.systemPayloadJson,
              attachments: parseRoomMessageAttachmentsJson(m.attachmentsJson),
            );
          },
        )
        .toList();
  }

  Future<BeaconRoomState> fetchBeaconRoomState(String beaconId) async {
    final r = await _remoteApiService
        .request(GBeaconRoomStateGetReq((b) => b.vars.beaconId = beaconId))
        .firstWhere((e) => e.dataSource == DataSource.Link);
    final row = r.dataOrThrow(label: _label).BeaconRoomStateGet;
    return BeaconRoomState(
      beaconId: row.beaconId,
      currentPlan: row.currentPlan,
      openBlockerId: row.openBlockerId,
      openBlockerTitle: row.openBlockerTitle,
      lastRoomMeaningfulChange: row.lastRoomMeaningfulChange,
      updatedAt: DateTime.parse(row.updatedAt),
      updatedBy: row.updatedBy,
    );
  }

  Future<void> markRoomSeen({required String beaconId}) async {
    await _remoteApiService
        .request(
          GBeaconParticipantRoomSeenReq((b) => b.vars.beaconId = beaconId),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).BeaconParticipantRoomSeen);
  }

  Future<bool> participantSetNextMove({
    required String beaconId,
    required String targetUserId,
    required String nextMoveText,
    required int nextMoveSource,
    int? nextMoveStatus,
  }) async =>
      _remoteApiService
          .request(
            GBeaconParticipantSetNextMoveReq(
              (b) => b.vars
                ..beaconId = beaconId
                ..targetUserId = targetUserId
                ..nextMoveText = nextMoveText
                ..nextMoveSource = nextMoveSource
                ..nextMoveStatus = nextMoveStatus,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r.dataOrThrow(label: _label).BeaconParticipantSetNextMove);

  Future<bool> updateRoomPlan({
    required String beaconId,
    required String currentPlan,
  }) async =>
      _remoteApiService
          .request(
            GBeaconRoomStatePlanUpdateReq(
              (b) => b.vars
                ..beaconId = beaconId
                ..currentPlan = currentPlan,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r.dataOrThrow(label: _label).BeaconRoomStatePlanUpdate);

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
            offerNote: p.offerNote ?? '',
            nextMoveText: p.nextMoveText,
            nextMoveStatus: p.nextMoveStatus,
            nextMoveSource: p.nextMoveSource,
            linkedMessageId: p.linkedMessageId,
            createdAt: DateTime.parse(p.createdAt),
            updatedAt: DateTime.parse(p.updatedAt),
          ),
        )
        .toList();
  }

  Future<String> createMessage({
    required String beaconId,
    required String body,
    String? replyToMessageId,
    RoomPendingUpload? firstAttachment,
  }) async {
    final multipart = firstAttachment == null
        ? null
        : MultipartFile.fromBytes(
            'file',
            firstAttachment.bytes,
            contentType: MediaType.parse(firstAttachment.mimeType),
            filename: firstAttachment.fileName,
          );
    final r = await _remoteApiService
        .request(
          GRoomMessageCreateReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..body = body
              ..replyToMessageId = replyToMessageId
              ..file = multipart,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link);
    return r.dataOrThrow(label: _label).RoomMessageCreate.id;
  }

  Future<void> addMessageAttachment({
    required String beaconId,
    required String messageId,
    required RoomPendingUpload upload,
  }) async {
    final file = MultipartFile.fromBytes(
      'file',
      upload.bytes,
      contentType: MediaType.parse(upload.mimeType),
      filename: upload.fileName,
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
  }

  Future<Uint8List> downloadRoomAttachmentBytes(String attachmentId) =>
      _remoteApiService.fetchAuthenticatedBytes(
        Uri.parse('$kServerName$kPathRoomAttachmentDownload/$attachmentId'),
      );

  Future<bool> participantOfferHelp({
    required String beaconId,
    required String note,
  }) async =>
      _remoteApiService
          .request(
            GBeaconParticipantOfferHelpReq(
              (b) => b.vars
                ..beaconId = beaconId
                ..body = note,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r.dataOrThrow(label: _label).BeaconParticipantOfferHelp);

  Future<bool> admit({
    required String beaconId,
    required String participantUserId,
  }) async =>
      _remoteApiService
          .request(
            GBeaconRoomAdmitReq(
              (b) => b.vars
                ..beaconId = beaconId
                ..participantUserId = participantUserId,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r.dataOrThrow(label: _label).BeaconRoomAdmit);

  Future<bool> promoteSteward({
    required String beaconId,
    required String stewardUserId,
  }) async =>
      _remoteApiService
          .request(
            GBeaconStewardPromoteReq(
              (b) => b.vars
                ..beaconId = beaconId
                ..stewardUserId = stewardUserId,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r.dataOrThrow(label: _label).BeaconStewardPromote);

  Future<bool> toggleReaction({
    required String beaconId,
    required String messageId,
    required String emoji,
  }) async =>
      _remoteApiService
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

  @disposeMethod
  Future<void> dispose() async {
    await _roomInvSub.cancel();
    await _roomRefreshController.close();
  }
}
