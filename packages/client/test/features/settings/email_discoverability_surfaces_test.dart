@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
// Redirect the federated path provider to this test's temporary app directory.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The federated plugin provides an in-memory backend for widget tests.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// Keep the same platform store when the test restarts the app.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:tentura/app/di/di_current.config.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/home/domain/port/home_orientation_preferences_port.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/features/home/ui/screen/home_screen.dart';
import 'package:tentura/features/home/ui/widget/home_account_avatar_button.dart';
import 'package:tentura/features/home/ui/widget/home_rail_account_footer.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/features/settings/ui/screen/settings_screen.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_handler.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../data/service/_session_account_test_harness.dart';
import '../../support/phone_surface.dart';

const _accountId = 'Uviewer000001';
const _contactId = 'Ucontact00001';
const _settingTitle = "People who have my email can see I'm on Tentura";
const _query = 'emailDiscoverability';
const _mutation = 'emailDiscoverabilitySet';

void main() {
  group('Email discoverability in Settings → Account', () {
    testWidgets('shows on from the server query', (tester) async {
      final app = _App.create(tester, enabled: true);
      await app.start(path: kPathSettings);

      expect(_switchValue(tester, _settingsSwitch()), isTrue);
      expect(app.server.reads, greaterThan(0));
      expect(app.server.writes, isEmpty);
    });

    testWidgets('shows off from a raw GraphQL false response', (tester) async {
      const body = '{"data":{"emailDiscoverability":false}}';
      final app = _App.create(tester, enabled: true);
      app.server.rawQueryResponse = body;

      // The route resolves its real repository and cubit through app DI.
      // The fixture replaces HTTP, so the switch can only get this answer
      // from the production GraphQL client and its response mapping.
      await app.start(path: kPathSettings);

      expect(_switchValue(tester, _settingsSwitch()), isFalse);
      expect(app.server.queryResponseBodies, isNotEmpty);
      expect(app.server.queryResponseBodies, everyElement(body));
      expect(app.server.writes, isEmpty);
    });

    testWidgets('writes off from the tile and writes on from its switch', (
      tester,
    ) async {
      final app = _App.create(tester, enabled: true);
      await app.start(path: kPathSettings);
      final control = _settingsSwitch();

      expect(_switchValue(tester, control), isTrue);
      await _tap(tester, find.text(_settingTitle));
      expect(app.server.writes, [false]);
      expect(_switchValue(tester, control), isFalse);

      await _tap(tester, control);
      expect(app.server.writes, [false, true]);
      expect(_switchValue(tester, control), isTrue);
    });

    testWidgets('shows the mutation answer to each request to turn off', (
      tester,
    ) async {
      final app = _App.create(tester, enabled: true);
      // Hold every query at the initial value. Only the mutation can tell
      // the tile that the second request was accepted.
      app.server.rawQueryResponse = '{"data":{"emailDiscoverability":true}}';
      await app.start(path: kPathSettings);
      final control = _settingsSwitch();
      expect(_switchValue(tester, control), isTrue);

      app.server.mutationAnswer = true;
      await _tap(tester, control);

      expect(app.server.writes, [false]);
      expect(_switchValue(tester, control), isTrue);

      app.server.mutationAnswer = false;
      await _tap(tester, control);

      expect(app.server.writes, [false, false]);
      expect(_switchValue(tester, control), isFalse);
    });
  });

  group('Email discoverability explainer on signed-in Home', () {
    for (final enabled in [true, false]) {
      testWidgets(
        'explains the setting with its switch ${enabled ? 'on' : 'off'}',
        (
          tester,
        ) async {
          final app = _App.create(tester, enabled: enabled);
          await app.start();

          final card = _explainer();
          expect(card, findsOneWidget);
          expect(_explanation(tester, card), isNotEmpty);
          expect(_switchValue(tester, _inlineSwitch(card)), enabled);
          expect(app.server.reads, greaterThan(0));
        },
      );
    }

    testWidgets('changing the inline switch updates the Account setting', (
      tester,
    ) async {
      final app = _App.create(tester, enabled: true);
      await app.start();
      final card = _explainer();
      final control = _inlineSwitch(card);

      expect(_switchValue(tester, control), isTrue);
      await _tap(tester, control);
      expect(app.server.writes, [false]);
      expect(_switchValue(tester, control), isFalse);

      await app.openSettings();
      expect(_switchValue(tester, _settingsSwitch()), isFalse);
    });

    testWidgets('returning to a rebuilt Home keeps an undismissed card', (
      tester,
    ) async {
      final app = _App.create(tester, enabled: true);
      await app.start();
      final wasVisible = _explainer().evaluate().length == 1;

      await app.rebuildHomeFromSettings();

      expect(_explainer(), findsOneWidget);
      expect(wasVisible, isTrue);
    });

    testWidgets('dismissal hides the card after rebuild and app restart', (
      tester,
    ) async {
      final app = _App.create(tester, enabled: true);
      await app.start();
      final card = _explainer();
      expect(card, findsOneWidget);
      final explanation = _explanation(tester, card);
      expect(explanation, isNotEmpty);

      void expectCardHidden() {
        expect(_explainer(), findsNothing);
        for (final line in explanation) {
          expect(find.text(line), findsNothing);
        }
      }

      await _tap(tester, _dismissControl(card));
      expectCardHidden();
      expect(app.server.writes, isEmpty);

      await app.rebuildHomeFromSettings();
      expectCardHidden();

      await app.stop();
      await app.start();
      expectCardHidden();
    });
  });

  testWidgets('Account shows Russian email privacy copy at 375 × 667', (
    tester,
  ) async {
    final app = _App.create(tester, enabled: true);
    await app.start(path: kPathSettings);

    final englishTile = _settingsTile(_settingTitle);
    final tileCopy = _texts(tester, englishTile);
    final englishSubtitle = _settingsSubtitle(tester, englishTile);
    final subtitleCopy = englishSubtitle == null
        ? null
        : _texts(tester, englishSubtitle);

    await app.stop();
    await _useRussianPhoneSurface(tester);
    await app.start(path: kPathSettings, locale: const Locale('ru'));

    final en = _catalog('en');
    final ru = _catalog('ru');
    final titles = _translationsOf(_settingTitle, en, ru);
    final russianTitle = titles.singleWhere(
      (title) => _settingsTile(
        title,
        locale: const Locale('ru'),
      ).evaluate().isNotEmpty,
      orElse: () => fail(
        'Account does not show a Russian translation of the setting title',
      ),
    );
    final russianTile = _settingsTile(russianTitle, locale: const Locale('ru'));
    expect(tileCopy, contains(_settingTitle));
    _expectTranslatedText(tester, russianTile, tileCopy, en, ru);

    final russianSubtitle = _settingsSubtitle(tester, russianTile);
    if (subtitleCopy == null) {
      expect(russianSubtitle, isNull);
    } else {
      expect(subtitleCopy, isNotEmpty, reason: 'Account renders its subtitle');
      expect(
        russianSubtitle,
        isNotNull,
        reason: 'Account has a Russian subtitle',
      );
      _expectTranslatedText(tester, russianSubtitle!, subtitleCopy, en, ru);
    }
  });

  testWidgets(
    'Home shows Russian explainer copy and dismiss label at 375 × 667',
    (
      tester,
    ) async {
      final app = _App.create(tester, enabled: true);
      await app.start();

      final englishCard = _explainer();
      final cardCopy = _texts(tester, englishCard);
      final englishDismiss = _dismissControl(englishCard);
      final dismissLabel = englishDismiss.evaluate().length == 1
          ? _controlLabel(tester, englishDismiss)
          : null;

      await app.stop();
      await _useRussianPhoneSurface(tester);
      await app.start(locale: const Locale('ru'));

      final russianCard = _explainer();
      expect(russianCard, findsOneWidget);
      final ruDismiss = _dismissControl(russianCard);
      expect(ruDismiss, findsOneWidget);
      expect(
        dismissLabel,
        isNotNull,
        reason: 'Home has an English dismiss label',
      );
      expect(
        cardCopy.where((text) => text != dismissLabel && text != _settingTitle),
        hasLength(greaterThanOrEqualTo(2)),
        reason: 'The explainer has a title and a body',
      );
      final en = _catalog('en');
      final ru = _catalog('ru');
      expect(
        _translationsOf(dismissLabel!, en, ru),
        contains(_controlLabel(tester, ruDismiss)),
      );
      _expectTranslatedText(tester, russianCard, cardCopy, en, ru);
    },
  );
}

