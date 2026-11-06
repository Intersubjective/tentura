import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/constellation_field_search_result.dart';
import '../../domain/port/constellation_field_search_port.dart';
import '../gql/_g/field_search.req.gql.dart';

@LazySingleton(
  as: ConstellationFieldSearchPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
final class ConstellationFieldSearchRepository
    implements ConstellationFieldSearchPort {
  ConstellationFieldSearchRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  @override
  Future<ConstellationFieldSearchResult> search({
    required String query,
    required String context,
  }) async {
    final payload = await _remoteApiService
        .request(
          GFieldSearchReq(
            (b) => b.vars
              ..query = query
              ..context = context,
          ),
        )
        .firstLinkResponse(label: 'FieldSearch')
        .then(
          (response) => response.dataOrThrow(label: 'FieldSearch').fieldSearch,
        );
    final people = payload.people?.toList() ?? const [];
    final requests = payload.requests?.toList() ?? const [];
    final posts = payload.posts?.toList() ?? const [];
    return ConstellationFieldSearchResult(
      people: [
        for (final row in people)
          ConstellationFieldSearchPersonHit(
            id: row.id,
            displayName: row.displayName,
            handle: row.handle,
          ),
      ],
      requests: [
        for (final row in requests)
          ConstellationFieldSearchRequestHit(
            id: row.id,
            authorId: row.authorId,
            title: row.title,
            status: row.status,
            hidden: row.hidden,
            lastActivityAt: DateTime.parse(row.lastActivityAt).toUtc(),
          ),
      ],
      posts: [
        for (final row in posts)
          ConstellationFieldSearchPostHit(
            id: row.id,
            authorId: row.authorId,
            rootExcerpt: row.rootExcerpt,
            status: row.status,
            hidden: row.hidden,
            lastActivityAt: DateTime.parse(row.lastActivityAt).toUtc(),
            expiresAt: row.expiresAt == null
                ? null
                : DateTime.parse(row.expiresAt!).toUtc(),
          ),
      ],
    );
  }
}
