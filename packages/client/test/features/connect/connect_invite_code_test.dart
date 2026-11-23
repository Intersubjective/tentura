// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/connect/ui/widget/connect_bottom_sheet.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_accept_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../data/service/_session_account_test_harness.dart';
import '../../support/fake_app_navigator.dart';
import '../../support/phone_surface.dart';

const _viewer = 'U325f01f7d5b8';
const _inviter = 'U96e2e7582017';
const _code = 'I0fbceade7077';
const _request = 'B806d29daebbe';
const _requestTitle = 'Fix the roof';
const _previewPath = '/api/v2/invite/$_code/preview';
const _acceptPath = '/api/v2/invite/$_code/accept-as-existing';
const _launchLabel = 'Enter a code';
const _token = 'invite-test-token';

const _translations = [
  (
    locale: Locale('en'),
    search: 'Search',
    openTitle: 'Accept invite and request?',
    openBody:
        'Accepting only gives you access to this request and adds it to your Activity.',
    closedTitle: 'Request closed',
    closedBody:
        'Vadim invited you to «Fix the roof», but it has already closed.',
    friendTitle: 'Accept friend invitation?',
    friendAccepted: 'Invitation accepted.',
    yes: 'Yes',
    accept: 'Accept',
    cancel: 'Cancel',
    friendshipPattern: 'friend|connects? you|now connected',
  ),
  (
    locale: Locale('ru'),
    search: 'Поиск',
    openTitle: 'Принять приглашение и запрос?',
    openBody:
        'Принятие приглашения даст вам доступ только к этому запросу '
        'и добавит его в «Активность».',
    closedTitle: 'Запрос закрыт',
    closedBody:
        'Vadim пригласил вас в запрос «Fix the roof», но он уже закрыт.',
    friendTitle: 'Принять приглашение в друзья?',
    friendAccepted: 'Приглашение принято.',
    yes: 'Да',
    accept: 'Принять',
    cancel: 'Отмена',
    friendshipPattern: 'друз',
  ),
];

void main() {
  for (final copy in _translations) {
    group('Connect invite codes in ${copy.locale.languageCode}', () {
      for (final lapsed in [false, true]) {
        testWidgets(
          lapsed
              ? 'closed Request explains the closure and can be cancelled'
              : 'open Request explains access and can be cancelled',
          (tester) async {
            final wire = _InviteWire(previewLapsed: lapsed);
            final phone = copy.locale.languageCode == 'ru';
            if (phone) await usePhoneSurface(tester);
            await wire.run(tester, copy.locale, copy.search, (navigator) async {
              final title = _inDialog(
                lapsed ? copy.closedTitle : copy.openTitle,
              );
              final body = _inDialog(lapsed ? copy.closedBody : copy.openBody);
              final confirm = _inDialog(lapsed ? copy.accept : copy.yes);
              final cancel = _inDialog(copy.cancel);
              final dialogText = [
                title,
                body,
                if (!lapsed) _inDialog(_requestTitle),
                confirm,
                cancel,
              ];
              for (final label in dialogText) {
                expect(label.hitTestable(), findsOneWidget);
                if (phone) {
                  final bounds = tester.getRect(label);
                  expect(
                    (Offset.zero & kPhoneSurface).intersect(bounds),
                    bounds,
                  );
                  expect(
                    tester
                        .renderObject<RenderParagraph>(label)
                        .didExceedMaxLines,
                    isFalse,
                  );
                }
              }
              expect(
                _inDialog(RegExp(copy.friendshipPattern, caseSensitive: false)),
                findsNothing,
              );

              await _tapDialogAction(tester, copy.cancel);
              expect(find.byType(InvitationAcceptDialog), findsNothing);
              expect(wire.acceptedCodes, isEmpty);
              expect(navigator.intents, isEmpty);
            });
          },
        );
      }

      testWidgets('accepting an open Request opens the admitted Request once', (
        tester,
      ) async {
        final wire = _InviteWire(previewLapsed: false);
        await wire.run(tester, copy.locale, copy.search, (navigator) async {
          expect(wire.acceptedCodes, isEmpty);
          expect(navigator.intents, isEmpty);
          final expectedCopy = [copy.openTitle, _requestTitle, copy.openBody];
          final visibleCopy = [
            for (final text in expectedCopy)
              if (_inDialog(text).hitTestable().evaluate().length == 1) text,
          ];
          await _tapDialogAction(tester, copy.yes);

          expect(wire.acceptedCodes, [_code]);
          expect(
            navigator.named('openBeacon').map((intent) => intent.args['id']),
            [_request],
          );
          expect(navigator.named('openProfile'), isEmpty);
          expect(_inSnackBar('Invitation accepted!'), findsNothing);
          expect(visibleCopy, expectedCopy);
          expect(wire.previewRequests, contains(_previewPath));
          expect(wire.existingAcceptRequests, [_acceptPath]);
        });
      });

      for (final previewLapsed in [true, false]) {
        testWidgets(
          previewLapsed
              ? 'accepting a closed Request finishes without navigation or success copy'
              : 'a Request that closes during acceptance finishes without navigation or success copy',
          (tester) async {
            final wire = _InviteWire(
              previewLapsed: previewLapsed,
              acceptLapsed: true,
            );
            await wire.run(tester, copy.locale, copy.search, (navigator) async {
              await _tapDialogAction(
                tester,
                previewLapsed ? copy.accept : copy.yes,
              );

              expect(find.byType(InvitationAcceptDialog), findsNothing);
              expect(wire.acceptedCodes, [_code]);
              expect(navigator.intents, isEmpty);
              expect(
                _inSnackBar(
                  RegExp(
                    'Invitation accepted|Приглашение принято|'
                    'shared .* with you|поделил.* с вами',
                    caseSensitive: false,
                  ),
                ),
                findsNothing,
              );
              expect(wire.existingAcceptRequests, [_acceptPath]);
            });
          },
        );
      }

      testWidgets(
        'a plain invite opens the inviter and confirms in the locale',
        (
          tester,
        ) async {
          final wire = _InviteWire();
          await wire.run(tester, copy.locale, copy.search, (navigator) async {
            expect(_inDialog(copy.friendTitle).hitTestable(), findsOneWidget);
            await _tapDialogAction(tester, copy.yes);

            expect(wire.acceptedCodes, [_code]);
            expect(navigator.intents, [
              const NavIntent('openProfile', {'id': _inviter}),
            ]);
            expect(_inSnackBar('Invitation accepted!'), findsNothing);
            expect(
              _inSnackBar(copy.friendAccepted).hitTestable(),
              findsOneWidget,
            );
          });
        },
      );
    });
  }
}