Future<void> _useRussianPhoneSurface(WidgetTester tester) async {
  await usePhoneSurface(tester);
  tester.view
    ..physicalSize = kPhoneSurface
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder _settingsTile(String title, {Locale locale = const Locale('en')}) {
  final account = find.byWidgetPredicate(
    (widget) =>
        widget is TenturaMenuGroup &&
        widget.title == lookupL10n(locale).settingsSectionAccount,
    description: 'the Settings Account section',
  );
  return find.descendant(
    of: account,
    matching: find.widgetWithText(ListTile, title),
  );
}

Finder _settingsSwitch() => find.descendant(
  of: _settingsTile(_settingTitle),
  matching: find.byType(Switch),
);

Finder? _settingsSubtitle(WidgetTester tester, Finder tile) {
  if (tile.evaluate().isEmpty) return null;
  expect(tile, findsOneWidget);
  final subtitle = tester.widget<ListTile>(tile).subtitle;
  return subtitle == null ? null : find.byWidget(subtitle);
}

Finder _explainer() => find.ancestor(
  of: find.descendant(
    of: find.byType(HomeScreen),
    matching: find.byType(Switch),
  ),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Card ||
        widget is TenturaTechCard ||
        widget is TenturaTechCardStatic ||
        widget is MaterialBanner,
    description: 'the email discoverability card on Home with an inline switch',
  ),
);

