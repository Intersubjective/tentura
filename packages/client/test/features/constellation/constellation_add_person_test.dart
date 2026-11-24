@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/port/constellation_account_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_app_bar.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_no_contacts.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/people_tags/data/repository/people_tags_repository.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/phantoms/data/repository/phantom_repository.dart';
import 'package:tentura/features/phantoms/domain/port/phantom_repository_port.dart';

import '../../support/constellation_composer_screen_harness.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _viewer = Profile(id: 'Uviewer000001', displayName: 'Viewer');
const _newPerson = 'PH0123456789ab';
const _code = 'I123456789abc';
const _canvasAction = 'Add someone not on Tentura yet';
const _personAction = '+ Person';
const _save = 'Save without inviting';
const _copy = 'Copy invite link';
const _share = 'Share…';
const _personalLine =
    'Hi Anna, I put you on my map in Tentura — join so we can ask each other for a hand.';
const _editedLine = 'Anna, come join our neighbourhood group!';
const _appBarAdd = Key('constellation.app_bar.create_here');
const _requestItem = Key('constellation.canvas.create_menu.request');
const _postItem = Key('constellation.canvas.create_menu.post');
const _shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
final _now = DateTime.utc(2026, 11, 24, 12);

Finder get _canvas => find.byType(GraphView<NodeDetails, EdgeDetails>);
Finder get _banner => find.byKey(ConstellationNoContactsBanner.bannerKey);
Finder _inBanner(Finder child) => find.descendant(of: _banner, matching: child);
Finder get _personInBanner => _inBanner(find.text(_personAction));
Finder _personInMenu([String label = _personAction]) => find.descendant(
  of: find.byWidgetPredicate((widget) => widget is PopupMenuItem<Object?>),
  matching: find.text(label),
);
Finder _editableNamed(Pattern label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        label.allMatches(widget.decoration?.labelText ?? '').isNotEmpty,
  ),
  matching: find.byType(EditableText),
);

