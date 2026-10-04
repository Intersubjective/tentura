import 'dart:convert';

import 'package:built_collection/built_collection.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/data/gql/tentura_v2_upload.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/port/post_publish_port.dart';
import 'package:tentura/features/beacon_threads/data/gql/_g/room_message_attachment_add.req.gql.dart';

import '../gql/_g/post_publish.req.gql.dart';

@Singleton(as: PostPublishPort, env: [Environment.dev, Environment.prod])
class PostPublishRepository implements PostPublishPort {
  const PostPublishRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _label = 'PostPublish';

  @override
  Future<PostPublishResult> postPublish({
    required String beaconId,
    required String body,
    required List<String> mentionUserIds,
    required List<int> mentionOffsets,
    required List<int> mentionLengths,
    required List<String> recipientIds,
    required Map<String, String> notes,
    required BeaconForwardPolicyValue forwardPolicy,
    RoomPendingUpload? attachment,
  }) async {
    final result = await _remoteApiService
        .request(
          GPostPublishReq(
            (b) => b.vars
              ..id = beaconId
              ..body = body
              ..mentionUserIds = ListBuilder(mentionUserIds)
              ..mentionOffsets = ListBuilder(mentionOffsets)
              ..mentionLengths = ListBuilder(mentionLengths)
              ..recipientIds = ListBuilder(recipientIds)
              ..notes = notes.isEmpty ? null : jsonEncode(notes)
              ..forwardPolicy = forwardPolicy.value
              ..file = attachment == null
                  ? null
                  : TenturaV2Upload(
                      filename: attachment.fileName,
                      mimeType: attachment.mimeType,
                      bytes: attachment.bytes,
                    ),
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).postPublish);
    return PostPublishResult(
      beaconId: result.beaconId,
      rootMessageId: result.rootMessageId,
    );
  }

  @override
  Future<void> addRootAttachment({
    required String beaconId,
    required String messageId,
    required RoomPendingUpload upload,
  }) async {
    await _remoteApiService
        .request(
          GRoomMessageAttachmentAddReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..messageId = messageId
              ..file = TenturaV2Upload(
                filename: upload.fileName,
                mimeType: upload.mimeType,
                bytes: upload.bytes,
              ),
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).RoomMessageAttachmentAdd);
  }
}