Finder _inlineSwitch(Finder card) => find.descendant(
  of: card,
  matching: find.byType(Switch),
);

bool _switchValue(WidgetTester tester, Finder control) {
  expect(control, findsOneWidget);
  return tester.widget<Switch>(control).value;
}

List<String> _texts(WidgetTester tester, Finder scope) => tester
    .widgetList<Text>(
      find.descendant(of: scope, matching: find.byType(Text), matchRoot: true),
    )
    .map((text) => text.data ?? text.textSpan!.toPlainText())
    .toList();

// The card explains the effect separately from the switch's setting label.
Iterable<String> _explanation(WidgetTester tester, Finder card) =>
    _texts(tester, card).where(
      (text) =>
          text != _settingTitle &&
          text.contains('Tentura') &&
          RegExp(r'\be-?mail\b', caseSensitive: false).hasMatch(text) &&
          RegExp(
            r'\b(see|find|know|check|match|tell|discover)\b',
            caseSensitive: false,
          ).hasMatch(text),
    );

Finder _dismissControl(Finder card) => find.descendant(
  of: card,
  matching: find.byWidgetPredicate(
    (widget) =>
        (widget is ButtonStyleButton && widget.onPressed != null) ||
        (widget is IconButton && widget.onPressed != null),
    description: 'the explainer dismiss button',
  ),
);

String _controlLabel(WidgetTester tester, Finder control) {
  final button = tester.widget(control);
  if (button is IconButton) return button.tooltip ?? '';
  return _texts(tester, control).single;
}

Map<String, Object?> _catalog(String locale) =>
    (jsonDecode(File('l10n/app_$locale.arb').readAsStringSync()) as Map)
        .cast<String, Object?>();

