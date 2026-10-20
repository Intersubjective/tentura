import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/auth/ui/screen/recover_screen.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';

class _FakeAuthCubit extends Fake implements AuthCubit {
  _FakeAuthCubit({this.authRecoveryNeeded = false});

  final bool authRecoveryNeeded;

  final recoveredSeeds = <String>[];

  @override
  AuthState get state => AuthState(
    updatedAt: DateTime.utc(2026),
    authRecoveryNeeded: authRecoveryNeeded,
  );

  @override
  Stream<AuthState> get stream => const Stream.empty();

  @override
  Future<void> recoverAndSignIn(String seed, {String? authAttemptId}) async {
    recoveredSeeds.add(seed);
  }
}

class _TestRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: RecoverRoute.page, initial: true),
  ];
}

Future<void> _pumpRecover(WidgetTester tester, _FakeAuthCubit cubit) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = _TestRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    BlocProvider<AuthCubit>.value(
      value: cubit,
      child: MaterialApp.router(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) =>
            TenturaResponsiveScope(child: child ?? const SizedBox.shrink()),
        routerConfig: router.config(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _recoverButton() =>
    find.widgetWithText(FilledButton, 'Recover', skipOffstage: false);

void main() {
  group('RecoverScreen (#490)', () {
    testWidgets('landing "Recover from seed" visit is titled '
        '"Recover your account" with no session-error block', (tester) async {
      await _pumpRecover(tester, _FakeAuthCubit());

      expect(find.text('Recover your account'), findsOneWidget);
      expect(find.text('Session recovery'), findsNothing);
      expect(find.text('Sign in again'), findsNothing);
      expect(
        find.text("We couldn't verify your session. Sign in again."),
        findsNothing,
      );
    });

    testWidgets('session-loss visit keeps the session recovery block '
        '(guard)', (tester) async {
      await _pumpRecover(tester, _FakeAuthCubit(authRecoveryNeeded: true));

      expect(find.text('Session recovery'), findsOneWidget);
      expect(find.text('Sign in again'), findsOneWidget);
    });

    testWidgets('camera does not start until "Scan QR" is tapped', (
      tester,
    ) async {
      await _pumpRecover(tester, _FakeAuthCubit());

      expect(find.byType(MobileScanner), findsNothing);
      expect(find.text('Scan QR'), findsOneWidget);
    });

    testWidgets('Recover is disabled until a seed is entered', (tester) async {
      final cubit = _FakeAuthCubit();
      await _pumpRecover(tester, cubit);

      expect(tester.widget<FilledButton>(_recoverButton()).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(tester.widget<FilledButton>(_recoverButton()).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '  some-seed  ');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(_recoverButton()).onPressed,
        isNotNull,
      );

      await tester.tap(_recoverButton());
      await tester.pump();
      expect(cubit.recoveredSeeds, ['some-seed']);
    });
  });

  group('recoverScannerErrorText (#490)', () {
    final l10n = L10nEn();

    test('no camera shows plain copy, not the browser exception', () {
      const error = MobileScannerException(
        errorCode: MobileScannerErrorCode.genericError,
        errorDetails: MobileScannerErrorDetails(
          message: 'NotFoundError: Requested device not found',
        ),
      );

      final text = recoverScannerErrorText(l10n, error);

      expect(text, l10n.recoverCameraNotFound);
      expect(text, contains('No camera found'));
      expect(text, isNot(contains('NotFoundError')));
    });

    test('blocked permission says so plainly', () {
      const error = MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );

      expect(recoverScannerErrorText(l10n, error), l10n.recoverCameraBlocked);
    });
  });

  group('AuthSeedIsWrongException copy (#490)', () {
    test('English is plain, with no "Auth error" prefix', () {
      const e = AuthSeedIsWrongException();
      expect(
        e.toEn,
        "That seed doesn't match an account. Check for missing characters.",
      );
    });

    test('Russian has no developer prefix either', () {
      const e = AuthSeedIsWrongException();
      expect(e.toRu, isNot(contains('Ошибка авторизации')));
      expect(e.toRu, contains('seed'));
    });
  });
}
