import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/port/mutual_friends_repository_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class MutualFriendsCase extends UseCaseBase {
  MutualFriendsCase(
    this._repository, {
    required super.env,
    required super.logger,
  });

  final MutualFriendsRepositoryPort _repository;

  Future<List<UserPublicRecord>> fetchMutualFriends({
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
