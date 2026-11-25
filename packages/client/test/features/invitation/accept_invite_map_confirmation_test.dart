import 'dart:convert';

import 'package:flutter/material.dart';
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
import 'package:tentura/features/invitation/ui/message/accept_invite_messages.dart';
import 'package:tentura/features/invitation/ui/screen/accept_invite_screen.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_handler.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../data/service/_session_account_test_harness.dart';
import '../../support/fake_app_navigator.dart';
import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _code = 'Iabc123';
const _invitePath = '/api/v2/invite/$_code';
const _aliceConfirmation = "You're on Alice's map.";
final _internalTerms = RegExp(
  'phantom|фантом|placeholder',
  caseSensitive: false,
);

void main() {
  test('preview keeps the map invite flag and defaults it to false', () {
    final flags = [
      for (final flag in [true, null, false])
        _mapInviteFlag(
          InvitePreview.fromJson(_previewJson(phantomInvite: flag)),
        ),
    ];

    expect(
      flags,
      [true, false, false],
      reason:
          'The parsed preview exposes phantomInvite for true, omitted, '
          'and false wire values.',
    );
  });

  test(
    'an existing account sees the confirmation for its invite outcome',
    () async {
      for (final (server, expectedMessage, expectedEnglish) in [
        (
          _InviteServer(
            _previewJson(callerStatus: 'already-friends', phantomInvite: false),
          ),
          isA<InviteAlreadyFriendsMessage>(),
          'You are already connected with this person.',
        ),
        (
          _InviteServer(_previewJson(phantomInvite: false)),
          isA<InviteAcceptedMessage>(),
          'Invitation accepted.',
        ),
        (
          _InviteServer(_previewJson(phantomInvite: true), acceptStatus: 404),
          isA<InviteNoLongerValidMessage>(),
          'This invite is no longer valid.',
        ),
      ]) {
        final message = await _acceptThroughRepository(server);
        expect(message.message, expectedMessage);
        expect(message.message.toEn, expectedEnglish);
      }

      const inviterNames = ['Alice', 'Alice from the garden'];
      final confirmations = [
        for (final name in inviterNames)
          await _acceptThroughRepository(
            _InviteServer(_previewJson(phantomInvite: true, inviterName: name)),
          ),
      ];
      expect(
        confirmations.map((effect) => effect.message.toEn),
        [_aliceConfirmation, "You're on Alice from the garden's map."],
      );
      for (final (index, name) in inviterNames.indexed) {
        final message = confirmations[index].message;
        expect(message, isNot(isA<InviteAcceptedMessage>()));
        expect(message, isNot(isA<InviteAlreadyFriendsMessage>()));
        expect(message.toRu, _russianMapConfirmation(name));
        expect(message.toEn, isNot(matches(_internalTerms)));
        expect(message.toRu, isNot(matches(_internalTerms)));
      }
    },
  );

  for (final (locale, language) in [
    (const Locale('en'), 'English'),
    (const Locale('ru'), 'Russian'),
  ]) {
    testWidgets(
      'accepting an invitation to Alice’s map shows the $language snackbar',
      (tester) async {
        await usePhoneSurface(tester);
        final navigator = registerFakeAppNavigator();
        final server = _InviteServer(_previewJson(phantomInvite: true));
        final effects = FakeUiEffectPort();

        await http.runWithClient(() async {
          final cubit = await _makeCubit(effects);
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              theme: TenturaTheme.light(),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              builder: (context, child) => UiEffectHandler(
                effects: effects,
                child: child!,
              ),
              home: BlocProvider.value(
                value: cubit,
                child: const AcceptInviteScreen(id: _code),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));

          final dialog = find.byType(InvitationAcceptDialog);
          expect(dialog, findsOneWidget);
          expect(
            find.descendant(of: dialog, matching: find.text('Alice')),
            findsOneWidget,
          );
          expect(server.acceptRequests, isEmpty);
          expect(find.byType(SnackBar), findsNothing);

          final accept = find.descendant(
            of: dialog,
            matching: find.widgetWithText(
              TextButton,
              lookupL10n(locale).buttonYes,
            ),
          );
          expect(accept.hitTestable(), findsOneWidget);
          await tester.tap(accept);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));

          expect(server.acceptRequests, [
            'POST $_invitePath/accept-as-existing',
          ]);
          expect(navigator.intents, [const NavIntent('resetToHome')]);
          expect(dialog, findsNothing);
          expect(tester.takeException(), isNull);

          final snackbar = find.byType(SnackBar);
          expect(snackbar, findsOneWidget);
          final snackbarText = tester
              .widgetList<RichText>(
                find.descendant(of: snackbar, matching: find.byType(RichText)),
              )
              .map((text) => text.text.toPlainText());
          expect(
            snackbarText,
            contains(
              locale.languageCode == 'en'
                  ? _aliceConfirmation
                  : _russianMapConfirmation('Alice'),
            ),
          );
          expect(snackbarText, everyElement(isNot(matches(_internalTerms))));
        }, server.client);
      },
    );
  }
}