Set<String> _translationsOf(
  String english,
  Map<String, Object?> en,
  Map<String, Object?> ru,
) {
  final keys = en.keys.where(
    (key) => !key.startsWith('@') && en[key] == english,
  );
  expect(keys, isNotEmpty, reason: '$english is in app_en.arb');
  final translations = keys
      .map((key) => ru[key])
      .whereType<String>()
      .where((text) => RegExp('[А-Яа-яЁё]').hasMatch(text))
      .toSet();
  expect(
    translations,
    isNotEmpty,
    reason: '$english is translated in app_ru.arb',
  );
  for (final copy in [english, ...translations]) {
    expect(copy.toLowerCase(), isNot(matches(RegExp('phantom|фантом'))));
  }
  return translations;
}

void _expectTranslatedText(
  WidgetTester tester,
  Finder surface,
  List<String> englishCopy,
  Map<String, Object?> en,
  Map<String, Object?> ru,
) {
  final rendered = _texts(tester, surface);
  final translationsByText = {
    for (final english in englishCopy)
      english: _translationsOf(english, en, ru),
  };
  final translatedCopy = translationsByText.values.expand((copy) => copy);
  expect(rendered, everyElement(isNot(isIn(englishCopy))));
  expect(rendered, everyElement(isIn(translatedCopy)));
  for (final MapEntry(key: english, value: translations)
      in translationsByText.entries) {
    final localized = find.descendant(
      of: surface,
      matchRoot: true,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            translations.contains(
              widget.data ?? widget.textSpan!.toPlainText(),
            ),
        description: 'rendered Russian translation of "$english"',
      ),
    );
    expect(localized, findsWidgets);
    for (final text in tester.renderObjectList<RenderParagraph>(localized)) {
      expect(text.didExceedMaxLines, isFalse, reason: english);
      expect(text.size.width, lessThanOrEqualTo(kPhoneSurface.width));
    }
  }
}

