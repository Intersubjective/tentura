// #1079 / #1140: account menu — phone RU, profile / settings / sign out only.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/auth/domain/entity/account_entity.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/widget/home_account_avatar_button.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

final class _ProfileCubitFake extends Fake implements ProfileCubit {
  _ProfileCubitFake(this._state);

  final ProfileState _state;

  @override
  ProfileState get state => _state;

  @override
  Stream<ProfileState> get stream => const Stream.empty();

  @override
  bool get isClosed => false;

  @override
  Future<void> close() async {}
}

class _AuthFake extends Fake implements AuthCubit {
  _AuthFake(this._state);

  final AuthState _state;

  @override
  AuthState get state => _state;

  @override
  Stream<AuthState> get stream => const Stream.empty();

  @override
  bool get isClosed => false;

  @override
  Future<void> close() async {}
}

Future<void> _pumpMenu(
  WidgetTester tester, {
  required Profile profile,
  required AuthCubit auth,
  ProfileCubit? profileCubit,
}) async {
  await usePhoneSurface(tester);
  final mock =
      profileCubit ?? _ProfileCubitFake(ProfileState(profile: profile));
  final effects = FakeUiEffectPort();
  final screenCubit = ScreenCubit(effects);

  GetIt.I
    ..registerSingleton<ProfileCubit>(mock)
    ..registerSingleton<AuthCubit>(auth)
    ..registerSingleton<ScreenCubit>(screenCubit);
  addTearDown(GetIt.I.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: mock),
            BlocProvider<AuthCubit>.value(value: auth),
            BlocProvider<ScreenCubit>.value(value: screenCubit),
          ],
          child: const Center(
            child: HomeAccountAvatarButton(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final l10n = lookupL10n(const Locale('ru'));

  testWidgets(
    'RU phone: avatar menu shows view profile, settings, logout full text',
    (tester) async {
      const profile = Profile(
        id: 'Ucur',
        displayName:
            'Очень длинное имя для проверки переносов и отсутствия переполнения',
      );
      final auth = _AuthFake(
        AuthState(
          updatedAt: DateTime(2026),
          currentAccountId: 'Ucur',
          accounts: [
            AccountEntity(id: 'Ucur', displayName: profile.displayName),
          ],
        ),
      );
      await _pumpMenu(tester, profile: profile, auth: auth);

      await tester.tap(find.byKey(HomeAccountAvatarButton.buttonKey));
      await tester.pumpAndSettle();

      expect(find.text(l10n.accountMenuViewProfile), findsOneWidget);
      expect(find.text(l10n.labelSettings), findsOneWidget);
      expect(find.text(l10n.logout), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long-press opens the same menu as tap', (tester) async {
    const profile = Profile(id: 'U1', displayName: 'Я');
    final auth = _AuthFake(
      AuthState(
        updatedAt: DateTime(2026),
        currentAccountId: 'U1',
        accounts: [const AccountEntity(id: 'U1', displayName: 'Я')],
      ),
    );
    await _pumpMenu(tester, profile: profile, auth: auth);

    await tester.longPress(find.byKey(HomeAccountAvatarButton.buttonKey));
    await tester.pumpAndSettle();
    expect(find.text(l10n.labelSettings), findsOneWidget);
  });

  testWidgets('secondary tap opens the account menu', (tester) async {
    const profile = Profile(id: 'U1', displayName: 'Я');
    final auth = _AuthFake(
      AuthState(
        updatedAt: DateTime(2026),
        currentAccountId: 'U1',
        accounts: [const AccountEntity(id: 'U1', displayName: 'Я')],
      ),
    );
    await _pumpMenu(tester, profile: profile, auth: auth);

    final center = tester.getCenter(
      find.byKey(HomeAccountAvatarButton.buttonKey),
    );
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text(l10n.labelSettings), findsOneWidget);
  });

  testWidgets('logout opens confirm dialog', (tester) async {
    const profile = Profile(id: 'U1', displayName: 'Я');
    final auth = _AuthFake(
      AuthState(
        updatedAt: DateTime(2026),
        currentAccountId: 'U1',
        accounts: [const AccountEntity(id: 'U1', displayName: 'Я')],
      ),
    );
    await _pumpMenu(tester, profile: profile, auth: auth);

    await tester.tap(find.byKey(HomeAccountAvatarButton.buttonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.logout));
    await tester.pumpAndSettle();

    expect(find.text(l10n.logoutConfirmTitle), findsOneWidget);
  });

  testWidgets(
    'first tap opens menu with semantics enabled (web parity)',
    (tester) async {
      final semantics = tester.ensureSemantics();
      const profile = Profile(id: 'U1', displayName: 'Я');
      final auth = _AuthFake(
        AuthState(
          updatedAt: DateTime(2026),
          currentAccountId: 'U1',
          accounts: [const AccountEntity(id: 'U1', displayName: 'Я')],
        ),
      );
      await _pumpMenu(tester, profile: profile, auth: auth);

      await tester.tap(find.byKey(HomeAccountAvatarButton.buttonKey));
      await tester.pumpAndSettle();

      expect(find.text(l10n.accountMenuViewProfile), findsOneWidget);
      semantics.dispose();
    },
  );
}
