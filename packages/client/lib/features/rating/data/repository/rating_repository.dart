import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';

import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/profile.dart';

import '../gql/_g/rating_fetch.data.gql.dart';
import '../gql/_g/rating_fetch.req.gql.dart';

@Singleton(env: [Environment.dev, Environment.prod])
class RatingRepository {
  static const _label = 'Rating';

  RatingRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  Future<Iterable<Profile>> fetch({required String context}) =>
      _remoteApiService
          .request(
            GRatingFetchReq(
              (r) => r
                // ..context = const Context().withEntry(
                //   HttpLinkHeaders(headers: {kHeaderQueryContext: context}),
                // )
                ..vars.context = context,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r.dataOrThrow(label: _label).rating)
          .then(profilesFromRows);

  /// `rating()` returns MeritRank rows for every node type. Beacon `dst`s have
  /// a null `user` relationship; those rows are not people and must be skipped.
  @visibleForTesting
  static List<Profile> profilesFromRows(
    Iterable<GRatingFetchData_rating> rows,
  ) => [
    for (final row in rows)
      if (row.user case final user?) (user as UserModel).toEntity(),
  ];
}