Future<void> _settle(WidgetTester tester) async {
  // Advance route transitions without waiting for unrelated repeating
  // animations elsewhere in the signed-in shell.
  for (var frame = 0; frame < 20; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(tester.takeException(), isNull);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _settle(tester);
}

class _App {
  _App._(this.tester, this.server);

  factory _App.create(
    WidgetTester tester, {
    required bool enabled,
  }) {
    final dir = Directory.systemTemp.createTempSync('email-privacy-test-');
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final previousPreferences = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(
      () => SharedPreferencesAsyncPlatform.instance = previousPreferences,
    );
    final previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestDirectories(dir.path);
    addTearDown(() => PathProviderPlatform.instance = previousPathProvider);
    const location = MethodChannel('flutter.baseflow.com/geolocator');
    final messenger = tester.binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(location, (_) async => false);
    addTearDown(() => messenger.setMockMethodCallHandler(location, null));
    PackageInfo.setMockInitialValues(
      appName: 'Tentura',
      packageName: 'tentura',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    final app = _App._(tester, _PrivacyServer(enabled));
    addTearDown(() => dir.deleteSync(recursive: true));
    addTearDown(app.stop);
    return app;
  }

  final WidgetTester tester;
  final _PrivacyServer server;
  RootRouter? _router;
  bool _initialized = false;

  Future<void> start({
    String path = kPathMyWork,
    Locale locale = const Locale('en'),
  }) async {
    await tester.runAsync(() async {
      final getIt = GetIt.I;
      _initialized = true;
      getIt
        ..registerSingleton<RealtimeSocketFactory>(NoopRealtimeSocketFactory())
        ..skipDoubleRegistration = true;
      try {
        await http.runWithClient(
          () => getIt
              .init(environment: 'dev')
              .timeout(const Duration(seconds: 15)),
          () => MockClient((request) async => server.respond(request)),
        );
      } finally {
        getIt.skipDoubleRegistration = false;
      }
      // Startup also fills the unrelated contact cache. Let it finish before
      // any test can unmount and close the database.
      final contacts = getIt<ContactsCase>();
      if (contacts.nameOf(_contactId) == null) {
        await contacts.changes
            .firstWhere((_) => contacts.nameOf(_contactId) != null)
            .timeout(const Duration(seconds: 5));
      }
      await contacts.refresh().timeout(const Duration(seconds: 5));
      await getIt<SettingsCubit>().setIntroEnabled(false);
      final orientation = getIt<HomeOrientationPreferencesPort>();
      await orientation.setActivated(userId: _accountId);
      await orientation.setOrientationDismissed(userId: _accountId);
      _router = getIt<RootRouter>();
    });
    expect(GetIt.I<AuthCubit>().state.currentAccountId, _accountId);
    final router = _router!;
    await tester.pumpWidget(
      MaterialApp.router(
        locale: locale,
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        routerConfig: router.config(
          deepLinkBuilder: (_) => DeepLink.path(path),
          includePrefixMatches: false,
        ),
        builder: (context, child) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: GetIt.I<ScreenCubit>()),
            BlocProvider.value(value: GetIt.I<AuthCubit>()),
            BlocProvider.value(value: GetIt.I<SettingsCubit>()),
            BlocProvider.value(value: GetIt.I<ProfileCubit>()),
          ],
          child: UiEffectHandler(
            effects: GetIt.I<UiEffectPort>(),
            child: TenturaResponsiveScope(child: child!),
          ),
        ),
      ),
    );
    await _settle(tester);
    if (path == kPathSettings) {
      expect(find.byType(SettingsScreen), findsOneWidget);
    } else {
      await _waitForHome();
    }
  }

  Future<void> _waitForHome() async {
    expect(find.byType(HomeScreen), findsOneWidget);
    final activation = GetIt.I<HomeActivationCubit>();
    // Drift runs on a background isolate. Let its responses reach the
    // test binding before a restart tears down the first widget tree.
    for (
      var attempt = 0;
      attempt < 100 && !activation.state.hydrated;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(activation.state.hydrated, isTrue);
    await _settle(tester);
  }

  Future<void> openSettings() async {
    final l10n = L10n.of(tester.element(find.byType(HomeScreen)))!;
    final avatar = find.byKey(HomeAccountAvatarButton.buttonKey).hitTestable();
    await _tap(
      tester,
      avatar.evaluate().isNotEmpty
          ? avatar
          : find.byKey(HomeRailAccountFooter.footerKey),
    );
    await _tap(tester, find.text(l10n.labelSettings));
    expect(find.byType(SettingsScreen), findsOneWidget);
  }

  Future<void> rebuildHomeFromSettings() async {
    await openSettings();
    final router = _router!;
    await router.replaceAll([SettingsRoute()], updateExistingRoutes: false);
    await _settle(tester);
    expect(find.byType(HomeScreen, skipOffstage: false), findsNothing);

    await router.replaceAll([const HomeRoute()], updateExistingRoutes: false);
    await _settle(tester);
    await _waitForHome();
  }

  Future<void> stop() async {
    if (!_initialized) return;
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
    await tester.runAsync(
      () => GetIt.I.reset().timeout(const Duration(seconds: 10)),
    );
    SharedPreferences.resetStatic();
    _initialized = false;
    _router = null;
  }
}

class _PrivacyServer {
  _PrivacyServer(this.enabled);

  bool enabled;
  bool? mutationAnswer;
  String? rawQueryResponse;
  int reads = 0;
  final queryResponseBodies = <String>[];
  final writes = <bool>[];

