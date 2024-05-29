import 'package:tentura/data/gql/gql_client.dart';

import 'package:tentura/features/beacon/domain/entity/beacon.dart';
import 'package:tentura/features/profile/domain/entity/user.dart';

import 'gql/_g/profile_fetch_by_user_id.req.gql.dart';
import 'gql/_g/user_vote_by_id.req.gql.dart';

class ProfileViewRepository {
  static const _label = 'ProfileView';

  ProfileViewRepository({
    Client? gqlClient,
  }) : _gqlClient = gqlClient ?? GetIt.I<Client>();

  final Client _gqlClient;

  Future<({User user, List<Beacon> beacons})> fetchById(String userId) =>
      _gqlClient
          .request(GProfileFetchByUserIdReq((b) => b.vars.user_id = userId))
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
        (r) {
          final profile = r.dataOrThrow(label: _label).user_by_pk!;
          return (
            user: profile as User,
            beacons: profile.beacons.map((r) => r as Beacon).toList(),
          );
        },
      );

  Future<int> voteById({
    required String userId,
    required int amount,
  }) =>
      _gqlClient
          .request(GUserVoteByIdReq(
            (b) => b.vars
              ..object = userId
              ..amount = amount,
          ))
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
              (r) => r.dataOrThrow(label: _label).insert_vote_user_one!.amount);
}
