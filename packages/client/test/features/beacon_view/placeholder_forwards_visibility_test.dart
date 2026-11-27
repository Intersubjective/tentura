@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_people_surface.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/graphql_round_trip_server.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'request_open_round_trips_support.dart';

const _requestId = 'B000000000042';
const _sender = Profile(id: 'U000000000001', displayName: 'Sender');
const _author = Profile(id: 'U000000000002', displayName: 'Author');
const _member = Profile(id: 'U000000000003', displayName: 'Member');

void main() {
  for (final locale in const [Locale('en'), Locale('ru')]) {
    testWidgets(
      'only the sender sees pending and lapsed forwards to people without an account in ${locale.languageCode}',
      (tester) async {
        if (locale.languageCode == 'ru') await usePhoneSurface(tester);
        await tester.runAsync(() async {
          final row = _rowName(locale);
          // The same stale/mixed response is available in all three sessions.
          // Check both the author and an unrelated member before the positive
          // control proves that the fixture can populate the sender's fold.
          for (final viewer in [_author, _member]) {
            await _openForwards(tester, locale, viewer, () {
              expect(row, findsNothing);
              expect(_status(locale, lapsed: false), findsNothing);
              expect(_status(locale, lapsed: true), findsNothing);
            });
          }
          await _openForwards(tester, locale, _sender, () {
            expect(row, findsNWidgets(2));
            final pending = _status(locale, lapsed: false);
            final lapsed = _status(locale, lapsed: true);
            expect(pending, findsOneWidget);
            expect(lapsed, findsOneWidget);

            _expectBilingual(
              tester,
              locale,
              row.first,
              _suffixPattern('en'),
              _suffixPattern('ru'),
              onTemplate: (template) => template.replaceAll(
                RegExp(r'\{\w+\}'),
                'Vasya',
              ),
            );
            for (final (finder, expired) in [
              (pending, false),
              (lapsed, true),
            ]) {
              _expectBilingual(
                tester,
                locale,
                finder,
                _statusPattern('en', lapsed: expired),
                _statusPattern('ru', lapsed: expired),
              );
            }
            expect(tester.takeException(), isNull);
          });
        });
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
}

RegExp _suffixPattern(String language) => RegExp(
  language == 'ru'
      ? r'^(?:Vasya )?\(?(?:ещ[её] не в (?:Тентуре|Tentura)|ещ[её] нет в (?:Тентуре|Tentura))\)?$'
      : r'^(?:Vasya )?\(?not on Tentura yet\)?$',
  caseSensitive: false,
);

Finder _rowName(Locale locale) => find.textContaining(
  RegExp(
    locale.languageCode == 'ru'
        ? r'^Vasya \((?:ещ[её] не в|ещ[её] нет в) (?:Тентуре|Tentura)\)$'
        : r'^Vasya \(not on Tentura yet\)$',
    caseSensitive: false,
  ),
  findRichText: true,
);

RegExp _statusPattern(String language, {required bool lapsed}) => RegExp(
  switch ((language, lapsed)) {
    ('ru', false) =>
      r'^(?:ожидает(?: регистрации| вступления)?|в ожидании|ожидание)$',
    ('ru', true) =>
      r'^(?:ист[её]к(?:ла|ло)?|просрочен[ао]?|устарел[ао]?|недействителен|потерял[ао]? актуальность)$',
    (_, false) => r'^(?:pending|awaiting (?:signup|registration|joining))$',
    (_, true) => r'^(?:lapsed|expired|no longer valid)$',
  },
  caseSensitive: false,
);

Finder _status(Locale locale, {required bool lapsed}) => find.textContaining(
  _statusPattern(locale.languageCode, lapsed: lapsed),
  findRichText: true,
);

void _expectBilingual(
  WidgetTester tester,
  Locale locale,
  Finder finder,
  RegExp english,
  RegExp russian, {
  String Function(String)? onTemplate,
}) {
  final text = switch (tester.widget(finder)) {
    Text(:final data, :final textSpan) => data ?? textSpan!.toPlainText(),
    RichText(:final text) => text.toPlainText(),
    final widget => throw StateError('Unexpected label: $widget'),
  };
  final en = _readArb('en');
  final ru = _readArb('ru');
  final forbidden = RegExp('phantom|фантом|beacon|маяк', caseSensitive: false);
  expect(
    en.keys.any((key) {
      final a = en[key];
      final b = ru[key];
      if (a is! String || b is! String) return false;
      final enText = onTemplate?.call(a) ?? a;
      final ruText = onTemplate?.call(b) ?? b;
      final rendered = locale.languageCode == 'ru' ? ruText : enText;
      final variants = {
        rendered,
        if (onTemplate != null) ...{
          'Vasya $rendered',
          'Vasya ($rendered)',
          'Vasya (${rendered.toLowerCase()})',
        },
      };
      return english.hasMatch(enText) &&
          russian.hasMatch(ruText) &&
          !forbidden.hasMatch(enText) &&
          !forbidden.hasMatch(ruText) &&
          variants.contains(text);
    }),
    isTrue,
    reason: 'The displayed label «$text» has matching EN and RU catalog copy',
  );
}

Map<String, Object?> _readArb(String language) =>
    (jsonDecode(File('l10n/app_$language.arb').readAsStringSync()) as Map)
        .cast<String, Object?>();

Future<void> _openForwards(
  WidgetTester tester,
  Locale locale,
  Profile viewer,
  void Function() check,
) async {
  final server = _requestServer(viewer);
  await http.runWithClient(() async {
    final remote = RemoteApiService(
      const Env(),
      const WebSocketClientRealtimeSocketFactory(),
    );
    await remote.setSessionAuth();
    final realtime = buildTestRealtimeSync();
    final wired = buildWiredBeaconViewCase(remote, realtime);
    final effects = FakeUiEffectPort();
    final screen = ScreenCubit(effects);
    final profile = _ProfileCubit(viewer);
    final cubit = BeaconViewCubit(
      id: _requestId,
      myProfile: viewer,
      beaconViewCase: wired.viewCase,
      effects: effects,
    );
    const tick = Duration(milliseconds: 10);
    Future<void> settle() => server.drain(
      wait: () async {
        await Future<void>.delayed(tick);
        await tester.pump(tick);
      },
    );
    try {
      await settle();
      expect(cubit.state.beacon.id, _requestId);
      expect(cubit.state.beacon.title, 'Fix the bike');
      expect(cubit.state.loadError, isNull, reason: server.describe());
      expect(cubit.state.firstLoadDone, isTrue, reason: server.describe());
      await tester.pumpPeopleTagsWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: locale,
          home: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ScreenCubit>.value(value: screen),
                BlocProvider<ProfileCubit>.value(value: profile),
                BlocProvider<BeaconViewCubit>.value(value: cubit),
              ],
              child: Scaffold(
                body: BlocBuilder<BeaconViewCubit, BeaconViewState>(
                  bloc: cubit,
                  builder: (_, state) => BeaconPeopleSurface(
                    beaconViewCubit: cubit,
                    beaconState: state,
                    focusUserId: null,
                    peopleTabAttentionActive: false,
                    postBuddingEnabled: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await settle();
      final title = lookupL10n(locale).labelForwards;
      final fold = find.textContaining(
        RegExp('^${RegExp.escape(title)}(?: \\(\\d+\\))?\$'),
      );
      expect(fold, findsOneWidget);
      await tester.ensureVisible(fold);
      await tester.tap(fold);
      await settle();
      expect(tester.takeException(), isNull);
      expect(cubit.state.forwardsLoaded, isTrue, reason: server.describe());
      expect(
        server.calls.expand((call) => call.operationNames),
        contains('ForwardEdgesFetch'),
        reason: 'The opened fold loaded its forward data over GraphQL',
      );
      check();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      server.answerPending();
      await cubit.close();
      await screen.close();
      await profile.close();
      await realtime.port.dispose();
      await remote.close();
    }
  }, () => server.client);
}

GraphqlRoundTripServer _requestServer(Profile viewer) {
  final isAuthor = viewer.id == _author.id;
  return GraphqlRoundTripServer(
    viewerId: viewer.id,
    overrides: (type, field, _) => switch ((type, field)) {
      ('beacon', 'id') || ('v2_BeaconDisplayStatus', 'beaconId') => _requestId,
      ('beacon', 'title') => 'Fix the bike',
      ('beacon', 'kind') ||
      ('beacon', 'status') ||
      ('beacon', 'forward_policy') => 0,
      ('beacon', 'access_level') => isAuthor ? 0 : 1,
      ('beacon', 'access_reasons') => isAuthor ? 1 : 4,
      ('beacon', 'can_read_content') ||
      ('beacon', 'can_read_involvement') ||
      ('beacon', 'can_read_admitted_helpers') ||
      ('beacon', 'is_discoverable') => true,
      ('user', 'id') => _author.id,
      ('user', 'display_name') => _author.displayName,
      ('user', 'image') => null,
      // Proposed read seam for the pending-forward rows in plan §7. The
      // response deliberately keeps senderId on both rows across sessions
      // so a client that renders everything cannot pass the privacy check.
      ('query_root', 'beaconPendingForwards') ||
      ('v2_ConstellationField', 'pendingForwards') => _pendingForwards,
      _ => GraphqlRoundTripServer.auto,
    },
  );
}

final _pendingForwards = [
  for (final (id, phantomId, state) in [
    ('PF000000000001', 'PH000000000001', 'pending'),
    ('PF000000000002', 'PH000000000002', 'lapsed'),
  ])
    {
      '__typename': 'v2_PendingForward',
      'id': id,
      'beaconId': _requestId,
      'senderId': _sender.id,
      'phantomId': phantomId,
      'displayName': 'Vasya',
      'state': state,
    },
];

class _ProfileCubit extends Cubit<ProfileState> implements ProfileCubit {
  _ProfileCubit(Profile viewer) : super(ProfileState(profile: viewer));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