  http.Response respond(http.Request request) {
    if (request.url.path.endsWith('/session/access-token')) {
      return _json({
        'subject': _accountId,
        'access_token': 'test-token',
        'expires_in': 3600,
      });
    }
    final payload = jsonDecode(request.body) as Map<String, dynamic>;
    final document = payload['query'] as String;
    if (document.contains(_query)) {
      return _respondToSetting(request.url.path, document, payload);
    }
    final data = switch (payload['operationName']) {
      'UserFetchById' => {
        '__typename': 'query_root',
        'user_by_pk': {
          '__typename': 'user',
          'id': _accountId,
          'created_at': '2026-01-01T12:00:00Z',
          'display_name': 'Mira',
          'handle': 'mira',
          'description': '',
          'my_vote': 0,
          'trusts_viewer': false,
          'is_mutual_friend': false,
          'image': null,
          'scores': <Object>[],
          'user_presence': null,
          'user_availability': null,
        },
      },
      'MyContacts' => {
        'myContacts': [
          {
            'subjectId': _contactId,
            'contactName': 'A contact',
            'updatedAt': '2026-01-01T12:00:00Z',
          },
        ],
      },
      'NoisyWallEnabled' => {'noisyWallEnabled': false},
      'AttentionLiveObligations' => {'liveObligationBeacons': <String>[]},
      'MyWorkInit' => {
        'authoredNonArchived': <Object>[],
        'helpOfferedNonArchived': <Object>[],
        'obligationBeacons': <Object>[],
        'archivedIdHints': <Object>[],
      },
      'MyWorkArchived' => {
        'archivedRows': <Object>[],
        'helpOfferedArchived': <Object>[],
      },
      'InboxFetch' => {'inbox_item': <Object>[]},
      'MyPosts' => {'myPosts': <Object>[]},
      _ => <String, Object?>{},
    };
    return _json({'data': data});
  }

  http.Response _respondToSetting(
    String path,
    String document,
    Map<String, dynamic> payload,
  ) {
    if (path != kPathGraphQLEndpointV2) {
      return _json({
        'errors': [
          {'message': 'Email discoverability belongs to the Tentura API'},
        ],
      });
    }

    final operation = parseString(document).definitions
        .whereType<OperationDefinitionNode>()
        .singleWhere((op) => op.name?.value == payload['operationName']);
    final field = operation.selectionSet.selections
        .whereType<FieldNode>()
        .singleWhere(
          (field) =>
              field.name.value == _query || field.name.value == _mutation,
        );
    final responseKey = field.alias?.value ?? field.name.value;
    if (operation.type == OperationType.query && field.name.value == _query) {
      reads++;
      final body =
          rawQueryResponse ??
          jsonEncode({
            'data': {responseKey: enabled},
          });
      final response = _jsonResponse(body);
      queryResponseBodies.add(response.body);
      return response;
    } else if (operation.type == OperationType.mutation &&
        field.name.value == _mutation) {
      final argument = field.arguments
          .singleWhere((arg) => arg.name.value == 'enabled')
          .value;
      final variables = payload['variables'] as Map<String, dynamic>?;
      final requested = switch (argument) {
        BooleanValueNode(:final value) => value,
        VariableNode(:final name) => variables?[name.value] as bool,
        _ => throw ArgumentError.value(
          argument,
          'enabled',
          'Expected a Boolean',
        ),
      };
      writes.add(requested);
      enabled = mutationAnswer ?? requested;
    } else {
      throw StateError('Unexpected email discoverability operation');
    }
    return _json({
      'data': {responseKey: enabled},
    });
  }

  http.Response _json(Map<String, Object?> data) =>
      _jsonResponse(jsonEncode(data));

  http.Response _jsonResponse(String body) => http.Response(
    body,
    200,
    headers: {'content-type': 'application/json'},
  );
}

class _TestDirectories extends PathProviderPlatform {
  _TestDirectories(this.path);

  final String path;

  @override
  Future<String> getTemporaryPath() async => path;

  @override
  Future<String> getApplicationDocumentsPath() async => path;
}
