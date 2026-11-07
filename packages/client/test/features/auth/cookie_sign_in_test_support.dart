import 'dart:async';

import 'package:tentura/features/auth/data/repository/auth_remote_repository.dart';
import 'package:tentura/features/auth/data/service/web_auth_sign_out_cleanup_web.dart'
    as web_cleanup;
import 'package:tentura/features/auth/domain/entity/account_entity.dart';
import 'package:tentura/features/auth/domain/entity/session_cookie_clear_result.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';
import 'package:tentura/features/auth/domain/port/auth_remote_repository_port.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';

import 'auth_test_helpers.dart';

const selectedAccountId = 'account-alice';
const selectedAccountName = 'Alice';
// A valid, deterministic 32-byte Ed25519 seed, usable by the real AuthBox.
const selectedAccountSeed = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
const cookieAccountId = 'account-boris';
const unrelatedAccountId = 'account-charlie';
const unrelatedAccountSeed = 'charlie-device-seed';

/// Stateful local port: current-account notifications, seeds and session
/// markers behave independently, as they do in AuthLocalRepository.
class CookieSignInLocal extends EmptyAuthLocal {
  CookieSignInLocal({
    bool selectedHasSession = true,
    String? selectedSeed,
    this.currentAccountId = '',
  }) {
    if (selectedHasSession) _sessionIds.add(selectedAccountId);
    if (selectedSeed != null) _seeds[selectedAccountId] = selectedSeed;
  }

  String currentAccountId;
  final _changes = StreamController<String>.broadcast();
  final _accounts = <String, AccountEntity>{
    selectedAccountId: const AccountEntity(
      id: selectedAccountId,
      displayName: selectedAccountName,
    ),
    cookieAccountId: const AccountEntity(
      id: cookieAccountId,
      displayName: 'Boris',
    ),
    unrelatedAccountId: const AccountEntity(
      id: unrelatedAccountId,
      displayName: 'Charlie',
    ),
  };
  final _sessionIds = <String>{cookieAccountId};
  final _seeds = <String, String>{
    unrelatedAccountId: unrelatedAccountSeed,
  };

  @override
  Stream<String> currentAccountChanges() async* {
    yield currentAccountId;
    yield* _changes.stream;
  }

  @override
  Future<void> dispose() => _changes.close();

  @override
  Future<String> getCurrentAccountId() async => currentAccountId;

  @override
  Future<void> setCurrentAccountId(String? id) async {
    currentAccountId = id ?? '';
    _changes.add(currentAccountId);
  }

  @override
  Future<List<AccountEntity>> getAccountsAll() async =>
      _accounts.values.toList();

  @override
  Future<AccountEntity?> getAccountById(String id) async => _accounts[id];

  @override
  Future<AccountEntity?> getCurrentAccount() async =>
      _accounts[currentAccountId];

  @override
  Future<String> getSeedByAccountId(String id) async =>
      _seeds[id] ?? (throw const AuthIdNotFoundException());

  @override
  Future<bool> isSessionAccount(String id) async => _sessionIds.contains(id);

  @override
  Future<void> addSessionAccount(String id, [String? displayName]) async {
    _sessionIds.add(id);
    _accounts.putIfAbsent(
      id,
      () => AccountEntity(id: id, displayName: displayName ?? ''),
    );
  }

  @override
  Future<void> addAccount(String id, String seed, [String? displayName]) async {
    _seeds[id] = seed;
    _accounts[id] = AccountEntity(id: id, displayName: displayName ?? '');
  }

  @override
  Future<void> upsertAccountWithSeed(
    String id,
    String seed, [
    String? displayName,
  ]) async {
    _seeds[id] = seed;
    _sessionIds.remove(id);
    _accounts.putIfAbsent(
      id,
      () => AccountEntity(id: id, displayName: displayName ?? ''),
    );
  }

  @override
  Future<void> storeLinkedSeedIfAbsent(String id, String seed) async {
    _seeds.putIfAbsent(id, () => seed);
  }

  @override
  Future<void> updateAccount(AccountEntity account) async {
    _accounts[account.id] = account;
  }

  @override
  Future<void> removeAccount(String id) async {
    _accounts.remove(id);
    _sessionIds.remove(id);
    _seeds.remove(id);
  }

  @override
  Future<void> retainOnlyAccount(String keepId) async {
    if (keepId.isEmpty) {
      return;
    }
    for (final id in _accounts.keys.toList()) {
      if (id != keepId) {
        await removeAccount(id);
      }
    }
  }

  @override
  Future<void> clearAllAuthData() async {
    _accounts.clear();
    _sessionIds.clear();
    _seeds.clear();
    await setCurrentAccountId(null);
  }
}

/// The session endpoint authenticates the cookie's owner before returning its
/// subject. Rejecting that subject must undo this side effect as well.
final class CookieSignInRemote extends EmptyAuthRemote {
  CookieSignInRemote() : super(sessionUserId: cookieAccountId);

  String? authenticatedAccountId;
  int sessionSignIns = 0;

  @override
  Future<String> signInWithSession() async {
    sessionSignIns++;
    return authenticatedAccountId = sessionUserId;
  }

  @override
  Future<void> signOut() async {
    authenticatedAccountId = null;
  }

  @override
  Future<SessionCookieClearResult> clearSessionCookie() async {
    authenticatedAccountId = null;
    return super.clearSessionCookie();
  }
}

/// Observe the subject returned by the production repository after the real
/// HTTP response has been parsed. Never provide a replacement result.
final class ObservedCookieSignInRemote extends AuthRemoteRepository {
  ObservedCookieSignInRemote({
    required super.remoteApiService,
    required super.log,
  });

  final parsedSessionSubjects = <String>[];

  @override
  Future<String> signInWithSession() async {
    final subject = await super.signInWithSession();
    parsedSessionSubjects.add(subject);
    return subject;
  }
}

/// Exercise the actual web cookie-preference function on the VM too. Only
/// document navigation is left at the platform port.
final class CookiePreferencePlatform extends TestAuthPlatformCleanup {
  @override
  Future<bool> tryPreferCookieSessionSignIn(
    AuthRemoteRepositoryPort remote,
    AuthLocalRepositoryPort local,
    String userId,
  ) => web_cleanup.tryPreferCookieSessionSignIn(remote, local, userId);
}

Future<Object?> selectedAccountSignInError(AuthCase auth) async {
  try {
    await auth.signIn(userId: selectedAccountId);
    return null;
  } catch (error) {
    return error;
  }
}

bool namesSelectedAccountForSignIn(String text, String languageCode) {
  return text == selectedAccountSignInInstruction(languageCode);
}

String selectedAccountSignInInstruction(String languageCode) =>
    switch (languageCode) {
      'en' => 'Sign in again as $selectedAccountName',
      'ru' => 'Войдите снова как $selectedAccountName',
      _ => throw ArgumentError.value(languageCode, 'languageCode'),
    };
