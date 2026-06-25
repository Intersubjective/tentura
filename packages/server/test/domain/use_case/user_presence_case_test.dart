import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/enums.dart';
import 'package:tentura_server/domain/entity/user_presence_entity.dart';
import 'package:tentura_server/domain/port/user_presence_repository_port.dart';
import 'package:tentura_server/domain/use_case/user_presence_case.dart';
import 'package:tentura_server/env.dart';

void main() {
  late FakeUserPresenceRepository repo;
  late UserPresenceCase case_;

  const userId = 'Ualice';

  final presence = UserPresenceEntity(
    userId: userId,
    lastSeenAt: DateTime.utc(2025, 6, 1),
    lastNotifiedAt: DateTime.utc(2025, 6, 1),
    offlineAfterDelay: const Duration(minutes: 5),
    status: UserPresenceStatus.online,
  );

  setUp(() {
    repo = FakeUserPresenceRepository();
    case_ = UserPresenceCase(
      repo,
      env: Env(environment: Environment.test),
      logger: Logger('UserPresenceCaseTest'),
    );
  });

  group('UserPresenceCase.get', () {
    test('delegates to repository and returns presence', () async {
      repo.getResult = presence;

      expect(await case_.get(userId), same(presence));
      expect(repo.getCalls, [userId]);
    });

    test('returns null when repository has no row', () async {
      repo.getResult = null;

      expect(await case_.get(userId), isNull);
      expect(repo.getCalls, [userId]);
    });
  });

  group('UserPresenceCase.touch', () {
    test('updates lastSeenAt for the user', () async {
      final before = DateTime.timestamp();

      await case_.touch(userId: userId);

      expect(repo.updateCalls, hasLength(1));
      final call = repo.updateCalls.single;
      expect(call.userId, userId);
      expect(call.status, isNull);
      expect(call.lastSeenAt, isNotNull);
      expect(
        call.lastSeenAt!.difference(before).inMilliseconds,
        lessThan(1000),
      );
    });
  });

  group('UserPresenceCase.setStatus', () {
    test('updates status and lastSeenAt for the user', () async {
      final before = DateTime.timestamp();

      await case_.setStatus(
        userId: userId,
        status: UserPresenceStatus.offline,
      );

      expect(repo.updateCalls, hasLength(1));
      final call = repo.updateCalls.single;
      expect(call.userId, userId);
      expect(call.status, UserPresenceStatus.offline);
      expect(call.lastSeenAt, isNotNull);
      expect(
        call.lastSeenAt!.difference(before).inMilliseconds,
        lessThan(1000),
      );
    });
  });
}

final class FakeUserPresenceRepository implements UserPresenceRepositoryPort {
  UserPresenceEntity? getResult;
  final getCalls = <String>[];
  final updateCalls = <_UpdateCall>[];

  @override
  Future<UserPresenceEntity?> get(String userId) async {
    getCalls.add(userId);
    return getResult;
  }

  @override
  Future<void> update(
    String userId, {
    DateTime? lastSeenAt,
    DateTime? lastNotifiedAt,
    UserPresenceStatus? status,
  }) async {
    updateCalls.add(
      _UpdateCall(
        userId: userId,
        lastSeenAt: lastSeenAt,
        lastNotifiedAt: lastNotifiedAt,
        status: status,
      ),
    );
  }
}

final class _UpdateCall {
  const _UpdateCall({
    required this.userId,
    this.lastSeenAt,
    this.lastNotifiedAt,
    this.status,
  });

  final String userId;
  final DateTime? lastSeenAt;
  final DateTime? lastNotifiedAt;
  final UserPresenceStatus? status;
}
