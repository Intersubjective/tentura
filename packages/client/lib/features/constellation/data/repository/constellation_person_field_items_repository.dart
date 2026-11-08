import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/constellation_field_target_kind.dart';
import '../../domain/entity/constellation_person_field_item.dart';
import '../../domain/port/constellation_person_field_items_port.dart';
import '../gql/_g/person_field_items.req.gql.dart';

@LazySingleton(
  as: ConstellationPersonFieldItemsPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
final class ConstellationPersonFieldItemsRepository
    implements ConstellationPersonFieldItemsPort {
  ConstellationPersonFieldItemsRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  @override
  Future<ConstellationPersonFieldItemsPage> fetch({
    required String personId,
    required ConstellationPersonFieldBucket bucket,
    String query = '',
    String? cursor,
  }) async {
    final payload = await _remoteApiService
        .request(
          GPersonFieldItemsReq(
            (b) => b.vars
              ..personId = personId
              ..bucket = bucket.wireValue
              ..query = query.isEmpty ? null : query
              ..cursor = cursor,
          ),
        )
        .firstLinkResponse(label: 'PersonFieldItems')
        .then(
          (response) =>
              response.dataOrThrow(label: 'PersonFieldItems').personFieldItems,
        );
    final items = payload.items?.toList() ?? const [];
    final counts = payload.counts;
    return ConstellationPersonFieldItemsPage(
      items: [
        for (final row in items)
          ConstellationPersonFieldItem(
            id: row.id,
            kind: row.kind == 1
                ? ConstellationFieldTargetKind.post
                : ConstellationFieldTargetKind.request,
            authorId: row.authorId,
            title: row.title,
            rootExcerpt: row.rootExcerpt,
            status: row.status,
            hidden: row.hidden,
            lastActivityAt: DateTime.parse(row.lastActivityAt).toUtc(),
            expiresAt: row.expiresAt == null
                ? null
                : DateTime.parse(row.expiresAt!).toUtc(),
          ),
      ],
      nextCursor: payload.nextCursor,
      counts: ConstellationPersonFieldCounts(
        active: counts.active,
        closed: counts.closed,
        hidden: counts.hidden,
      ),
    );
  }
}