Finder get _name => _editableNamed(RegExp(r'\bname\b', caseSensitive: false));
Finder get _message => _editableNamed(
  RegExp(r'\b(invite|invitation|message)\b', caseSensitive: false),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'holding an empty point offers a person alongside Request and Post',
    (
      tester,
    ) async {
      await _withField(tester, (field) async {
        await _openCanvasMenu(tester, _emptyPoint(tester));
        await _choosePerson(tester, find.text(_canvasAction));
        _expectSheet();
        expect(field.creates, isEmpty);
      });
    },
  );

  testWidgets('right-clicking an empty point opens the same add-person sheet', (
    tester,
  ) async {
    await _withField(tester, (field) async {
      await _openCanvasMenu(tester, _emptyPoint(tester), rightClick: true);
      await _choosePerson(tester, find.text(_canvasAction));
      _expectSheet();
      expect(field.creates, isEmpty);
    });
  });

  testWidgets(
    'saving from the canvas keeps the name, chosen emoji and pressed point',
    (
      tester,
    ) async {
      await _withField(tester, (field) async {
        final point = _emptyPoint(tester);
        final scene = field.sceneAt(tester, point);
        await _openCanvasMenu(tester, point);
        await _choosePerson(tester, find.text(_canvasAction));
        await _enterName(tester, '  Anna  ');

        const emoji = '😀';
        final emojiControl = find.byTooltip('Emoji').evaluate().isEmpty
            ? find.text('Emoji')
            : find.byTooltip('Emoji');
        await _tap(tester, emojiControl);
        await _tap(tester, find.text(emoji).hitTestable().first);
        await _tap(tester, find.text(_save));

        field.expectCreatedAt(scene, emoji: emoji);
        expect(field.invites, isEmpty, reason: 'saving alone mints no invite');
        expect(field.tagWrites, isEmpty, reason: 'no tags were selected');
        await field.deliverPersonChange(tester);
        field.expectPersonOnMap(scene, emoji: emoji);
      });
    },
  );

  testWidgets('the app-bar add menu saves a pin at the viewport centre', (
    tester,
  ) async {
    await _withField(tester, (field) async {
      final centre = field.sceneAt(tester, tester.getCenter(_canvas));
      await _openAppBarMenu(tester);
      await _choosePerson(tester, _personInMenu());
      _expectSheet();
      await _enterName(tester, 'Anna');
      await _tap(tester, find.text(_save));

      field.expectCreatedAt(centre);
      await field.deliverPersonChange(tester);
      field.expectPersonOnMap(centre);
    });
  });

  testWidgets(
    'the empty Field offers a visible add button next to its invite',
    (
      tester,
    ) async {
      await _withField(tester, (field) async {
        _expectBannerInvite();
        final centre = field.sceneAt(tester, tester.getCenter(_canvas));
        final add = _personInBanner.hitTestable();
        await _choosePerson(tester, add);
        _expectSheet();
        await _enterName(tester, 'Anna');
        await _tap(tester, find.text(_save));

        field.expectCreatedAt(centre);
        await field.deliverPersonChange(tester);
        expect(
          _banner,
          findsNothing,
          reason: 'the Field now has someone on it',
        );
      });
    },
  );

  testWidgets('the rollout gate hides each add-person entry until enabled', (
    tester,
  ) async {
    await _withField(tester, (field) async {
      _expectBannerInvite();
      expect(_personInBanner, findsNothing);
      await _openCanvasMenu(tester, _emptyPoint(tester));
      expect(find.text(_canvasAction), findsNothing);
      await _dismissOverlay(tester);
      await _openAppBarMenu(tester);
      expect(_personInMenu(), findsNothing);
      await _dismissOverlay(tester);

      await field.mount(tester, enabled: true);
      expect(_personInBanner.hitTestable(), findsOneWidget);
      await _openCanvasMenu(tester, _emptyPoint(tester), rightClick: true);
      expect(find.text(_canvasAction), findsOneWidget);
      await _dismissOverlay(tester);
      await _openAppBarMenu(tester);
      expect(_personInMenu(), findsOneWidget);
    }, enabled: false);
  });

  testWidgets('names below three trimmed characters cannot save or invite', (
    tester,
  ) async {
    await _withField(tester, (field) async {
      await _openFromAppBar(tester);
      for (final name in ['Al', '  Al  ']) {
        await _enterName(tester, name);
        for (final action in [_save, _copy, _share]) {
          final label = find.text(action);
          final button = find.ancestor(
            of: label,
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          );
          expect(button, findsOneWidget, reason: 'the sheet shows $action');
          expect(tester.widget<ButtonStyleButton>(button).enabled, isFalse);
          await tester.ensureVisible(label);
          await tester.tap(label, warnIfMissed: false);
          await tester.pumpAndSettle();
        }
        expect(field.creates, isEmpty);
        expect(field.invites, isEmpty);
      }

      await _enterName(tester, '  Ann  ');
      await _tap(tester, find.text(_save));
      expect(field.creates.single.variables['name'], 'Ann');
    });
  });

  testWidgets('the name field accepts at most 32 characters', (tester) async {
    await _withField(tester, (field) async {
      await _openFromAppBar(tester);
      const limit = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ123456';
      await _enterName(tester, '${limit}789');
      expect(_entered(tester, _name), limit);
      await _tap(tester, find.text(_save));
      expect(field.creates.single.variables['name'], limit);
    });
  });

  testWidgets(
    'saving selected tags adds the newly created person to each tag',
    (
      tester,
    ) async {
      await _withField(tester, (field) async {
        await _openFromAppBar(tester);
        await _enterName(tester, 'Anna');
        // Use the tag chooser if the sheet presents the tags behind a button.
        if (find.text(_tags.keys.first).evaluate().isEmpty) {
          await _tap(tester, find.text('Tags'));
        }
        for (final tag in _tags.keys) {
          await _tap(tester, find.text(tag));
        }
        if (find.text(_save).hitTestable().evaluate().isEmpty) {
          // A separate tag chooser applies its selection via a visible action.
          await _tap(tester, find.textContaining(RegExp(r'^(Done|Apply)$')));
        }
        await _tap(tester, find.text(_save));

        expect(field.creates, hasLength(1));
        final writes = field.tagWrites;
        expect(writes, isNotEmpty);
        expect(
          writes.expand((call) => call.variables['ops'] as List<Object?>),
          unorderedEquals([
            for (final id in _tags.values)
              allOf(
                containsPair('tagId', id),
                containsPair('personId', _newPerson),
                containsPair('op', 'add'),
              ),
          ]),
        );
        expect(
          field.sent.indexOf(writes.first),
          greaterThan(
            field.sent.indexOf(field.creates.single),
          ),
        );
      });
    },
  );

  testWidgets(
    'the personal line follows name edits until it is edited by hand',
    (
      tester,
    ) async {
      await _withField(tester, (field) async {
        await _openFromAppBar(tester);
        await _enterName(tester, 'Anna');
        expect(_entered(tester, _message), _personalLine);
        await _enterName(tester, 'Mira');
        expect(
          _entered(tester, _message),
          _personalLine.replaceFirst('Anna', 'Mira'),
        );

        await tester.ensureVisible(_message);
        await tester.enterText(_message, _editedLine);
        await _enterName(tester, 'Anna');
        expect(_entered(tester, _message), _editedLine);
        expect(field.creates, isEmpty);
        expect(field.invites, isEmpty);
      });
    },
  );

  testWidgets(
    'copy puts the personal line and ensured link on the clipboard and '
    'further sharing reuses the person',
    (tester) async {
      final clipboard = _recordClipboard(tester);
      final shares = _recordShares(tester);
      await _withField(tester, (field) async {
        await _openFromAppBar(tester);
        await _enterName(tester, 'Anna');
        await tester.ensureVisible(_message);
        await tester.enterText(_message, _editedLine);
        await tester.pump();
        expect(field.creates, isEmpty);
        expect(field.invites, isEmpty);

        await _tap(tester, find.text(_copy));
        expect(field.creates.single.variables['name'], 'Anna');
        expect(field.invites.single.variables, {'id': _newPerson});
        expect(
          field.sent.indexOf(field.invites.single),
          greaterThan(
            field.sent.indexOf(field.creates.single),
          ),
        );
        _expectInvitePayload(clipboard.single, _editedLine);
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text(
              'The link has been copied to the clipboard',
              findRichText: true,
            ),
          ),
          findsOneWidget,
        );

        await _tap(tester, find.text(_copy));
        expect(clipboard, hasLength(2));
        _expectInvitePayload(clipboard.last, _editedLine);
        await _tap(tester, find.text(_share));
        _expectInvitePayload(shares.single['text'], _editedLine);
        expect(field.creates, hasLength(1));
        expect(
          field.invites.map((call) => call.variables['id']),
          everyElement(_newPerson),
        );
      });
    },
  );

  testWidgets(
    'sharing first creates the person and sends the default line with '
    'their ensured invite link to the system sheet',
    (tester) async {
      final shares = _recordShares(tester);
      await _withField(tester, (field) async {
        await _openFromAppBar(tester);
        await _enterName(tester, 'Anna');
        expect(field.creates, isEmpty);
        expect(field.invites, isEmpty);
        await _tap(tester, find.text(_share));

        expect(field.creates.single.variables['name'], 'Anna');
        expect(field.invites.single.variables, {'id': _newPerson});
        expect(
          field.sent.indexOf(field.invites.single),
          greaterThan(
            field.sent.indexOf(field.creates.single),
          ),
        );
        _expectInvitePayload(shares.single['text'], _personalLine);
      });
    },
  );

  testWidgets('Russian phone menus, banner and sheet use the Russian catalog', (
    tester,
  ) async {
    await _withField(tester, (_) async {
      final context = tester.element(find.byType(ConstellationBody));
      expect(Localizations.localeOf(context), const Locale('ru'));
      expect(MediaQuery.sizeOf(context), kPhoneSurface);

      await _openCanvasMenu(tester, _emptyPoint(tester));
      final en = _catalog('en');
      final ru = _catalog('ru');
      final canvas = _localized(en, ru, _canvasAction);
      final person = _localized(en, ru, _personAction);
      await _choosePerson(tester, find.text(canvas));
      final save = _localized(en, ru, _save);
      final copy = _localized(en, ru, _copy);
      final share = _localized(en, ru, _share);
      for (final action in [save, copy, share]) {
        final label = find.text(action);
        expect(label, findsOneWidget);
        await tester.ensureVisible(label);
        await tester.pumpAndSettle();
        expect(label.hitTestable(), findsOneWidget);
      }

      final name = _editableNamed(RegExp('имя', caseSensitive: false));
      final message = _editableNamed(
        RegExp(
          'приглашен|сообщени',
          caseSensitive: false,
        ),
      );
      for (final field in [name, message]) {
        final textField = find.ancestor(
          of: field,
          matching: find.byType(TextField),
        );
        final label = tester.widget<TextField>(textField).decoration?.labelText;
        expect(ru.values, contains(label));
        expect(en.values, isNot(contains(label)));
      }
      for (final english in ['Emoji', 'Tags']) {
        final label = _localized(en, ru, english);
        expect(
          find.text(label).evaluate().isNotEmpty ||
              find.byTooltip(label).evaluate().isNotEmpty,
          isTrue,
          reason: 'the sheet shows the Russian label $label',
        );
      }
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Анна');
      await tester.pump();
      final placeholder = RegExp(r'\{[^{}]+\}');
      final templateKey = en.entries.singleWhere((entry) {
        final text = entry.value;
        return !entry.key.startsWith('@') &&
            text is String &&
            text.replaceFirst(placeholder, 'Anna') == _personalLine;
      }).key;
      final translated = ru[templateKey];
      expect(
        translated,
        isA<String>(),
        reason: 'the personal line has a Russian translation',
      );
      final russianLine = (translated! as String).replaceAll(
        placeholder,
        'Анна',
      );
      expect(russianLine, contains('Анна'));
      expect(russianLine, matches(RegExp('[А-Яа-яЁё]')));
      expect(_entered(tester, message), russianLine);

      final internalWord = RegExp('phantom|фантом', caseSensitive: false);
      for (final catalog in [en, ru]) {
        expect(
          catalog.entries.where(
            (entry) {
              final text = entry.value;
              return !entry.key.startsWith('@') &&
                  text is String &&
                  internalWord.hasMatch(text);
            },
          ),
          isEmpty,
        );
      }
      expect(tester.takeException(), isNull);
      await _dismissOverlay(tester);

      await _openAppBarMenu(tester);
      await _choosePerson(tester, _personInMenu(person));
      expect(find.text(save), findsOneWidget);
      await _dismissOverlay(tester);

      _expectBannerInvite();
      await _choosePerson(tester, _inBanner(find.text(person)).hitTestable());
      expect(find.text(save), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, locale: const Locale('ru'));
  });
}

void _expectBannerInvite() {
  expect(_banner, findsOneWidget);
  expect(
    _inBanner(
      find.byKey(ConstellationNoContactsBanner.inviteKey),
    ).hitTestable(),
    findsOneWidget,
  );
}

void _expectSheet() {
  expect(_name, findsOneWidget);
  for (final action in [_save, _copy, _share]) {
    expect(find.text(action), findsOneWidget);
  }
}

Offset _emptyPoint(WidgetTester tester) =>
    tester.getRect(_canvas).bottomRight - const Offset(100, 85);

Future<void> _openCanvasMenu(
  WidgetTester tester,
  Offset point, {
  bool rightClick = false,
}) async {
  if (rightClick) {
    await tester.tapAt(
      point,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
  } else {
    await tester.longPressAt(point);
  }
  await tester.pumpAndSettle();
  expect(find.byKey(_requestItem), findsOneWidget);
  expect(find.byKey(_postItem), kPostsEnabled ? findsOneWidget : findsNothing);
}

Future<void> _openAppBarMenu(WidgetTester tester) async {
  await _tap(tester, find.byKey(_appBarAdd));
  expect(find.byKey(_requestItem), findsOneWidget);
}

Future<void> _openFromAppBar(WidgetTester tester) async {
  await _openAppBarMenu(tester);
  await _choosePerson(tester, _personInMenu());
}

Future<void> _choosePerson(WidgetTester tester, Finder choice) async {
  expect(
    choice,
    findsOneWidget,
    reason: 'the entry point offers adding a person',
  );
  await _tap(tester, choice);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _enterName(WidgetTester tester, String name) async {
  await tester.ensureVisible(_name);
  await tester.enterText(_name, name);
  await tester.pump();
}

String _entered(WidgetTester tester, Finder field) =>
    tester.widget<EditableText>(field).controller.text;

Future<void> _dismissOverlay(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(ConstellationBody))).pop();
  await tester.pumpAndSettle();
}

Map<String, Object?> _catalog(String locale) =>
    jsonDecode(File('l10n/app_$locale.arb').readAsStringSync())
        as Map<String, Object?>;

String _localized(
  Map<String, Object?> en,
  Map<String, Object?> ru,
  String label,
) {
  final values = en.entries
      .where((entry) => entry.value == label)
      .map((entry) => ru[entry.key])
      .whereType<String>()
      .toSet();
  expect(values, hasLength(1), reason: 'the catalogs translate "$label"');
  final translated = values.single;
  expect(translated, matches(RegExp('[А-Яа-яЁё]')));
  return translated;
}

void _expectInvitePayload(Object? payload, String line) {
  expect(payload, isA<String>());
  final text = payload! as String;
  expect(text, startsWith(line));
  final afterLine = text.substring(line.length);
  expect(afterLine, matches(RegExp(r'^\s+')));
  final url = afterLine.trim();
  expect(url, matches(RegExp(r'^https?://\S+$')));
  expect(Uri.parse(url).path, '/invite/$_code');
}

List<String> _recordClipboard(WidgetTester tester) {
  final writes = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger
    ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        writes.add(
          (call.arguments as Map<Object?, Object?>)['text']! as String,
        );
      }
      return null;
    });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return writes;
}

