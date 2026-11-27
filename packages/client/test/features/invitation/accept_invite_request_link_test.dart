import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/invitation/ui/bloc/accept_invite_cubit.dart';
import 'package:tentura/features/invitation/ui/screen/accept_invite_screen.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../data/service/_session_account_test_harness.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _code = 'I806d29daebbe';
const _requestId = 'B000000000042';
const _title = 'Fix the bike';
const _previewPath = '/api/v2/invite/$_code/preview';
const _acceptPath = '/api/v2/invite/$_code/accept-as-existing';

void main() {
  testWidgets('accept-invite links preview the attached Request and plain '
      'links still accept a contact invitation', (tester) async {
    await _openLink(tester, requestId: null, (wire, effects) async {
      expect(wire.previews.single.path, _previewPath);
      expect(wire.previews.single.queryParameters, isEmpty);
      expect(find.text('Vadim'), findsOneWidget);
      expect(find.text(_title), findsNothing);

      await tester.tap(find.text(lookupL10n(const Locale('en')).buttonYes));
      await _pumpPage(tester);
      expect(wire.accepts.map((uri) => uri.path), [_acceptPath]);
      expect(effects.emitted.whereType<ShowError>(), isEmpty);
      expect(
        effects.emitted.whereType<NavigateReplace>().map((e) => e.target),
        [NavigateReplaceTarget.home],
      );
    });

    await _openLink(tester, requestId: _requestId, (wire, effects) async {
      expect(wire.previews.single.path, _previewPath);
      expect(
        wire.previews.single.queryParameters,
        {'r': _requestId},
        reason: 'The preview receives the Request id from the opened URL',
      );
      expect(find.text(_title), findsOneWidget);
      expect(effects.emitted.whereType<ShowError>(), isEmpty);
    });
  });
}

Future<void> _openLink(
  WidgetTester tester,
  Future<void> Function(_InviteWire, FakeUiEffectPort) check, {
  required String? requestId,
}) async {
  final wire = _InviteWire();
  await http.runWithClient(() async {
    final remote = testRealtimeClient();
    final repository = InvitationRepository(remote);
    final effects = FakeUiEffectPort();
    final postJoin = PostJoinNavigationCubit();
    final auth = _SignedInAuth();
    final router = RootRouter(
      Logger('InviteLinkTest'),
      auth,
      _Settings(),
      postJoin,
    );
    final cubit = AcceptInviteCubit(repository, effects, postJoin);

    GetIt.I.pushNewScope(
      init: (scope) => scope.registerSingleton<AcceptInviteCubit>(cubit),
    );
    try {
      await remote.setSessionAuth();
      tester.binding.platformDispatcher.defaultRouteNameTestValue = Uri(
        path: '/accept-invite/$_code',
        queryParameters: requestId == null ? null : {'r': requestId},
      ).toString();
      await tester.pumpWidget(
        MaterialApp.router(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          builder: (context, child) => TenturaResponsiveScope(child: child!),
          routerConfig: router.config(
            deepLinkBuilder: router.deepLinkBuilder,
            deepLinkTransformer: router.deepLinkTransformer,
            includePrefixMatches: false,
          ),
        ),
      );
      await _pumpPage(tester);
      expect(
        tester.widget<AcceptInviteScreen>(find.byType(AcceptInviteScreen)).id,
        _code,
      );
      expect(tester.takeException(), isNull);
      expect(wire.previews, hasLength(1));
      await check(wire, effects);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue();
      await GetIt.I.popScope();
      router.dispose();
      if (!cubit.isClosed) await cubit.close();
      await auth.close();
      await repository.dispose();
      await remote.close();
    }
  }, () => MockClient(wire.respond));
}

class _SignedInAuth extends Cubit<AuthState> implements AuthCubit {
  _SignedInAuth()
    : super(
        AuthState(
          currentAccountId: 'Uviewer000001',
          updatedAt: DateTime.utc(2026),
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(introEnabled: false);
  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

class _InviteWire {
  final previews = <Uri>[];
  final accepts = <Uri>[];

  Future<http.Response> respond(http.Request request) async {
    final url = request.url;
    switch ((request.method, url.path)) {
      case ('POST', '/api/v2/session/access-token'):
        return _json({
          'subject': 'Uviewer000001',
          'access_token': 'invite-test-token',
          'expires_in': 3600,
        });
      case ('GET', _previewPath):
        previews.add(url);
        return _json({
          'codeStatus': 'available',
          'callerStatus': 'existing-user',
          'suggestedAction': 'accept-as-existing',
          'inviter': {'id': 'Uissuer000001', 'displayName': 'Vadim'},
          if (url.queryParameters['r'] == _requestId)
            'beacon': {
              'id': _requestId,
              'title': _title,
              'kind': 'request',
              'lapsed': false,
            },
        });
      case ('POST', _acceptPath):
        accepts.add(url);
        return http.Response('', 204);
      default:
        throw StateError('Unexpected HTTP request ${request.method} $url');
    }
  }
}

http.Response _json(Map<String, Object?> value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);

Future<void> _pumpPage(WidgetTester tester) async {
  for (var frame = 0; frame < 20; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