Finder _inDialog(Pattern text) => find.descendant(
  of: find.byType(InvitationAcceptDialog),
  matching: _text(text),
);

Finder _inSnackBar(Pattern text) => find.descendant(
  of: find.byType(SnackBar),
  matching: _text(text),
);

Finder _text(Pattern text) => text is String
    ? find.text(text, findRichText: true)
    : find.textContaining(text, findRichText: true);

Future<void> _tapDialogAction(WidgetTester tester, String label) async {
  final action = _inDialog(label).hitTestable();
  expect(action, findsOneWidget, reason: 'The dialog offers $label.');
  await tester.tap(action);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

class _SignedInAuth extends Fake implements AuthCubit {
  @override
  AuthState get state =>
      AuthState(updatedAt: DateTime.utc(2026), currentAccountId: _viewer);
}

class _InviteWire {
  _InviteWire({this.previewLapsed, this.acceptLapsed = false});

  final bool? previewLapsed;
  final bool acceptLapsed;
  final previewRequests = <String>[];
  final existingAcceptRequests = <String>[];
  final acceptedCodes = <String>[];

  Future<void> run(
    WidgetTester tester,
    Locale locale,
    String searchLabel,
    Future<void> Function(FakeAppNavigator) verify,
  ) => http.runWithClient(
    () async {
      final remote = testRealtimeClient();
      final repository = InvitationRepository(remote);
      addTearDown(remote.close);
      addTearDown(repository.dispose);
      final navigator = registerFakeAppNavigator();
      GetIt.I
        ..registerSingleton<InvitationRepository>(repository)
        ..registerSingleton<AuthCubit>(_SignedInAuth())
        ..registerSingleton<Logger>(Logger('ConnectInviteTest'));
      addTearDown(GetIt.I.reset);
      await remote.setSessionAuth();

      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: TenturaTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => ConnectBottomSheet.show(context),
                child: const Text(_launchLabel),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text(_launchLabel));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), _code);
      await tester.tap(find.widgetWithText(FilledButton, searchLabel));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(InvitationAcceptDialog), findsOneWidget);
      await verify(navigator);
    },
    () => MockClient(_respond),
  );

  Future<http.Response> _respond(http.Request request) async {
    final path = request.url.path;
    if (path == '/api/v2/session/access-token') {
      expect(request.method, 'POST');
      return _json({
        'subject': _viewer,
        'access_token': _token,
        'expires_in': 3600,
      });
    }

    expect(request.headers['Authorization'], 'Bearer $_token');
    if (path == _previewPath) {
      expect(request.method, 'GET');
      previewRequests.add(path);
      return _json({
        'codeStatus': 'available',
        'callerStatus': 'existing-user',
        'suggestedAction': 'accept-as-existing',
        'inviter': {'id': _inviter, 'displayName': 'Vadim'},
        if (previewLapsed != null)
          'beacon': {
            'id': _request,
            'title': _requestTitle,
            'kind': 'request',
            'lapsed': previewLapsed,
          },
      });
    }
    if (path == _acceptPath) {
      expect(request.method, 'POST');
      existingAcceptRequests.add(path);
      acceptedCodes.add(_code);
      return _json({'ok': true, 'requestLapsed': acceptLapsed});
    }

    // The legacy GraphQL API returns the issuer and a consumption boolean.
    // A lapsed Request can still consume the invite without granting access.
    expect(path, endsWith('/graphql'));
    expect(request.method, 'POST');
    final operation = jsonDecode(request.body) as Map<String, dynamic>;
    final variables = operation['variables'] as Map<String, dynamic>;
    expect(variables, containsPair('id', _code));
    switch (operation['operationName']) {
      case 'InvitationById':
        return _json({
          'data': {
            '__typename': 'query_root',
            'invitationById': {
              '__typename': 'v2_Invitation',
              'id': _code,
              'created_at': '2026-01-01T00:00:00Z',
              'issuer': {
                '__typename': 'v2_user',
                'id': _inviter,
                'displayName': 'Vadim',
                'description': '',
                'is_mutual_friend': false,
                'trusts_viewer': false,
              },
            },
          },
        });
      case 'InvitationAccept':
        acceptedCodes.add(variables['id'] as String);
        return _json({
          'data': {'__typename': 'mutation_root', 'invitationAccept': true},
        });
      default:
        throw StateError(
          'Unexpected GraphQL operation: ${operation['operationName']}',
        );
    }
  }

  static http.Response _json(Map<String, Object?> value) => http.Response(
    jsonEncode(value),
    200,
    headers: {'content-type': 'application/json'},
  );
}