List<Map<Object?, Object?>> _recordShares(WidgetTester tester) {
  final shares = <Map<Object?, Object?>>[];
  final messenger = tester.binding.defaultBinaryMessenger
    ..setMockMethodCallHandler(_shareChannel, (call) async {
      expect(call.method, 'share');
      shares.add(call.arguments as Map<Object?, Object?>);
      return 'dev.fluttercommunity.plus/share/success';
    });
  addTearDown(() => messenger.setMockMethodCallHandler(_shareChannel, null));
  return shares;
}

class _Account implements ConstellationAccountPort {
  @override
  Stream<String> get currentAccountChanges => Stream.value(_viewer.id);
}

const _tags = {'Gardening': 'tag-gardening', 'Neighbours': 'tag-neighbours'};

Future<void> _withField(
  WidgetTester tester,
  Future<void> Function(_FieldHarness) body, {
  bool enabled = true,
  Locale locale = const Locale('en'),
}) async {
  final sent = <WireSent>[];
  final server = _FieldServer();
  await withRemoteWire(
    {},
    sent,
    (remote) async {
      final sync = buildTestRealtimeSync();
      final tags = PeopleTagsCase(
        PeopleTagsRepository(remote),
        sync.case_,
        env: const Env(),
        logger: Logger.detached('AddPersonTagsTest'),
      );
      final getIt = GetIt.I
        ..pushNewScope(
          init: (scope) {
            scope
              ..registerSingleton<PeopleTagsCase>(tags)
              ..registerSingleton<PhantomRepositoryPort>(
                PhantomRepository(remote),
              );
          },
        );
      addTearDown(() async {
        await getIt.popScope();
        await tags.dispose();
        await sync.port.dispose();
      });
      await tags.load();
      expect(tags.tags.map((tag) => tag.name), unorderedEquals(_tags.keys));
      final field = _FieldHarness(
        sent,
        locale,
        ConstellationRepository(remote),
      );
      await field.mount(tester, enabled: enabled);
      await body(field);
    },
    responseFor: server.respond,
  );
}

