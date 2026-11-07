import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';

import 'auth_test_helpers.dart';
import 'cookie_sign_in_test_support.dart';

AuthCase _auth(CookieSignInLocal local, CookieSignInRemote remote) => AuthCase(
  local,
  remote,
  TestDevicePush(),
  CookiePreferencePlatform(),
  TestSettingsRepository(),
  env: const Env(),
  logger: Logger('CookieSignInIdentityTest'),
);

void main() {
  group('Cookie sign-in identity', () {
    test(
      'restoring the cookie owner never lets a stale account selection '
      'publish another identity',
      () async {
        final local = CookieSignInLocal(currentAccountId: selectedAccountId);
        addTearDown(local.dispose);
        final remote = CookieSignInRemote();
        final auth = _auth(local, remote);

        // Start with a stale persisted pointer. Selecting a saved account must
        // agree with the cookie-authoritative bootstrap. The companion
        // cookie_sign_in_reload.test.mjs also proves an actual document reload.
        final restored = await auth.bootstrapWebSession();
        expect(restored.sessionUserId, cookieAccountId);
        expect(restored.currentAccountId, cookieAccountId);
        await auth.signInRestored(restored);

        final announced = <String>[];
        final subscription = auth.currentAccountChanges().listen(announced.add);
        addTearDown(subscription.cancel);
        await Future<void>.delayed(Duration.zero);
        expect(announced, [cookieAccountId]);

        await selectedAccountSignInError(auth);
        await Future<void>.delayed(Duration.zero);

        expect(remote.sessionSignIns, 2);
        expect(
          announced,
          isNot(contains(selectedAccountId)),
          reason:
              'the cookie authenticated Boris, so Alice must never be '
              'announced as the signed-in person, even transiently',
        );
        expect(await auth.getCurrentAccountId(), isNot(selectedAccountId));
        expect(
          remote.authenticatedAccountId,
          isNull,
          reason:
              'rejecting Alice after restoring Boris must also undo the '
              'cookie sign-in, even when no incorrect identity was published',
        );
        expect(await local.isSessionAccount(selectedAccountId), isFalse);
      },
    );

    test(
      'rejecting a different cookie owner undoes its remote sign-in',
      () async {
        final local = CookieSignInLocal();
        addTearDown(local.dispose);
        final remote = CookieSignInRemote();

        await selectedAccountSignInError(_auth(local, remote));

        expect(remote.sessionSignIns, 1);
        expect(
          remote.authenticatedAccountId,
          isNull,
          reason:
              'a rejected account switch must not leave authenticated '
              'requests running as the cookie owner',
        );
      },
    );

    test(
      'a mismatched cookie invalidates only the stale saved session',
      () async {
        final local = CookieSignInLocal();
        addTearDown(local.dispose);
        final remote = CookieSignInRemote();

        await selectedAccountSignInError(_auth(local, remote));

        expect(remote.sessionSignIns, 1);
        expect(
          await local.isSessionAccount(selectedAccountId),
          isFalse,
          reason:
              'Alice cannot reuse a session marker for Boris on the next tap',
        );
        expect(await local.getAccountById(cookieAccountId), isNotNull);
        expect(await local.isSessionAccount(cookieAccountId), isTrue);
        expect(await local.getAccountById(unrelatedAccountId), isNotNull);
        expect(
          await local.getSeedByAccountId(unrelatedAccountId),
          unrelatedAccountSeed,
        );
      },
    );

    test(
      'a saved account without a usable seed leaves no cookie authentication '
      'after a mismatched sign-in',
      () async {
        final local = CookieSignInLocal(selectedHasSession: false);
        addTearDown(local.dispose);
        final remote = CookieSignInRemote();

        await selectedAccountSignInError(_auth(local, remote));

        expect(remote.sessionSignIns, 1);
        expect(
          remote.authenticatedAccountId,
          isNull,
          reason:
              'the web cookie preference must be undone before reporting '
              'that the selected account needs another sign-in',
        );
        expect(await local.getCurrentAccountId(), isNot(selectedAccountId));
      },
    );

    test(
      'a mismatched saved session account asks to sign in again as that person '
      'in English and Russian',
      () async {
        final local = CookieSignInLocal(
          selectedSeed: selectedAccountSeed,
        );
        addTearDown(local.dispose);
        final remote = CookieSignInRemote();

        expect(await local.isSessionAccount(selectedAccountId), isTrue);
        expect(
          await local.getSeedByAccountId(selectedAccountId),
          selectedAccountSeed,
        );

        final error = await selectedAccountSignInError(_auth(local, remote));

        expect(remote.sessionSignIns, 1);
        expect(error, isA<AuthException>());
        final notice = error! as AuthException;
        expect(
          notice.toEn,
          selectedAccountSignInInstruction('en'),
          reason: 'expected "Sign in again as Alice", got "${notice.toEn}"',
        );
        expect(
          notice.toRu,
          selectedAccountSignInInstruction('ru'),
          reason:
              'RU recovery must name Alice and ask to sign in again: '
              '${notice.toRu}',
        );
      },
    );
  });
}
