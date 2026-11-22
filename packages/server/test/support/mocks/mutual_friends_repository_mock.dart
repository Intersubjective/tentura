import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/port/mutual_friends_repository_port.dart';

@Injectable(
  as: MutualFriendsRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class MutualFriendsRepositoryMock implements MutualFriendsRepositoryPort {
  @override
  Future<List<UserPublicRecord>> fetchMutualFriends({
    required String aliceId,
    required String bobId,
    required String context,
  }) => Future.value(const []);
}