class _FieldHarness {
  _FieldHarness(this.sent, this.locale, this.repository);

  final List<WireSent> sent;
  final Locale locale;
  final ConstellationRepository repository;
  late ConstellationCubit cubit;
  late FakeClockPort _clock;
  late FakeWakeUpPort _wakeUp;
  late TestRealtimeSyncPort _realtime;

  List<WireSent> _calls(String operation) =>
      sent.where((call) => call.operationName == operation).toList();
  List<WireSent> get creates => _calls('PhantomCreate');
  List<WireSent> get invites => _calls('PhantomInviteEnsure');
  List<WireSent> get tagWrites => _calls('PersonTagMembersApply');

  Future<void> mount(WidgetTester tester, {required bool enabled}) async {
    final sync = buildTestRealtimeSync();
    _clock = FakeClockPort(_now);
    _wakeUp = FakeWakeUpPort();
    _realtime = sync.port;
    final store = ConstellationFieldStoreCase(
      repository,
      _Account(),
      _clock,
      _wakeUp,
      sync.case_,
      env: const Env(),
      logger: Logger.detached('AddPersonFieldTest'),
      phantomsEnabled: enabled,
    );
    final fieldCubit = ConstellationCubit(
      case_: store,
      viewer: _viewer,
      loadOnCreate: false,
    );
    cubit = fieldCubit;
    addTearDown(() async {
      await fieldCubit.close();
      await store.dispose();
      await sync.port.dispose();
    });
    await tester.pump();
    await cubit.load();
    expect(cubit.state.loadError, isNull);
    expect(
      cubit.state.field,
      isNotNull,
      reason: 'the Field loaded its wire snapshot',
    );

    final phone = locale.languageCode == 'ru';
    if (phone) await usePhoneSurface(tester);
    final composer = buildComposerHarnessComposer(eligible: const {});
    await pumpConstellationBody(
      tester,
      cubit,
      size: phone ? kPhoneSurface : const Size(1200, 900),
      locale: locale,
      wrapBody: (body) => BlocProvider<ConstellationComposerCubit>.value(
        value: composer,
        child: Scaffold(
          body: Column(
            children: [
              ConstellationAppBarRow(
                legendExpanded: false,
                onToggleLegend: () {},
              ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_canvas, findsOneWidget);
  }

  Offset sceneAt(WidgetTester tester, Offset global) => cubit.graphController
      .viewportLocalToScene(global - tester.getTopLeft(_canvas));

  Future<void> deliverPersonChange(WidgetTester tester) async {
    // A successful create publishes a separate notification that prompts
    // open Fields to read again. Deliver it through the normal realtime seam.
    _realtime.emitChange(
      const RealtimeEntityChange(
        kind: RealtimeEntityKind.phantom,
        aggregateId: _newPerson,
        operation: RealtimeOperation.insert,
        source: RealtimeChangeSource.serverInvalidation,
      ),
    );
    await tester.pump();
    const refreshWindow = Duration(seconds: 3);
    _clock.advance(refreshWindow);
    _wakeUp.elapse(refreshWindow);
    await tester.pumpAndSettle();
  }

  void expectCreatedAt(Offset scene, {String? emoji}) {
    expect(creates, hasLength(1));
    final variables = creates.single.variables;
    expect(variables['name'], 'Anna');
    if (emoji != null) expect(variables['emoji'], emoji);
    final position = variables['position'] as Map<String, Object?>;
    final expected = constellationPointToV1Anchor((x: scene.dx, y: scene.dy));
    expect(position['coordinateSpaceVersion'], expected.coordinateSpaceVersion);
    expect(position['xUnits'], closeTo(expected.xUnits, 0.01));
    expect(position['yUnits'], closeTo(expected.yUnits, 0.01));
  }

  void expectPersonOnMap(Offset scene, {String? emoji}) {
    final createIndex = sent.indexOf(creates.single);
    expect(
      sent.skip(createIndex + 1).map((call) => call.operationName),
      contains('ConstellationFieldFetch'),
      reason: 'the app refreshes the Field after the create response',
    );
    const graphId = 'fh:$_newPerson';
    expect(find.byKey(const ValueKey(graphId)), findsOneWidget);
    final node = cubit.graphController.nodes.singleWhere(
      (node) => node.graphNodeId == graphId,
    );
    expect(node.label, 'Anna');
    if (emoji != null) {
      expect(
        find.descendant(
          of: find.byKey(const ValueKey(graphId)),
          matching: find.text(emoji),
        ),
        findsOneWidget,
      );
    }
    expect(
      (cubit.graphController.getPositionForId(graphId) - scene).distance,
      lessThan(2),
    );
    final targets = cubit.state.field!.resolvedAnchorProjection.anchors.map(
      (anchor) => (anchor.target.kind.wireValue, anchor.target.id),
    );
    expect(targets, contains(('PHANTOM', _newPerson)));
  }
}

class _FieldServer {
  Map<String, dynamic>? _person;
  bool _invited = false;
  final _memberTags = <String>[];

  Future<Map<String, dynamic>> respond(WireSent call) async {
    switch (call.operationName) {
      case 'ConstellationFieldFetch':
      case 'ConstellationAnchorsFetch':
        return _snapshot();
      case 'PhantomCreate':
        _person = call.variables;
        return {'phantomCreate': _newPerson};
      case 'PhantomInviteEnsure':
        _invited = true;
        return {'phantomInviteEnsure': _code};
      case 'PersonTags':
        return {
          'personTags': [
            for (final (index, tag) in _tags.entries.indexed)
              {
                '__typename': 'v2_PersonTag',
                'id': tag.value,
                'name': tag.key,
                'glyph': tag.key[0],
                'color': 2,
                'ord': index,
                'count': 0,
                'countOffField': 0,
              },
          ],
        };
      case 'PersonTagMemberships':
        return {'personTagMemberships': <Object?>[]};
      case 'PersonAutoTags':
        return {'personAutoTags': <Object?>[]};
      case 'PersonTagMembersApply':
        final ops = (call.variables['ops'] as List<Object?>)
            .cast<Map<String, Object?>>();
        _memberTags.addAll(
          ops
              .where((op) => op['personId'] == _newPerson && op['op'] == 'add')
              .map((op) => op['tagId']! as String),
        );
        return {'personTagMembersApply': true};
      default:
        throw StateError('Unexpected GraphQL operation ${call.operationName}');
    }
  }

  Map<String, dynamic> _snapshot() => {
    'constellationField': {
      '__typename': 'v2_ConstellationField',
      'loadedAt': _now.toIso8601String(),
      'context': '',
      'peersCapped': false,
      'requestsCapped': false,
      'directContactIds': <String>[],
      'peers': <Object?>[],
      'edges': <Object?>[],
      'requests': <Object?>[],
      'posts': <Object?>[],
      'memberWebs': <Object?>[],
      'phantoms': [
        if (_person case final person?)
          {
            '__typename': 'v2_ConstellationPhantom',
            'id': _newPerson,
            'displayName': person['name'],
            'emoji': person['emoji'],
            'hasPrivateAvatar': false,
            'ownTagIds': _memberTags,
            'pinState': 'pinned',
            'inviteState': _invited ? 'live' : 'none',
            'createdAt': _now.toIso8601String(),
          },
      ],
      'anchorProjection': {
        '__typename': 'v2_ConstellationAnchorProjection',
        'revision': _person == null ? '0' : '1',
        'anchors': [
          if (_person?['position'] case final Map<String, dynamic> position)
            {
              '__typename': 'v2_ConstellationAnchor',
              'targetKind': 'PHANTOM',
              'targetId': _newPerson,
              ...position,
              'revision': '1',
              'placedAt': _now.toIso8601String(),
            },
        ],
        'pinnedPeers': <Object?>[],
        'pinnedRequests': <Object?>[],
        'supportPeers': <Object?>[],
        'supportEdges': <Object?>[],
        'serverFilteredBeaconIds': <String>[],
        'serverFilteredBeaconCount': 0,
      },
    },
  };
}
