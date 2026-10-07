import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/port/post_conversion_port.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';

import '../gql/_g/beacon_convert_to_request.req.gql.dart';
import 'beacon_repository.dart';

@Singleton(as: PostConversionPort, env: [Environment.dev, Environment.prod])
class PostConversionRepository implements PostConversionPort {
  const PostConversionRepository(
    this._remoteApiService,
    this._beaconRepository,
    this._threadsRepository,
  );

  final RemoteApiService _remoteApiService;

  final BeaconRepository _beaconRepository;

  final BeaconThreadsRepository _threadsRepository;

  static const _label = 'PostConversion';

  static const _uuid = Uuid();

  @override
  Future<PostRootContent> fetchRootContent(String beaconId) async {
    final post = await _beaconRepository.fetchBeaconById(beaconId);
    final rootId = post.postRootMessageId;
    if (rootId == null) return const PostRootContent(body: '');
    final root = await _threadsRepository.fetchMessageTarget(
      beaconId: beaconId,
      messageId: rootId,
    );
    if (root == null) return const PostRootContent(body: '');
    final photo = root.attachments.where((a) => a.isImage).firstOrNull;
    return PostRootContent(
      body: root.body,
      firstImage: photo == null
          ? null
          : ImageEntity(
              localKey: _uuid.v4(),
              fileName: photo.fileName,
              mimeType: photo.mime,
              imageBytes: await _threadsRepository.downloadRoomAttachmentBytes(
                photo.id,
              ),
            ),
    );
  }

  @override
  Future<void> convertToRequest({
    required String beaconId,
    required String title,
    required String description,
    required Set<String> needs,
    required String? primaryNeedSlug,
    required DateTime? startAt,
    required DateTime? endAt,
    required bool isDiscoverable,
    List<String> helperIds = const [],
  }) async {
    await _remoteApiService
        .request(
          GBeaconConvertToRequestReq(
            (b) => b.vars
              ..id = beaconId
              ..title = title
              ..description = description
              ..needs = needs.isEmpty ? null : needs.join(',')
              ..primaryNeedSlug = primaryNeedSlug
              ..startAt = startAt?.toUtc().toIso8601String()
              ..endAt = endAt?.toUtc().toIso8601String()
              ..isDiscoverable = isDiscoverable
              ..helperIds.addAll(helperIds),
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beaconConvertToRequest);
  }
}
