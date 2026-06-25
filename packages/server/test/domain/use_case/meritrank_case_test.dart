import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/enum.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/meritrank_case.dart';

import 'meritrank_case_mocks.mocks.dart';

void main() {
  late MockUserRepositoryPort userRepo;
  late MockMeritrankRepositoryPort meritrankRepo;
  late MeritrankCase case_;
  late Env env;

  const userId = 'Ucaller';
  const initResult = 42;
  const calculateTimeout = Duration(seconds: 30);

  UserEntity user({Set<UserPrivileges>? privileges}) =>
      UserEntity(id: userId, privileges: privileges);

  setUp(() {
    userRepo = MockUserRepositoryPort();
    meritrankRepo = MockMeritrankRepositoryPort();
    env = Env(
      environment: Environment.test,
      meritrankCalculateTimeout: calculateTimeout,
    );
    case_ = MeritrankCase(
      userRepo,
      meritrankRepo,
      env: env,
      logger: Logger('MeritrankCaseTest'),
    );

    when(userRepo.getById(any)).thenAnswer((_) async => user());
    when(meritrankRepo.reset()).thenAnswer((_) async {});
    when(meritrankRepo.init()).thenAnswer((_) async => initResult);
    when(
      meritrankRepo.calculate(
        isBlocking: anyNamed('isBlocking'),
        timeout: anyNamed('timeout'),
      ),
    ).thenAnswer((_) async {});
  });

  group('MeritrankCase.init', () {
    test('admin role bypasses privilege lookup', () async {
      final result = await case_.init(
        userId: userId,
        userRoles: [UserRoles.admin],
      );

      expect(result, initResult);
      verify(meritrankRepo.reset()).called(1);
      verify(meritrankRepo.init()).called(1);
      verifyNever(userRepo.getById(any));
      verifyNever(
        meritrankRepo.calculate(
          isBlocking: anyNamed('isBlocking'),
          timeout: anyNamed('timeout'),
        ),
      );
    });

    test('mrInit privilege allows init', () async {
      when(userRepo.getById(userId)).thenAnswer(
        (_) async => user(privileges: {UserPrivileges.mrInit}),
      );

      final result = await case_.init(userId: userId);

      expect(result, initResult);
      verify(userRepo.getById(userId)).called(1);
      verify(meritrankRepo.reset()).called(1);
      verify(meritrankRepo.init()).called(1);
      verifyNever(
        meritrankRepo.calculate(
          isBlocking: anyNamed('isBlocking'),
          timeout: anyNamed('timeout'),
        ),
      );
    });

    test('missing privilege throws UnauthorizedException', () async {
      await expectLater(
        case_.init(userId: userId),
        throwsA(isA<UnauthorizedException>()),
      );

      verify(userRepo.getById(userId)).called(1);
      verifyNever(meritrankRepo.reset());
      verifyNever(meritrankRepo.init());
      verifyNever(
        meritrankRepo.calculate(
          isBlocking: anyNamed('isBlocking'),
          timeout: anyNamed('timeout'),
        ),
      );
    });

    test('forceCalculate triggers calculate with env timeout', () async {
      when(userRepo.getById(userId)).thenAnswer(
        (_) async => user(privileges: {UserPrivileges.mrInit}),
      );

      await case_.init(
        userId: userId,
        forceCalculate: true,
      );

      verify(meritrankRepo.reset()).called(1);
      verify(meritrankRepo.init()).called(1);
      verify(
        meritrankRepo.calculate(timeout: calculateTimeout),
      ).called(1);
    });

    test('forceCalculate false skips calculate', () async {
      when(userRepo.getById(userId)).thenAnswer(
        (_) async => user(privileges: {UserPrivileges.mrInit}),
      );

      await case_.init(
        userId: userId,
        forceCalculate: false,
      );

      verify(meritrankRepo.reset()).called(1);
      verify(meritrankRepo.init()).called(1);
      verifyNever(
        meritrankRepo.calculate(
          isBlocking: anyNamed('isBlocking'),
          timeout: anyNamed('timeout'),
        ),
      );
    });
  });
}
