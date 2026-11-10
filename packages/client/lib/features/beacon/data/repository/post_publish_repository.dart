import 'dart:convert';

import 'package:built_collection/built_collection.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/port/post_publish_port.dart';

import '../gql/_g/post_publish.req.gql.dart';

@Singleton(as: PostPublishPort, env: [Environment.dev, Environment.prod])
class PostPublishRepository implements PostPublishPort {
  const PostPublishRepository(this._remoteApiService);

  final RemoteRequestClient _remoteApiService;

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
    Duration? lifetime,
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
              ..lifetimeHours = lifetime?.inHours,
          ),
        )
        .firstLinkResponse(label: _label)
        .then((r) => r.dataOrThrow(label: _label).postPublish);
    return PostPublishResult(
      beaconId: result.beaconId,
      rootMessageId: result.rootMessageId,
      expiresAt: result.expiresAt == null || result.expiresAt!.isEmpty
          ? null
          : DateTime.parse(result.expiresAt!).toUtc(),
    );
  }
}
