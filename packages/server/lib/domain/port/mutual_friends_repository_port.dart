import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';

// ignore: one_member_abstracts -- injectable port with a single repository entry point
abstract class MutualFriendsRepositoryPort {
  Future<List<UserPublicRecord>> fetchMutualFriends({
    required String aliceId,
    required String bobId,
    required String context,
  });
}
