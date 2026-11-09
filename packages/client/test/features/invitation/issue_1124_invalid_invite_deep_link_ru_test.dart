// #1124: `/invite/<bad>` must reach accept-invite (not Requests silently) and
// show invalid-code feedback. Deep-link transform + AcceptInviteScreen path.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/invite_deep_link.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/invitation/ui/bloc/accept_invite_cubit.dart';
import 'package:tentura/features/invitation/ui/screen/accept_invite_screen.dart';
import 'package:tentura/ui/effect/ui_effect_handler.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/fake_app_navigator.dart';
import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'accept_invite_cubit_test.dart' show FakeInvitationAcceptPort;

Future<void> _pumpInvalidInviteFromDeepLink(
  WidgetTester tester, {
  required String inviteId,
}) async {
  final effects = FakeUiEffectPort();
  final cubit = AcceptInviteCubit.withPort(
    FakeInvitationAcceptPort(),
    effects: effects,
    postJoinNavigation: PostJoinNavigationCubit(),
  );
  addTearDown(cubit.close);

  final getIt = GetIt.I;
  registerFakeAppNavigator();
  if (!getIt.isRegistered<Logger>()) {
    getIt.registerSingleton<Logger>(Logger('issue-1124-invite'));
  }

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      builder: (_, child) => TenturaResponsiveScope(child: child!),
      home: Scaffold(
        body: UiEffectHandler(
          effects: effects,
          child: BlocProvider<AcceptInviteCubit>.value(
            value: cubit,
            child: AcceptInviteScreen(id: inviteId),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets(
    '#/invite/BADCODE123 signed in shows invalid-code copy at 375×667 RU',
    (tester) async {
      await usePhoneSurface(tester);

      const rawDeepLink = '/invite/BADCODE123';
      final transformed = transformInviteDeepLink(
        uri: Uri.parse(rawDeepLink),
        isAuthenticated: true,
      );
      expect(transformed.path, '$kPathAcceptInvite/BADCODE123');
      expect(
        transformed.queryParameters[kQueryIsDeepLink],
        'true',
      );

      await _pumpInvalidInviteFromDeepLink(
        tester,
        inviteId: transformed.pathSegments.last,
      );

      expect(find.byType(SnackBar), findsOneWidget);
      final snackCopy = find
          .descendant(
            of: find.byType(SnackBar),
            matching: find.byType(RichText),
          )
          .evaluate()
          .map((e) => (e.widget as RichText).text.toPlainText())
          .join(' ');
      expect(
        snackCopy,
        contains('Этот код приглашения недействителен.'),
      );
      expect(tester.takeException(), isNull);

      final snackBar = tester.getRect(find.byType(SnackBar));
      expect(snackBar.left, greaterThanOrEqualTo(0));
      expect(snackBar.right, lessThanOrEqualTo(kPhoneSurface.width));
    },
  );
}
