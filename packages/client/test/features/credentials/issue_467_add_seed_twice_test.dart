import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/credentials/data/repository/credentials_repository.dart';
import 'package:tentura/features/credentials/domain/entity/credential_entity.dart';
import 'package:tentura/features/credentials/domain/entity/credential_types.dart';
import 'package:tentura/features/credentials/domain/use_case/credentials_case.dart';
import 'package:tentura/features/credentials/ui/bloc/credentials_cubit.dart';
import 'package:tentura/ui/dialog/show_seed_dialog.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';

import '../auth/auth_test_helpers.dart';

// #467: under "Add sign-in method", tapping "Recovery seed" minted a brand new
// seed credential on every tap, with no word that the account already had
// one. Two taps left two seed rows and the person could not tell which one
// they had saved. With a seed already on the account, the tap must ask first
// (a dialog) and mint nothing until the person confirms; Cancel mints nothing.

/// Server stand-in: every linkSeed adds one more ed25519 credential, the way
/// POST /accounts/me/credentials does.
class _CountingCredentialsRepository extends Fake
    implements CredentialsRepository {
  _CountingCredentialsRepository(this.credentials);

  final List<CredentialEntity> credentials;
  int linkSeedCalls = 0;

  @override
  Future<List<CredentialEntity>> fetchCredentials() async =>
      List.of(credentials);

  @override
  Future<String> linkSeed() async {
    linkSeedCalls++;
    credentials.add(
      CredentialEntity(
        id: 'minted-$linkSeedCalls',
        type: CredentialTypes.ed25519Device,
        identifier: 'MINTEDPUBKEY000$linkSeedCalls',
      ),
    );
    return 'fresh-seed-$linkSeedCalls';
  }
}

class _NoopEffects implements UiEffectPort {
  @override
  Stream<UiEffect> get effects => const Stream.empty();

  @override
  void emit(UiEffect effect) {}
}

class _UnusedPlatform extends Fake implements PlatformRepositoryPort {}

class _TestRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: CredentialsRoute.page, initial: true),
  ];
}

const _existingSeed = CredentialEntity(
  id: 'seed-1',
  type: CredentialTypes.ed25519Device,
  identifier: 'EXISTINGPUBKEY0000000000',
);

const _email = CredentialEntity(
  id: 'email-1',
  type: CredentialTypes.emailOtp,
  identifier: 'vadim@example.com',
);

final _l10n = L10nEn();

Future<_CountingCredentialsRepository> _pumpScreen(
  WidgetTester tester,
  List<CredentialEntity> initial,
) async {
  // Compact width: HomeRailFrame then returns the screen unchanged.
  await tester.binding.setSurfaceSize(const Size(400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final repository = _CountingCredentialsRepository(List.of(initial));
  final case_ = CredentialsCase(
    repository,
    EmptyAuthLocal(),
    env: const Env(),
    logger: Logger('test'),
  );
  GetIt.I.registerFactory<CredentialsCubit>(
    () => CredentialsCubit(case_, _UnusedPlatform(), _NoopEffects()),
  );
  addTearDown(GetIt.I.reset);

  final router = _TestRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      builder: (context, child) =>
          TenturaResponsiveScope(child: child ?? const SizedBox.shrink()),
      routerConfig: router.config(),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

/// The "Recovery seed" row under "Add sign-in method" (the tappable one; the
/// existing seed row in "Your sign-in methods" has no onTap).
Finder _addSeedTile() {
  final tiles = find
      .widgetWithText(TenturaMenuTile, _l10n.credentialRecoverySeed)
      .evaluate()
      .where((e) => (e.widget as TenturaMenuTile).onTap != null)
      .toList();
  expect(
    tiles,
    hasLength(1),
    reason: 'expected one tappable "Recovery seed" row under Add',
  );
  return find.byWidget(tiles.single.widget);
}

Finder _dialogButton({required bool cancel}) {
  final buttons = find
      .descendant(
        of: find.byType(Dialog),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      )
      .evaluate()
      .where((e) {
        final hasCancelText = find
            .descendant(
              of: find.byWidget(e.widget),
              matching: find.text(_l10n.buttonCancel),
            )
            .evaluate()
            .isNotEmpty;
        return cancel ? hasCancelText : !hasCancelText;
      })
      .toList();
  expect(buttons, hasLength(1), reason: 'dialog needs one Cancel and one go');
  return find.byWidget(buttons.single.widget);
}

void main() {
  group('Add > Recovery seed with a seed already on the account (#467)', () {
    testWidgets('the tap asks first and mints nothing yet', (tester) async {
      final repository = await _pumpScreen(tester, [_existingSeed, _email]);

      await tester.tap(_addSeedTile());
      await tester.pumpAndSettle();

      expect(
        repository.linkSeedCalls,
        0,
        reason: 'a second seed was minted silently on the first tap',
      );
      expect(find.byType(ShowSeedDialog), findsNothing);
      expect(
        find.byType(Dialog),
        findsOneWidget,
        reason: 'the person must be asked before another seed is made',
      );
    });

    testWidgets('Cancel on that question mints nothing and leaves one seed '
        'row', (tester) async {
      final repository = await _pumpScreen(tester, [_existingSeed, _email]);

      await tester.tap(_addSeedTile());
      await tester.pumpAndSettle();
      await tester.tap(_dialogButton(cancel: true));
      await tester.pumpAndSettle();

      expect(repository.linkSeedCalls, 0);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(ShowSeedDialog), findsNothing);
      // One seed row in "Your sign-in methods" (+ the Add row).
      final seedRows = find
          .widgetWithText(TenturaMenuTile, _l10n.credentialRecoverySeed)
          .evaluate()
          .where((e) => (e.widget as TenturaMenuTile).onTap == null);
      expect(seedRows, hasLength(1));
    });

    testWidgets('confirming makes exactly one new seed and shows it', (
      tester,
    ) async {
      final repository = await _pumpScreen(tester, [_existingSeed, _email]);

      await tester.tap(_addSeedTile());
      await tester.pumpAndSettle();
      expect(repository.linkSeedCalls, 0);

      await tester.tap(_dialogButton(cancel: false));
      await tester.pumpAndSettle();

      expect(repository.linkSeedCalls, 1);
      expect(find.byType(ShowSeedDialog), findsOneWidget);
    });
  });

  group('Add > Recovery seed with no seed yet (#467 guard)', () {
    testWidgets('the first seed is still made on one tap and shown', (
      tester,
    ) async {
      final repository = await _pumpScreen(tester, [_email]);

      await tester.tap(_addSeedTile());
      await tester.pumpAndSettle();

      expect(repository.linkSeedCalls, 1);
      expect(find.byType(ShowSeedDialog), findsOneWidget);
    });
  });
}
