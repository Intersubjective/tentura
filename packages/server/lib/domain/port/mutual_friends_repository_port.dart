import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';

abstract class MutualFriendsRepositoryPort {
  Future<List<UserPublicRecord>> fetchMutualFriends({
    required String aliceId,
    required String bobId,
    required String context,
  });
}