// Read the new public field without a compile-time dependency on its addition.
// Missing API is an assertion mismatch, distinct from a legitimate false value.
bool? _mapInviteFlag(InvitePreview preview) {
  try {
    return (preview as dynamic).phantomInvite as bool?;
    // The baseline lacks the getter. Treat its absence as a missing value.
    // ignore: avoid_catching_errors
  } on NoSuchMethodError {
    return null;
  }
}

Matcher _russianMapConfirmation(String name) => allOf(
  contains(name),
  matches(RegExp(r'(?:^|[^\p{L}])карте(?!\p{L})', unicode: true)),
);

Map<String, Object?> _previewJson({
  String callerStatus = 'existing-user',
  bool? phantomInvite,
  String inviterName = 'Alice',
}) => {
  'codeStatus': 'available',
  'callerStatus': callerStatus,
  'phantomInvite': ?phantomInvite,
  'inviter': {'id': 'U1', 'displayName': inviterName},
};

Future<AcceptInviteCubit> _makeCubit(UiEffectPort effects) async {
  final remote = testRealtimeClient();
  final repository = InvitationRepository(remote);
  final postJoin = PostJoinNavigationCubit();
  final cubit = AcceptInviteCubit(repository, effects, postJoin);
  addTearDown(remote.close);
  addTearDown(repository.dispose);
  addTearDown(cubit.close);
  await remote.setSessionAuth();
  return cubit;
}

Future<ShowMessage> _acceptThroughRepository(
  _InviteServer server,
) => http.runWithClient(() async {
  final effects = FakeUiEffectPort();
  final cubit = await _makeCubit(effects);
  await cubit.start(_code);
  final callerStatus = server.preview['callerStatus'];
  expect(
    server.acceptRequests,
    isEmpty,
    reason: 'Opening a $callerStatus preview must not send an accept request.',
  );

  if (callerStatus == 'existing-user') {
    final inviter = server.preview['inviter']! as Map<String, String>;
    expect(cubit.state.needsConfirmation, isTrue);
    expect(
      cubit.state.pendingInviter,
      Profile(id: 'U1', displayName: inviter['displayName']!),
    );
    expect(effects.emitted, isEmpty);
    await cubit.confirmAccept();
    expect(server.acceptRequests, ['POST $_invitePath/accept-as-existing']);
  }

  // Already-connected accounts finish in start(); existing accounts
  // finish after confirmAccept(). Both routes must return home.
  expect(
    cubit.state.status,
    isA<StateIsSuccess>(),
    reason: 'The $callerStatus invite flow must finish successfully.',
  );
  expect(cubit.state.pendingInviter, isNull);
  expect(
    effects.emitted,
    [
      isA<ShowMessage>(),
      isA<NavigateReplace>().having(
        (effect) => effect.target,
        'target',
        NavigateReplaceTarget.home,
      ),
    ],
    reason:
        'The $callerStatus invite flow must show one message and return home.',
  );
  return effects.emitted.whereType<ShowMessage>().single;
}, server.client);

final class _InviteServer {
  _InviteServer(this.preview, {this.acceptStatus = 200});

  final Map<String, Object?> preview;
  final int acceptStatus;
  final acceptRequests = <String>[];

  MockClient client() => MockClient((request) async {
    final path = request.url.path;
    if (path == '/api/v2/session/access-token') {
      expect(request.method, 'POST');
      return _response({
        'subject': 'Uviewer000001',
        'access_token': 'test-token',
        'expires_in': 3600,
      });
    }
    expect(request.headers['Authorization'], 'Bearer test-token');
    if (path == '$_invitePath/preview') {
      expect(request.method, 'GET');
      return _response(preview);
    }
    if (path == '$_invitePath/accept-as-existing') {
      acceptRequests.add('${request.method} $path');
      return acceptStatus == 200
          ? _response({'ok': true, 'requestLapsed': false})
          : _response({'code': 'id_not_found'}, status: acceptStatus);
    }
    fail('Unexpected request: ${request.method} $path');
  });

  http.Response _response(Map<String, Object?> body, {int status = 200}) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
}
