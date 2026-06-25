import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/use_case/mutual_friends_case.dart';
import 'package:tentura_server/env.dart';

import 'mutual_friends_case_mocks.mocks.dart';

void main() {
  late MockMutualFriendsRepositoryPort repo;
  late MutualFriendsCase case_;

  const aliceId = 'Ualice';
  const bobId = 'Ubob';
  const context = 'profile_view';

  setUp(() {
    repo = MockMutualFriendsRepositoryPort();
    case_ = MutualFriendsCase(
      repo,
      env: Env(environment: Environment.test),
      logger: Logger('MutualFriendsCaseTest'),
    );
  });

  group('MutualFriendsCase.fetchMutualFriends', () {
    test('delegates to the repository with the same arguments', () async {
      const friends = [
        UserPublicRecord(
          id: 'Ucarol',
          displayName: 'Carol',
          description: '',
          isMutualFriend: true,
        ),
      ];
      when(
        repo.fetchMutualFriends(
          aliceId: anyNamed('aliceId'),
          bobId: anyNamed('bobId'),
          context: anyNamed('context'),
        ),
      ).thenAnswer((_) async => friends);

      final result = await case_.fetchMutualFriends(
        aliceId: aliceId,
        bobId: bobId,
        context: context,
      );

      expect(result, friends);
      verify(
        repo.fetchMutualFriends(
          aliceId: aliceId,
          bobId: bobId,
          context: context,
        ),
      ).called(1);
    });

    test('returns an empty list when the repository has no mutual friends', () async {
      when(
        repo.fetchMutualFriends(
          aliceId: anyNamed('aliceId'),
          bobId: anyNamed('bobId'),
          context: anyNamed('context'),
        ),
      ).thenAnswer((_) async => []);

      final result = await case_.fetchMutualFriends(
        aliceId: aliceId,
        bobId: bobId,
        context: context,
      );

      expect(result, isEmpty);
    });

    test('propagates repository errors', () async {
      when(
        repo.fetchMutualFriends(
          aliceId: anyNamed('aliceId'),
          bobId: anyNamed('bobId'),
          context: anyNamed('context'),
        ),
      ).thenAnswer((_) => Future.error(StateError('db unavailable')));

      await expectLater(
        case_.fetchMutualFriends(
          aliceId: aliceId,
          bobId: bobId,
          context: context,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
