import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/entity/account_entity.dart';
import 'package:tentura/features/auth/domain/entity/session_cookie_clear_result.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';
import 'package:tentura/features/auth/domain/port/auth_remote_repository_port.dart';
import 'package:tentura/features/auth/domain/use_case/account_case.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

void main() {
  group('AccountCase.normalizeSeed', () {
    final validBytes = Uint8List.fromList(List<int>.generate(kSeedLength, (i) => i));
    final validSeed = base64UrlEncode(validBytes);

    test('accepts padded base64url', () {
      final padded = validSeed.replaceAll('-', '+').replaceAll('_', '/');
      expect(AccountCase.normalizeSeed(padded), validSeed);
    });

    test('rejects wrong byte length', () {
      final short = base64UrlEncode(Uint8List.fromList([1, 2, 3]));
      expect(
        () => AccountCase.normalizeSeed(short),
        throwsA(isA<AuthSeedIsWrongException>()),
      );
    });

    test('rejects empty input', () {
      expect(
        () => AccountCase.normalizeSeed('   '),
        throwsA(isA<AuthSeedIsWrongException>()),
      );
    });
  });

  group('AccountCase.recoverFromSeedAndSignIn', () {
    AccountCase build({
      required RecoverFakeAuthLocal local,
      RecoverFakeAuthRemote? remote,
      RecoverFakeProfileRepository? profile,
    }) =>
        AccountCase(
          local,
          remote ?? RecoverFakeAuthRemote(),
          RecoverFakePlatform(),
          profile ?? RecoverFakeProfileRepository(),
          env: const Env(),
          logger: Logger('test'),
        );

    test('signs in, upserts seed account, sets current id', () async {
      final local = RecoverFakeAuthLocal();
      final remote = RecoverFakeAuthRemote(userId: 'U-recover');
      final profile = RecoverFakeProfileRepository(
        profile: const Profile(id: 'U-recover', displayName: 'Alice'),
      );
      final validSeed = base64UrlEncode(
        Uint8List.fromList(List<int>.generate(kSeedLength, (i) => i + 1)),
      );

      final account = await build(
        local: local,
        remote: remote,
        profile: profile,
      ).recoverFromSeedAndSignIn(validSeed);

      expect(account.id, 'U-recover');
      expect(remote.signInCalls, 1);
      expect(local.upsertCalls, hasLength(1));
      expect(local.upsertCalls.first.$1, 'U-recover');
      expect(local.currentAccountId, 'U-recover');
      expect(local.sessionAccountIds, isEmpty);
    });

    test('is idempotent when account already exists locally', () async {
      final local = RecoverFakeAuthLocal(
        existing: {'U-recover': const AccountEntity(id: 'U-recover')},
      );
      final remote = RecoverFakeAuthRemote(userId: 'U-recover');
      final validSeed = base64UrlEncode(
        Uint8List.fromList(List<int>.generate(kSeedLength, (i) => i + 2)),
      );

      await build(local: local, remote: remote).recoverFromSeedAndSignIn(validSeed);

      expect(local.upsertCalls, hasLength(1));
      expect(local.currentAccountId, 'U-recover');
    });

    test('clears session-only marker when recovering same user', () async {
      final local = RecoverFakeAuthLocal(
        existing: {'U-session': const AccountEntity(id: 'U-session')},
      )..sessionAccountIds.add('U-session');
      final remote = RecoverFakeAuthRemote(userId: 'U-session');
      final validSeed = base64UrlEncode(
        Uint8List.fromList(List<int>.generate(kSeedLength, (i) => i + 3)),
      );

      await build(local: local, remote: remote).recoverFromSeedAndSignIn(validSeed);

      expect(local.sessionAccountIds, isEmpty);
      expect(local.currentAccountId, 'U-session');
    });
  });
}

class RecoverFakeAuthLocal implements AuthLocalRepositoryPort {
  RecoverFakeAuthLocal({Map<String, AccountEntity>? existing})
    : _accounts = Map<String, AccountEntity>.from(existing ?? {});

  final Map<String, AccountEntity> _accounts;
  final List<(String, String, String?)> upsertCalls = [];
  final Set<String> sessionAccountIds = {};
  String? currentAccountId;

  @override
  Future<AccountEntity?> getAccountById(String id) async => _accounts[id];

  @override
  Future<void> upsertAccountWithSeed(
    String id,
    String seed, [
    String? displayName,
  ]) async {
    upsertCalls.add((id, seed, displayName));
    sessionAccountIds.remove(id);
    _accounts[id] = AccountEntity(
      id: id,
      displayName: displayName ?? _accounts[id]?.displayName ?? '',
    );
  }

  @override
  Future<void> addAccount(String id, String seed, [String? displayName]) async {
    _accounts[id] = AccountEntity(id: id);
  }

  @override
  Future<void> storeLinkedSeedIfAbsent(String id, String seed) async {}

  @override
  Future<void> addSessionAccount(String id, [String? displayName]) async {
    _accounts[id] = AccountEntity(id: id);
    sessionAccountIds.add(id);
  }

  @override
  Future<bool> isSessionAccount(String id) async => sessionAccountIds.contains(id);

  @override
  Future<void> setCurrentAccountId(String? id) async {
    currentAccountId = id;
  }

  @override
  Stream<String> currentAccountChanges() => const Stream.empty();
  @override
  Future<void> dispose() async {}
  @override
  Future<String> getCurrentAccountId() async => currentAccountId ?? '';
  @override
  Future<String> getSeedByAccountId(String id) async => 'seed';
  @override
  Future<List<AccountEntity>> getAccountsAll() async => _accounts.values.toList();
  @override
  Future<AccountEntity?> getCurrentAccount() async => null;
  @override
  Future<void> removeAccount(String id) async {}
  @override
  Future<void> updateAccount(AccountEntity account) async {
    _accounts[account.id] = account;
  }
}

class RecoverFakeAuthRemote implements AuthRemoteRepositoryPort {
  RecoverFakeAuthRemote({this.userId = 'U1'});

  final String userId;
  int signInCalls = 0;

  @override
  Future<String> signIn(String seed) async {
    signInCalls++;
    return userId;
  }

  @override
  Future<void> signOut() async {}
  @override
  Future<String> signInWithSession() async => userId;
  @override
  Future<void> establishSessionFromBearer() async {}
  @override
  Future<void> sessionLogout() async {}
  @override
  Future<SessionCookieClearResult> clearSessionCookie() async =>
      SessionCookieClearResult.succeeded;
  @override
  Future<String> signUp({
    required String seed,
    required String displayName,
    required String invitationCode,
    String? handle,
  }) async =>
      userId;
}

class RecoverFakeProfileRepository implements ProfileRepositoryPort {
  RecoverFakeProfileRepository({this.profile = const Profile(id: 'U1')});

  final Profile profile;

  @override
  Stream<RepositoryEvent<Profile>> get changes => const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<Profile> fetchById(String id) async => profile.copyWith(id: id);

  @override
  Future<void> update(
    Profile profile, {
    String? displayName,
    String? description,
    bool dropImage = false,
    ImageEntity? image,
    bool updateHandle = false,
    String? handle,
  }) async {}

  @override
  Future<void> delete(String id) async {}
}

class RecoverFakePlatform implements PlatformRepositoryPort {
  @override
  Future<String> getStringFromClipboard() async => '';

  @override
  Future<String> getAppVersion() async => '0.0.0';

  @override
  Future<void> launchUrl(String uri) async {}

  @override
  Future<void> launchUri(Uri uri) async {}
}
