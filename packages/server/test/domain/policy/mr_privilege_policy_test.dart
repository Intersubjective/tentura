import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/enum.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/policy/mr_privilege_policy.dart';

import '../use_case/meritrank_case_mocks.mocks.dart';

void main() {
  late MockUserRepositoryPort users;

  const userId = 'Ucaller';

  setUp(() {
    users = MockUserRepositoryPort();
    when(
      users.getById(any),
    ).thenAnswer((_) async => const UserEntity(id: userId));
  });

  test('admin role passes without a user lookup', () async {
    await ensureMrPrivilege(
      users,
      userId: userId,
      userRoles: [UserRoles.admin],
    );

    verifyNever(users.getById(any));
  });

  test('mrInit privilege passes', () async {
    when(users.getById(userId)).thenAnswer(
      (_) async =>
          const UserEntity(id: userId, privileges: {UserPrivileges.mrInit}),
    );

    await ensureMrPrivilege(users, userId: userId, userRoles: const []);

    verify(users.getById(userId)).called(1);
  });

  test('neither throws the auth UnauthorizedException', () async {
    await expectLater(
      ensureMrPrivilege(users, userId: userId),
      throwsA(
        isA<UnauthorizedException>().having(
          (e) => e.code.codeNumber,
          'code',
          const AuthExceptionCodes(
            AuthExceptionCode.authUnauthorizedException,
          ).codeNumber,
        ),
      ),
    );
  });
}
