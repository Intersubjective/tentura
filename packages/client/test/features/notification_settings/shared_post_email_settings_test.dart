@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/notification_settings/data/repository/notification_settings_repository.dart';
import 'package:tentura/features/notification_settings/ui/bloc/notification_settings_cubit.dart';
import 'package:tentura/features/notification_settings/ui/screen/notification_settings_screen.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

class _Router extends Mock implements StackRouter {
  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => false;
}

Future<SwitchListTile> _emailRow(
  WidgetTester tester,
  NotificationSettingsCubit cubit,
  String locale,
) async {
  final router = _Router();
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: RouterScope(
          controller: router,
          stateHash: 0,
          inheritableObserversBuilder: () => const [],
          child: StackRouterScope(
            controller: router,
            stateHash: 0,
            child: BlocProvider.value(
              value: cubit,
              child: const NotificationSettingsScreen(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
  final title = locale == 'en'
      ? 'Posts shared with me'
      : 'Посты, которыми поделились со мной';
  final l10n = L10n.of(
    tester.element(find.byType(NotificationSettingsScreen)),
  )!;
  final emailHeading = find.text(
    l10n.notificationSettingsEmail.toUpperCase(),
  );
  await tester.scrollUntilVisible(
    emailHeading,
    200,
    maxScrolls: 10,
  );
  await Scrollable.ensureVisible(
    tester.element(emailHeading),
  );
  await tester.pump();
  // The email section is now in view. If push also exposes this
  // category, its row precedes the email row in document order.
  final rows = find.widgetWithText(
    SwitchListTile,
    title,
    skipOffstage: false,
  );
  expect(
    rows,
    findsAtLeastNWidgets(1),
    reason:
        'Notification settings must expose a separate shared Post email switch',
  );
  return tester.widget<SwitchListTile>(rows.last);
}

void main() {
  for (final locale in ['en', 'ru']) {
    testWidgets(
      '$locale first-use server preferences show shared Post email enabled',
      (tester) async {
        await usePhoneSurface(tester);
        final response = await tester.runAsync(() async {
          final result = await Process.run(
            'dart',
            [
              'run',
              'test/support/notification_preferences_defaults_response.dart',
              locale,
            ],
            workingDirectory: '../server',
          ).timeout(const Duration(seconds: 45));
          expect(
            result.exitCode,
            0,
            reason:
                'The actual server default projection must execute: ${result.stderr}',
          );
          const prefix = 'NOTIFICATION_PREFERENCES_DEFAULTS ';
          final line = const LineSplitter()
              .convert(result.stdout as String)
              .singleWhere((line) => line.startsWith(prefix));
          return (jsonDecode(line.substring(prefix.length)) as Map)
              .cast<String, dynamic>();
        });
        final sent = <WireSent>[];
        await withRemoteWire({'NotificationPreferencesFetch': response!}, sent, (
          remote,
        ) async {
          final effects = FakeUiEffectPort();
          final cubit = NotificationSettingsCubit(
            repository: NotificationSettingsRepository(remote),
            effects: effects,
          );
          addTearDown(cubit.close);
          await tester.runAsync(cubit.fetch);
          expect(effects.emitted, isEmpty);
          expect(cubit.state.isLoading, isFalse);
          expect(sent.single.operationName, 'NotificationPreferencesFetch');
          final row = await _emailRow(tester, cubit, locale);
          expect(
            row.value,
            isTrue,
            reason:
                'First-use server defaults must display an enabled shared Post email switch',
          );
          expect(row.onChanged, isNotNull);
          expect(tester.takeException(), isNull);
        });
      },
    );
    for (final initiallyEnabled in [true, false]) {
      testWidgets(
        initiallyEnabled
            ? '$locale shared Post email is enabled on load and can be disabled independently'
            : '$locale shared Post email remains visible when opted out and can be enabled independently',
        (tester) async {
          await usePhoneSurface(tester);
          final sent = <WireSent>[];
          var savedEmail = <String>[
            'asksOfMe',
            'connections',
            'coordination',
            if (initiallyEnabled) 'postsSharedWithMe',
          ];
          Map<String, dynamic> preferences() => {
            '__typename': 'NotificationPreferences',
            'accountId': 'Uviewer000001',
            'pushCategories': ['asksOfMe', 'coordination'],
            'emailCategories': savedEmail,
            'mutedInAppEventClasses': <String>[],
            'quietHoursStart': null,
            'quietHoursEnd': null,
            'tzOffsetMinutes': 0,
            'emailDigest': 'daily',
            'snoozeUntil': null,
            'lockScreenSafe': false,
            'locale': locale,
          };
          await withRemoteWire(
            {},
            sent,
            (remote) async {
              final repository = NotificationSettingsRepository(remote);
              final effects = FakeUiEffectPort();
              final cubit = NotificationSettingsCubit(
                repository: repository,
                effects: effects,
              );
              addTearDown(cubit.close);
              await tester.runAsync(cubit.fetch);
              expect(cubit.state.isLoading, isFalse);
              expect(effects.emitted, isEmpty);
              expect(sent.single.operationName, 'NotificationPreferencesFetch');
              final row = await _emailRow(tester, cubit, locale);
              expect(
                row.value,
                initiallyEnabled,
                reason:
                    'A category absent from saved preferences is off; server defaults supply first-use opt-in',
              );
              expect(row.onChanged, isNotNull);
              // Invoke the settings control's public action. Browser touch/scroll
              // behavior is deliberately outside this structural widget test.
              await tester.runAsync(() async {
                row.onChanged!(!initiallyEnabled);
                for (
                  var i = 0;
                  i < 100 &&
                      !sent.any(
                        (r) =>
                            r.operationName == 'NotificationPreferencesUpdate',
                      );
                  i++
                ) {
                  await Future<void>.delayed(const Duration(milliseconds: 10));
                }
              });
              await tester.pump();
              final update = sent.singleWhere(
                (r) => r.operationName == 'NotificationPreferencesUpdate',
              );
              expect(
                update.variables['emailCategories'],
                unorderedEquals([
                  'asksOfMe',
                  'connections',
                  'coordination',
                  if (!initiallyEnabled) 'postsSharedWithMe',
                ]),
              );
              expect(
                update.variables['pushCategories'],
                unorderedEquals(['asksOfMe', 'coordination']),
              );
              expect(effects.emitted, isEmpty);
              // A fresh cubit fetches the saved transport response, proving the
              // option survives a reload rather than only an optimistic repaint.
              final reopened = NotificationSettingsCubit(
                repository: repository,
                effects: effects,
              );
              addTearDown(reopened.close);
              await tester.runAsync(reopened.fetch);
              expect(
                reopened.state.settings.emailCategories.map((c) => c.name),
                unorderedEquals([
                  'asksOfMe',
                  'connections',
                  'coordination',
                  if (!initiallyEnabled) 'postsSharedWithMe',
                ]),
              );
              expect(tester.takeException(), isNull);
            },
            responseFor: (request) async {
              if (request.operationName == 'NotificationPreferencesUpdate') {
                savedEmail = List<String>.from(
                  request.variables['emailCategories'] as List,
                );
                return {'notificationPreferencesUpdate': preferences()};
              }
              return {'notificationPreferences': preferences()};
            },
          );
        },
      );
    }
  }
}
