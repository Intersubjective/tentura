import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/account_profile_controller.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/user_case.dart';
import 'package:tentura_server/env.dart';

final class _FakeUserRepository implements UserRepositoryPort {
  UserEntity user = const UserEntity(id: 'Uabc', displayName: 'ada lovelace');

  String? lastUpdatedDisplayName;

  @override
  Future<UserEntity> getById(String id) async => user;

  @override
  Future<void> update({
    required String id,
    String? displayName,
    String? description,
    String? imageId,
    bool dropImage = false,
    bool setHandle = false,
    String? handle,
  }) async {
    lastUpdatedDisplayName = displayName;
    if (displayName != null) {
      user = UserEntity(id: user.id, displayName: displayName);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeImageRepository implements ImageRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeTaskRepository implements TaskRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late AccountProfileController controller;
  late _FakeUserRepository userRepo;

  setUp(() {
    userRepo = _FakeUserRepository();
    final env = Env(environment: 'test');
    final userCase = UserCase(
      _FakeImageRepository(),
      userRepo,
      _FakeTaskRepository(),
      env: env,
      logger: Logger('AccountProfileControllerTest'),
    );
    controller = AccountProfileController.forTest(userCase);
  });

  Request request(
    String method, {
    String? accountId,
    Object? body,
  }) => Request(
    method,
    Uri.parse('http://localhost/api/v2/accounts/me/profile'),
    body: body == null ? null : jsonEncode(body),
    headers: body == null ? null : {'content-type': 'application/json'},
    context: accountId == null
        ? null
        : {kContextJwtKey: JwtEntity(sub: accountId)},
  );

  group('GET', () {
    test('returns id and displayName for resolved account', () async {
      final res = await controller.get(request('GET', accountId: 'Uabc'));
      expect(res.statusCode, 200);
      final json =
          jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      expect(json, {'id': 'Uabc', 'displayName': 'ada lovelace'});
    });

    test('401 without auth context', () async {
      final res = await controller.get(request('GET'));
      expect(res.statusCode, 401);
    });
  });

  group('PATCH', () {
    test('updates trimmed displayName', () async {
      final res = await controller.patch(
        request('PATCH', accountId: 'Uabc', body: {'displayName': ' Ada L. '}),
      );
      expect(res.statusCode, 200);
      final json =
          jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      expect(json['displayName'], 'Ada L.');
      expect(userRepo.lastUpdatedDisplayName, 'Ada L.');
    });

    test('401 without auth context', () async {
      final res = await controller.patch(
        request('PATCH', body: {'displayName': 'Ada'}),
      );
      expect(res.statusCode, 401);
      expect(userRepo.lastUpdatedDisplayName, isNull);
    });

    test('400 on missing displayName', () async {
      final res = await controller.patch(
        request('PATCH', accountId: 'Uabc', body: <String, Object?>{}),
      );
      expect(res.statusCode, 400);
    });

    test('400 on non-string displayName', () async {
      final res = await controller.patch(
        request('PATCH', accountId: 'Uabc', body: {'displayName': 42}),
      );
      expect(res.statusCode, 400);
    });

    test('400 when too short after trim', () async {
      final res = await controller.patch(
        request('PATCH', accountId: 'Uabc', body: {'displayName': '  a  '}),
      );
      expect(res.statusCode, 400);
      expect(userRepo.lastUpdatedDisplayName, isNull);
    });

    test('400 when longer than $kTitleMaxLength chars', () async {
      final res = await controller.patch(
        request(
          'PATCH',
          accountId: 'Uabc',
          body: {'displayName': 'x' * (kTitleMaxLength + 1)},
        ),
      );
      expect(res.statusCode, 400);
    });

    test('400 on invalid JSON body', () async {
      final res = await controller.patch(
        Request(
          'PATCH',
          Uri.parse('http://localhost/api/v2/accounts/me/profile'),
          body: 'not json',
          headers: {'content-type': 'application/json'},
          context: {kContextJwtKey: const JwtEntity(sub: 'Uabc')},
        ),
      );
      expect(res.statusCode, 400);
    });
  });
}
