// Real web secure storage (flutter_secure_storage_web: localStorage +
// WebCrypto) holding values encrypted under a different AES key — what two
// tabs leave behind when each generated its own key. Reading them makes
// WebCrypto reject with a DOMException 'OperationError'.
//
//   * Cold boot must reach the app; the account whose seed cannot be
//     decrypted stays listed and is shown as needing sign-in again; the
//     ciphertexts stay in localStorage byte-for-byte. On web a signed-out
//     user has no in-app page at '/' (the router sends them to the static
//     landing, and QA mode suppresses that redirect), so this checks the
//     auth state the Recover screen renders from; the screen's message is
//     covered by test/features/auth/unreadable_seed_recovery_surface_test.dart.
//   * Request creation must work while secure storage holds an undecryptable
//     'beacon_create_op' (the command id no longer lives there), and that
//     entry is left as it was.
//
// Run: TENTURA_WEB_E2E_WASM=1 ./scripts/run_client_integration_web_local.sh \
//        integration_test/undecryptable_secure_storage_boot_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/app/boot_failure_app.dart';
import 'package:tentura/data/service/local_secure_storage.dart';
import 'package:tentura/features/auth/domain/port/auth_remote_repository_port.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/main.dart' as app;

import '../test/support/browser/foreign_key_secure_storage.dart';
import 'support/e2e_test_helpers.dart';

bool _bootedPastAuth() =>
    GetIt.I.isRegistered<AuthCubit>() &&
    !GetIt.I<AuthCubit>().state.isBootstrapping;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('web: cold boot with an account seed encrypted under another '
      'key reaches the app, shows the account as needing sign-in again, '
      'and keeps the ciphertext', (tester) async {
    await launchApp(app.main);
    await pumpSettleBounded(tester);
    final fixture = await bootstrapFixture(
      runId: uniqueRunId('undecryptable-seed'),
    );
    await logout(tester);
    await loginAs(tester, fixture.authorEmail);
    // Let the signed-in app finish its post-login database work: the cold
    // boot below closes this instance's database, and a transaction still
    // opening then fails the test with ConnectionClosedException.
    await pumpSettleBounded(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 5)),
    );
    await pumpSettleBounded(tester);
    final accountId = fixture.authorUserId;
    final accountKey = 'Auth:Id:$accountId';

    // A seed account on this device whose seed (and the boot 'init' probe)
    // were written by another tab under its own AES key; no session cookie.
    await LocalSecureStorage().delete('Auth:Session:$accountId');
    final ciphertexts = await writeUnderForeignKey({
      accountKey: 'seed-written-by-another-tab',
      'init': 'init',
    });
    // Test cleanup only: later tests boot without these entries.
    addTearDown(
      () => Future.wait(ciphertexts.keys.map(LocalSecureStorage().delete)),
    );
    await GetIt.I<AuthRemoteRepositoryPort>().clearSessionCookie();

    // Cold boot.
    await launchApp(app.main);
    await pumpSettleBounded(tester);

    expect(
      find.byType(BootFailureApp),
      findsNothing,
      reason: 'an undecryptable secure-storage entry must not fail boot',
    );
    await pumpUntil(
      tester,
      _bootedPastAuth,
      timeout: const Duration(seconds: 60),
      label: 'cold boot reaches the app',
    );
    final state = GetIt.I<AuthCubit>().state;
    expect(
      state.accounts.map((a) => a.id),
      contains(accountId),
      reason: 'the account whose seed cannot be read stays listed',
    );
    expect(state.currentAccountId, isEmpty);
    expect(
      state.authRecoveryNeeded,
      isTrue,
      reason: 'the account is marked as needing sign-in again',
    );
    expect(
      state.authSeedUnreadable,
      isTrue,
      reason:
          'the seed-only account is shown with the message that its seed '
          'cannot be read',
    );

    for (final MapEntry(:key, :value) in ciphertexts.entries) {
      expect(
        rawSecureStorageItem(key),
        value,
        reason: '"$key" failed to decrypt and must be kept byte-for-byte',
      );
    }
  });

  testWidgets('web: a Request is created while secure storage holds an '
      "undecryptable 'beacon_create_op', and that entry is left as it was", (
    tester,
  ) async {
    await launchApp(app.main);
    await pumpSettleBounded(tester);
    final fixture = await bootstrapFixture(
      runId: uniqueRunId('undecryptable-create-op'),
    );
    final ciphertexts = await writeUnderForeignKey({
      'beacon_create_op': 'command-id-written-by-another-tab',
    });
    addTearDown(() => LocalSecureStorage().delete('beacon_create_op'));
    final title = uniqueRequestTitle('IT undecryptable create op');

    await logout(tester);
    await createAndForwardRequest(tester, fixture: fixture, title: title);

    await logout(tester);
    await loginAs(tester, fixture.helperEmail);
    await runE2eStep(
      'created Request reaches the recipient',
      () => openRequestFromInbox(tester, requestTitle: title),
    );
    expect(find.text(title), findsWidgets);
    expect(
      rawSecureStorageItem('beacon_create_op'),
      ciphertexts['beacon_create_op'],
      reason: 'the undecryptable entry is neither migrated nor touched',
    );
  });
}
