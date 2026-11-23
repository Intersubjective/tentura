import 'dart:convert';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/invitation/domain/entity/invite_preview.dart';
import 'package:tentura/features/invitation/ui/bloc/accept_invite_cubit.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_accept_dialog.dart';
import 'package:tentura/features/invitation/ui/screen/accept_invite_screen.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../data/service/_session_account_test_harness.dart';
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
const _accessOnlyEn =
    'Accepting only gives you access to this request and adds it to your Activity.';
const _accessOnlyRu =
    'Принятие приглашения даст вам доступ только к этому запросу '
    'и добавит его в «Активность».';

void main() {
  testWidgets(
    'existing accounts get Request access only for open invites in English',
    (
      tester,
    ) async {
      final l10n = lookupL10n(_en);

      await _openInvite(tester, locale: _en);
      expect(find.text('Accept friend invitation?'), findsOneWidget);
      expect(find.textContaining('has already closed'), findsNothing);

      await _openInvite(tester, locale: _en, lapsed: true);
      expect(find.textContaining(_welcome, findRichText: true), findsNothing);
      _expectPublicCopy();
      expect(find.text(_closed, findRichText: true), findsOneWidget);

      await _showOpenRequestSignupDialog(tester);
      expect(
        find.text(
          'Accepting connects you with Vadim and adds this request to your Activity.',
        ),
        findsOneWidget,
      );
      expect(find.text(_accessOnlyEn), findsNothing);

      await _openInvite(tester, locale: _en, lapsed: false);
      expect(find.text(l10n.inviteAcceptBeaconTitle), findsOneWidget);
      expect(find.text(_request), findsOneWidget);
      expect(find.textContaining('has already closed'), findsNothing);
      _expectAccessOnlyDialog(tester, _accessOnlyEn, 'friend|connects? you');
    },
  );

  testWidgets(
    'existing accounts get Request access only with readable Russian copy on a phone',
    (tester) async {
      await usePhoneSurface(tester);
      await _openInvite(tester, locale: _ru, lapsed: false);

      expect(find.text(_request), findsOneWidget);
      final l10n = lookupL10n(_ru);
      for (final label in [l10n.buttonYes, l10n.buttonCancel]) {
        expect(
          find.widgetWithText(TextButton, label).hitTestable(),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
      final body = _expectAccessOnlyDialog(
        tester,
        _accessOnlyRu,
        'друз|свяж|в свою сеть|на связи',
      );
      expect(
        tester.renderObject<RenderParagraph>(body).didExceedMaxLines,
        isFalse,
      );
    },
  );

  test(
    'existing accounts get Request access only in both shipped translations',
    () {
      final english = _arb('en');
      final russian = _arb('ru');
      expect(
        english.keys.where(
          (key) =>
              english[key] == _accessOnlyEn && russian[key] == _accessOnlyRu,
        ),
        isNotEmpty,
        reason:
            'The exact English and Russian access-only messages share an ARB key.',
      );
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

Map<String, dynamic> _arb(String language) =>
    jsonDecode(File('l10n/app_$language.arb').readAsStringSync())
        as Map<String, dynamic>;

Finder _expectAccessOnlyDialog(
  WidgetTester tester,
  String expectedCopy,
  String friendshipPattern,
) {
  final dialog = find.byType(InvitationAcceptDialog);
  expect(dialog, findsOneWidget);
  final text = find.descendant(of: dialog, matching: find.byType(Text));
  final lines = tester
      .widgetList<Text>(text)
      .map(
        (widget) => widget.data ?? widget.textSpan!.toPlainText(),
      );
  expect(lines, contains(expectedCopy));
  expect(
    lines,
    everyElement(
      isNot(matches(RegExp(friendshipPattern, caseSensitive: false))),
    ),
  );
  return find.descendant(of: dialog, matching: find.text(expectedCopy));
}

Future<void> _showOpenRequestSignupDialog(WidgetTester tester) async {
  const open = 'Review invitation';
  await tester.pumpWidget(
    MaterialApp(
      locale: _en,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => InvitationAcceptDialog.show(
              context,
              profile: const Profile(
                id: 'U000000000001',
                displayName: _inviter,
              ),
              beacon: InvitePreview.fromJson(
                _preview(lapsed: false, signup: true),
              ).beacon,
              signup: true,
            ),
            child: const Text(open),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text(open));
  await tester.pumpAndSettle();
}

Map<String, Object?> _preview({required bool? lapsed, required bool signup}) =>
    {
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
    };

Future<_SignupRouter> _openInvite(
  WidgetTester tester, {
  required Locale locale,
  bool? lapsed,
  bool signup = false,
}) => http.runWithClient(
  () async {
    await tester.pumpWidget(const SizedBox.shrink());
    final remote = testRealtimeClient();
    final repository = InvitationRepository(remote);
    addTearDown(remote.close);
    addTearDown(repository.dispose);
    await remote.setSessionAuth();
    final cubit = AcceptInviteCubit.withPort(
      repository,
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
  },
  () => MockClient((request) async {
    final Map<String, Object?> body;
    if (request.url.path == '/api/v2/session/access-token') {
      expect(request.method, 'POST');
      body = {
        'subject': 'Uviewer000001',
        'access_token': 'test-token',
        'expires_in': 3600,
      };
    } else {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v2/invite/$_code/preview');
      expect(request.headers['Authorization'], 'Bearer test-token');
      body = _preview(lapsed: lapsed, signup: signup);
    }
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
  }),
);

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
