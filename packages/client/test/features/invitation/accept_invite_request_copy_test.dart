import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/invitation/domain/entity/invite_preview.dart';
import 'package:tentura/features/invitation/domain/port/invitation_accept_port.dart';
import 'package:tentura/features/invitation/ui/bloc/accept_invite_cubit.dart';
import 'package:tentura/features/invitation/ui/screen/accept_invite_screen.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/mock_stack_router_scope.dart';
import '../../support/phone_surface.dart';
import '../../support/russian_closed_request_copy.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _en = Locale('en');
const _ru = Locale('ru');
const _inviter = 'Vadim';
const _request = 'Fix the roof';
const _code = 'I806d29daebbe';
const _closed =
    'Vadim invited you to «Fix the roof», but it has already closed.';
const _welcome =
    "You're still welcome on Tentura, and you're now connected with Vadim.";

void main() {
  testWidgets(
    'existing accounts see the outcome for plain, open and closed invites',
    (
      tester,
    ) async {
      final l10n = lookupL10n(_en);

      await _openInvite(tester, locale: _en);
      expect(find.text(l10n.confirmFriendAccept), findsOneWidget);
      expect(find.textContaining('has already closed'), findsNothing);

      await _openInvite(tester, locale: _en, lapsed: false);
      expect(find.text(l10n.inviteAcceptBeaconTitle), findsOneWidget);
      expect(find.text(l10n.inviteAcceptBeaconBody(_inviter)), findsOneWidget);
      expect(find.textContaining('has already closed'), findsNothing);

      await _openInvite(tester, locale: _en, lapsed: true);
      expect(find.textContaining(_welcome, findRichText: true), findsNothing);
      _expectPublicCopy();
      expect(find.text(_closed, findRichText: true), findsOneWidget);
    },
  );

  testWidgets('new users see the closed Request and connection before signup', (
    tester,
  ) async {
    final router = await _openInvite(
      tester,
      locale: _en,
      lapsed: true,
      signup: true,
    );

    _expectPublicCopy();
    expect(
      find.text('$_closed $_welcome', findRichText: true),
      findsOneWidget,
      reason: router.registrationState,
    );
    expect(router.registrationState, isNull);
  });

  for (final signup in [false, true]) {
    testWidgets(
      'a closed Request names the inviter and Request in Russian for '
      '${signup ? 'new users' : 'existing accounts'} on a phone',
      (tester) async {
        await usePhoneSurface(tester);
        final router = await _openInvite(
          tester,
          locale: _ru,
          lapsed: true,
          signup: signup,
        );

        _expectPublicCopy();
        expect(find.textContaining(_closed, findRichText: true), findsNothing);
        expect(find.textContaining(_welcome, findRichText: true), findsNothing);
        if (!signup) {
          expect(
            find.textContaining(russianConnectionCopy, findRichText: true),
            findsNothing,
          );
        }
        final copy = findRussianClosedRequestCopy(
          inviter: _inviter,
          title: _request,
          welcomesNewAccount: signup,
        );
        expect(
          copy,
          findsOneWidget,
          reason:
              router.registrationState ??
              'Expected Russian copy explaining that the Request has closed.',
        );
        expect(router.registrationState, isNull);
        expect(
          tester.renderObject<RenderParagraph>(copy).didExceedMaxLines,
          isFalse,
        );
      },
    );
  }
}

void _expectPublicCopy() {
  expect(
    find.textContaining(
      RegExp('phantom|фантом', caseSensitive: false),
      findRichText: true,
    ),
    findsNothing,
  );
}

Future<_SignupRouter> _openInvite(
  WidgetTester tester, {
  required Locale locale,
  bool? lapsed,
  bool signup = false,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  final cubit = AcceptInviteCubit.withPort(
    _PreviewPort(
      InvitePreview.fromJson({
        'codeStatus': 'available',
        'callerStatus': signup ? 'anonymous' : 'existing-user',
        'inviter': {'id': 'U000000000001', 'displayName': _inviter},
        if (lapsed != null)
          'beacon': {
            'id': 'B000000000001',
            'kind': 'request',
            'title': _request,
            'lapsed': lapsed,
          },
      }),
    ),
    effects: FakeUiEffectPort(),
    postJoinNavigation: PostJoinNavigationCubit(),
  );
  addTearDown(cubit.close);

  final router = _SignupRouter();
  await tester.pumpWidget(
    wrapWithMockStackRouter(
      MaterialApp(
        locale: locale,
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: BlocProvider.value(
          value: cubit,
          child: const AcceptInviteScreen(id: _code),
        ),
      ),
      router: router,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  expect(tester.takeException(), isNull);
  return router;
}

final class _PreviewPort implements InvitationAcceptPort {
  _PreviewPort(this.preview);

  final InvitePreview preview;

  @override
  Future<InvitePreview> fetchInvitePreview(String code) async => preview;

  @override
  Future<void> acceptExistingInvite(String code) async {}
}

final class _SignupRouter extends MockStackRouterScope {
  final _replacements = <String>[];

  String? get registrationState => _replacements.isEmpty
      ? null
      : 'The invite went straight to ${_replacements.join(', ')}.';

  @override
  Future<void> replaceAll(
    List<PageRouteInfo> routes, {
    OnNavigationFailure? onFailure,
    bool updateExistingRoutes = true,
  }) async {
    _replacements.addAll(routes.map((route) => route.routeName));
  }
}
