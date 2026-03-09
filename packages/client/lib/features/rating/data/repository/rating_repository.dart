import 'package:injectable/injectable.dart';

// import 'package:tentura/consts.dart';
import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/profile.dart';

import '../gql/_g/rating_fetch.req.gql.dart';

@lazySingleton
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
          .then((r) => r.map((e) => (e.user! as UserModel).toEntity()));
}
