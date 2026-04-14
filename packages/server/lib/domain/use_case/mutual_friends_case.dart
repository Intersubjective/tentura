import 'package:injectable/injectable.dart';

import 'package:tentura_server/data/repository/mutual_friends_repository.dart';

@Singleton(order: 2)
class MutualFriendsCase {
  const MutualFriendsCase(this._repository);

  final MutualFriendsRepository _repository;

  Future<List<Map<String, dynamic>>> fetchMutualFriends({
    required String aliceId,
    required String bobId,
    required String context,
  }) =>
      _repository.fetchMutualFriends(
        aliceId: aliceId,
        bobId: bobId,
        context: context,
      );
}
