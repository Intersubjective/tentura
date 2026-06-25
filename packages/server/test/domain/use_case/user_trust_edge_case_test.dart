import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/enum.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/user_trust_edge_case.dart';

import 'user_trust_edge_case_mocks.mocks.dart';

void main() {
  late MockUserRepositoryPort userRepo;
  late MockUserTrustEdgeRepositoryPort trustEdgeRepo;
  late UserTrustEdgeCase case_;

  const userId = 'Ucaller';
  const sourceUserId = 'Usource';
  const subjectUserId = 'Usubject';
  const objectUserId = 'Uobject';

  UserEntity user({Set<UserPrivileges>? privileges}) =>
      UserEntity(id: userId, privileges: privileges);

  setUp(() {
    userRepo = MockUserRepositoryPort();
    trustEdgeRepo = MockUserTrustEdgeRepositoryPort();
    case_ = UserTrustEdgeCase(
      userRepo,
      trustEdgeRepo,
      env: Env(environment: Environment.test),
      logger: Logger('UserTrustEdgeCaseTest'),
    );

    when(userRepo.getById(any)).thenAnswer((_) async => user());
    when(
      trustEdgeRepo.setVoteAmountAndApplyEvidence(
        subjectUserId: anyNamed('subjectUserId'),
        objectUserId: anyNamed('objectUserId'),
        newAmount: anyNamed('newAmount'),
      ),
    ).thenAnswer((_) async {});
    when(trustEdgeRepo.forceRefreshStar(any)).thenAnswer((_) async {});
    when(trustEdgeRepo.forceRefreshAll()).thenAnswer((_) async {});
    when(trustEdgeRepo.cutoverBackfillIfNeeded()).thenAnswer((_) async {});
  });

  group('UserTrustEdgeCase.setUserVote', () {
    test('delegates vote amount to trust edge repository', () async {
      await case_.setUserVote(
        subjectUserId: subjectUserId,
        objectUserId: objectUserId,
        amount: 3,
      );

      verify(
        trustEdgeRepo.setVoteAmountAndApplyEvidence(
          subjectUserId: subjectUserId,
          objectUserId: objectUserId,
          newAmount: 3,
        ),
      ).called(1);
      verifyZeroInteractions(userRepo);
    });
  });

  group('UserTrustEdgeCase.forceRefreshStar', () {
    test('admin role bypasses privilege lookup', () async {
      await case_.forceRefreshStar(
        userId: userId,
        sourceUserId: sourceUserId,
        userRoles: [UserRoles.admin],
      );

      verify(trustEdgeRepo.forceRefreshStar(sourceUserId)).called(1);
      verifyNever(userRepo.getById(any));
    });

    test('mrInit privilege allows refresh', () async {
      when(userRepo.getById(userId)).thenAnswer(
        (_) async => user(privileges: {UserPrivileges.mrInit}),
      );

      await case_.forceRefreshStar(
        userId: userId,
        sourceUserId: sourceUserId,
      );

      verify(userRepo.getById(userId)).called(1);
      verify(trustEdgeRepo.forceRefreshStar(sourceUserId)).called(1);
    });

    test('missing privilege throws UnauthorizedException', () async {
      await expectLater(
        case_.forceRefreshStar(
          userId: userId,
          sourceUserId: sourceUserId,
        ),
        throwsA(isA<UnauthorizedException>()),
      );

      verify(userRepo.getById(userId)).called(1);
      verifyNever(trustEdgeRepo.forceRefreshStar(any));
    });
  });

  group('UserTrustEdgeCase.forceRefreshAll', () {
    test('admin role bypasses privilege lookup', () async {
      await case_.forceRefreshAll(
        userId: userId,
        userRoles: [UserRoles.admin],
      );

      verify(trustEdgeRepo.forceRefreshAll()).called(1);
      verifyNever(userRepo.getById(any));
    });

    test('mrInit privilege allows refresh', () async {
      when(userRepo.getById(userId)).thenAnswer(
        (_) async => user(privileges: {UserPrivileges.mrInit}),
      );

      await case_.forceRefreshAll(userId: userId);

      verify(userRepo.getById(userId)).called(1);
      verify(trustEdgeRepo.forceRefreshAll()).called(1);
    });

    test('missing privilege throws UnauthorizedException', () async {
      await expectLater(
        case_.forceRefreshAll(userId: userId),
        throwsA(isA<UnauthorizedException>()),
      );

      verify(userRepo.getById(userId)).called(1);
      verifyNever(trustEdgeRepo.forceRefreshAll());
    });
  });

  group('UserTrustEdgeCase.cutoverBackfillIfNeeded', () {
    test('delegates to trust edge repository', () async {
      await case_.cutoverBackfillIfNeeded();

      verify(trustEdgeRepo.cutoverBackfillIfNeeded()).called(1);
      verifyZeroInteractions(userRepo);
    });
  });
}
