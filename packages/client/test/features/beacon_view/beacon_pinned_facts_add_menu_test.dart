// The Request Facts sheet's «Add fact» button opens a menu with two items:
// «New fact» (the composer) and «Pick from available» (the picker in bring
// mode, opening on «Saved»; plan docs/plans/fact-pick-from-available-1288.md).
// Only a viewer who can coordinate sees the button. The menu is reachable by
// keyboard. One test runs the pick through the real GraphQL wire, mapper and
// repository into BeaconViewCubit.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_picker_sheet.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_facts_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/fact_origin_test_support.dart';
import 'beacon_view_case_test_support.dart';

const _beaconId = 'Bsheet01';
const _otherBeacon = 'Bother0000001';
const _author = Profile(id: 'Uauthor', displayName: 'Author');
const _viewer = Profile(id: 'Uviewer', displayName: 'Viewer');

const _newFact = 'New fact';

// Item ids: `TestIds` must declare both (checked in the ids test below).
const _newItemId = 'beacon.facts.add.new';
const _pickItemId = 'beacon.facts.add.pick';
final _newItem = find.byKey(TestIds.key(_newItemId));
final _pickItem = find.byKey(TestIds.key(_pickItemId));
const _pickFromAvailable = 'Pick from available';
const _savedText = 'Shed code 4471';
const _savedId = 'Fother0000001';

final _t0 = DateTime.utc(2026);

Future<void> pumpUntil(
  Stream<BeaconViewState> stream,
  bool Function() condition,
) async {
  if (condition()) return;
  await stream
      .timeout(const Duration(seconds: 5))
      .firstWhere((_) => condition());
}

BeaconFactCard _card(String id, String text, {String beaconId = _beaconId}) =>
    BeaconFactCard(
      id: id,
      beaconId: beaconId,
      factText: text,
      visibility: BeaconFactCardVisibilityBits.public,
      pinnedBy: 'Uother',
      createdAt: _t0,
      status: BeaconFactCardStatusBits.active,
    );

BeaconSavedFact _saved(String id, String text, {required String beaconId}) => (
  factCardId: id,
  available: true,
  beaconId: beaconId,
  beaconKind: 0,
  factText: text,
  attachmentsJson: '[]',
);

Beacon _beacon() => Beacon(
  id: _beaconId,
  title: 'Facts beacon',
  createdAt: _t0,
  updatedAt: _t0,
  author: _author,
);

/// Facts of this Request plus a saved list; a copy adds a card here.
class _Repo extends FakeBeaconViewFactCardRepository {
  _Repo({super.cards, List<BeaconSavedFact>? saved}) : saved = saved ?? [];

  final List<BeaconSavedFact> saved;
  final copyCalls = <({String source, String destination})>[];

  @override
  Future<List<BeaconSavedFact>> savedList() async => List.of(saved);

  @override
  Future<List<BeaconFactSearchHit>> search({
    required String query,
    String? excludeBeaconId,
  }) async => [];

  @override
  Future<BeaconFactCopyResult> copy({
    required String sourceFactCardId,
    required String destinationBeaconId,
  }) async {
    copyCalls.add((
      source: sourceFactCardId,
      destination: destinationBeaconId,
    ));
    final text = saved.firstWhere((s) => s.factCardId == sourceFactCardId);
    final id = '$sourceFactCardId-copy';
    cards = [
      ...cards,
      _card(id, text.factText!, beaconId: destinationBeaconId),
    ];
    return (factCardId: id, outcome: BeaconFactCopyOutcome.created);
  }
}

void _registerLogger() {
  final getIt = GetIt.instance;
  if (getIt.isRegistered<Logger>()) return;
  getIt.registerSingleton<Logger>(Logger('test'));
  addTearDown(() {
    // ignore: discarded_futures -- best-effort unregister.
    getIt.unregister<Logger>();
  });
}

Future<BeaconViewCubit> _loadedCubit(
  WidgetTester tester,
  FakeBeaconViewFactCardRepository facts, {
  Profile profile = _author,
}) async {
  final cubit = (await tester.runAsync(() async {
    final case_ = buildTestBeaconViewCase(
      beaconRepo: TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => _beacon(),
      factCardsRepo: facts,
      roomRepo: FakeBeaconViewRoomRepository(),
    );
    final c = BeaconViewCubit(
      id: _beaconId,
      myProfile: profile,
      beaconViewCase: case_,
      effects: FakeUiEffectPort(),
    );
    await pumpUntil(c.stream, () => c.state.beaconContextLoaded);
    return c;
  }))!;
  addTearDown(cubit.close);
  return cubit;
}

Future<void> _openFactsSheet(
  WidgetTester tester,
  BeaconViewCubit cubit, {
  Locale locale = const Locale('en'),
}) async {
  await tester.binding.setSurfaceSize(const Size(375, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => unawaited(
                showBeaconPinnedFactsSheet(ctx, cubit: cubit),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

final _addButton = find.byKey(TestIds.key(TestIds.beaconFactsAdd));

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(_addButton);
  await tester.pumpAndSettle();
}

Finder _inPicker(Finder f) =>
    find.descendant(of: find.byType(FactPickerSheet), matching: f);

bool _focusIsWithin(Element element) {
  final focused = FocusManager.instance.primaryFocus?.context;
  var inside = focused == element;
  focused?.visitAncestorElements((a) {
    if (a == element) inside = true;
    return !inside;
  });
  return inside;
}

/// Presses [key] until the focused element is [target] or inside it; fails
/// when it never gets there.
Future<void> _focus(
  WidgetTester tester,
  Finder target, {
  LogicalKeyboardKey key = LogicalKeyboardKey.tab,
}) async {
  final element = target.evaluate().single;
  for (var i = 0; i < 20; i++) {
    if (_focusIsWithin(element)) return;
    await tester.sendKeyEvent(key);
    await tester.pump();
  }
  fail('keyboard focus never reached $target with $key');
}

/// Every widget carrying a TestIds key of the Add-fact family.
Finder _anyAddFamilyKey() => find.byWidgetPredicate((w) {
  final k = w.key;
  return k is ValueKey<String> && k.value.startsWith(TestIds.beaconFactsAdd);
});

/// The English and Russian values of every ARB key whose English value is
/// [english].
Map<String, String?> _arbEntries(String english) {
  Map<String, dynamic> read(String f) =>
      jsonDecode(File('l10n/$f').readAsStringSync()) as Map<String, dynamic>;
  final en = read('app_en.arb');
  final ru = read('app_ru.arb');
  return {
    for (final e in en.entries)
      if (!e.key.startsWith('@') && e.value == english)
        e.key: ru[e.key] as String?,
  };
}

void main() {
  testWidgets('Add fact opens a menu offering New fact and Pick from '
      'available', (tester) async {
    final cubit = await _loadedCubit(
      tester,
      _Repo(cards: [_card('f1', 'Fact f1')]),
    );
    await _openFactsSheet(tester, cubit);

    final l10n = lookupL10n(const Locale('en'));
    expect(
      find.descendant(
        of: _addButton,
        matching: find.text(l10n.beaconFactsAddFact),
      ),
      findsOneWidget,
    );
    expect(find.text(_newFact), findsNothing, reason: 'menu starts closed');

    await _openMenu(tester);

    expect(find.text(_newFact), findsOneWidget);
    expect(find.text(_pickFromAvailable), findsOneWidget);
    expect(find.byType(MenuItemButton), findsNWidgets(2));
    expect(_newItem, findsOneWidget);
    expect(_pickItem, findsOneWidget);
    expect(
      find.descendant(of: _newItem, matching: find.text(_newFact)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _pickItem, matching: find.text(_pickFromAvailable)),
      findsOneWidget,
    );
  });

  testWidgets('the menu items read in Russian', (tester) async {
    final cubit = await _loadedCubit(
      tester,
      _Repo(cards: [_card('f1', 'Fact f1')]),
    );
    await _openFactsSheet(tester, cubit, locale: const Locale('ru'));

    expect(
      find.descendant(of: _addButton, matching: find.text('Добавить факт')),
      findsOneWidget,
    );

    await _openMenu(tester);

    expect(
      find.descendant(of: _newItem, matching: find.text('Новый факт')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _pickItem,
        matching: find.text('Выбрать из доступных'),
      ),
      findsOneWidget,
    );
  });

  test('menu item ids are TestIds constants and both strings have RU '
      'translations', () {
    final ids = File('lib/ui/test_ids.dart').readAsStringSync();
    expect(ids, contains("'$_newItemId'"));
    expect(ids, contains("'$_pickItemId'"));
    final pick = _arbEntries(_pickFromAvailable);
    expect(pick, hasLength(1), reason: 'one key reads «Pick from available»');
    expect(pick.values.single, 'Выбрать из доступных');
    expect(_arbEntries(_newFact).values, contains('Новый факт'));
  });

  testWidgets('an empty Facts sheet still offers both items', (tester) async {
    final cubit = await _loadedCubit(tester, _Repo());
    await _openFactsSheet(tester, cubit);
    final l10n = lookupL10n(const Locale('en'));
    expect(find.text(l10n.beaconFactsSheetEmpty), findsOneWidget);

    await _openMenu(tester);

    expect(find.text(_newFact), findsOneWidget);
    expect(find.text(_pickFromAvailable), findsOneWidget);
  });

  for (final withFacts in [true, false]) {
    testWidgets('a viewer who cannot coordinate sees no Add fact menu '
        '(${withFacts ? 'with' : 'without'} facts)', (tester) async {
      final cubit = await _loadedCubit(
        tester,
        _Repo(cards: [if (withFacts) _card('f1', 'Fact f1')]),
        profile: _viewer,
      );
      await _openFactsSheet(tester, cubit);

      expect(_addButton, findsNothing);
      expect(find.text(_newFact), findsNothing);
      expect(find.text(_pickFromAvailable), findsNothing);
      expect(find.byType(MenuItemButton), findsNothing);
      expect(_newItem, findsNothing);
      expect(_pickItem, findsNothing);
      expect(_anyAddFamilyKey(), findsNothing);
    });
  }

  testWidgets('New fact opens the composer and closes the menu', (
    tester,
  ) async {
    final cubit = await _loadedCubit(
      tester,
      _Repo(cards: [_card('f1', 'Fact f1')]),
    );
    await _openFactsSheet(tester, cubit);
    await _openMenu(tester);
    expect(find.byType(MenuItemButton), findsNWidgets(2));

    await tester.tap(find.text(_newFact));
    await tester.pumpAndSettle();

    final l10n = lookupL10n(const Locale('en'));
    expect(find.byType(MenuItemButton), findsNothing);
    expect(find.text(l10n.beaconFactsComposerTitle), findsOneWidget);
    expect(find.byType(FactPickerSheet), findsNothing);
  });

  group('Pick from available', () {
    Future<_Repo> openPicker(WidgetTester tester) async {
      _registerLogger();
      final repo = _Repo(
        cards: [_card('f1', 'Fact f1')],
        saved: [
          _saved('Fhere00000001', 'Saved in this Request', beaconId: _beaconId),
          _saved(_savedId, _savedText, beaconId: _otherBeacon),
        ],
      );
      registerFactRepository(repo);
      final cubit = await _loadedCubit(tester, repo);
      await _openFactsSheet(tester, cubit);
      await _openMenu(tester);
      await tester.tap(find.text(_pickFromAvailable));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('opens the picker on Saved without an «In this Request» '
        'scope and hides saved facts of this Request', (tester) async {
      await openPicker(tester);

      expect(find.byType(FactPickerSheet), findsOneWidget);
      expect(find.byType(MenuItemButton), findsNothing);
      final tabs = tester.widget<TenturaUnderlineTabs>(
        _inPicker(find.byType(TenturaUnderlineTabs)),
      );
      expect(tabs.tabs, hasLength(2));
      expect(
        tabs.tabs[0],
        lookupL10n(const Locale('en')).beaconRoomFactPickerTabSaved,
      );
      expect(tabs.selectedIndex, 0);
      expect(_inPicker(find.text('In this Request')), findsNothing);
      expect(_inPicker(find.text(_savedText)), findsOneWidget);
      expect(_inPicker(find.text('Saved in this Request')), findsNothing);
    });

    testWidgets('picking a saved fact of another Request copies it here and '
        'the Facts sheet shows it without reopening', (tester) async {
      final repo = await openPicker(tester);
      expect(find.text(_savedText), findsOneWidget);

      await tester.tap(_inPicker(find.text(_savedText)));
      await tester.pumpAndSettle();

      expect(repo.copyCalls, [(source: _savedId, destination: _beaconId)]);
      expect(find.byType(FactPickerSheet), findsNothing);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('Fact added', findRichText: true),
        ),
        findsOneWidget,
      );
      final l10n = lookupL10n(const Locale('en'));
      expect(find.text(l10n.beaconFactsSheetTitle), findsOneWidget);
      expect(find.text('Fact f1'), findsOneWidget);
      expect(find.text(_savedText), findsOneWidget);
    });
  });

  group('keyboard', () {
    Future<void> openFocused(WidgetTester tester) async {
      _registerLogger();
      final repo = _Repo(
        cards: [_card('f1', 'Fact f1')],
        saved: [_saved(_savedId, _savedText, beaconId: _otherBeacon)],
      );
      registerFactRepository(repo);
      final cubit = await _loadedCubit(tester, repo);
      await _openFactsSheet(tester, cubit);
      await _focus(tester, _addButton);
    }

    testWidgets('Enter on the focused Add fact button opens the menu', (
      tester,
    ) async {
      await openFocused(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text(_newFact), findsOneWidget);
      expect(find.text(_pickFromAvailable), findsOneWidget);
    });

    testWidgets('Arrow Down then Enter picks Pick from available', (
      tester,
    ) async {
      await openFocused(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text(_pickFromAvailable), findsOneWidget);

      final item = find.ancestor(
        of: find.text(_pickFromAvailable),
        matching: find.byType(MenuItemButton),
      );
      await _focus(tester, item, key: LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byType(FactPickerSheet), findsOneWidget);
    });

    testWidgets('Escape closes the open menu and opens nothing', (
      tester,
    ) async {
      await openFocused(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNWidgets(2));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      final l10n = lookupL10n(const Locale('en'));
      expect(find.text(_newFact), findsNothing);
      expect(find.text(_pickFromAvailable), findsNothing);
      expect(find.text(l10n.beaconFactsComposerTitle), findsNothing);
      expect(find.byType(FactPickerSheet), findsNothing);
      expect(find.text(l10n.beaconFactsSheetTitle), findsOneWidget);
    });
  });

  testWidgets('real wire: picking a saved fact copies it through GraphQL and '
      'the cubit refreshes the sheet', (tester) async {
    _registerLogger();
    final operations = <String>[];
    Map<String, dynamic>? copyVars;
    var copied = false;

    Map<String, Object?> row(String id, String text) => {
      '__typename': 'v2_BeaconFactCardRow',
      'id': id,
      'beaconId': _beaconId,
      'factText': text,
      'visibility': BeaconFactCardVisibilityBits.public,
      'pinnedBy': 'Uother',
      'pinnedByTitle': 'Other',
      'sourceMessageId': null,
      'status': BeaconFactCardStatusBits.active,
      'createdAt': _t0.toIso8601String(),
      'updatedAt': null,
      'attachmentsJson': '[]',
      'revisionSeq': 1,
      'lastEditedBy': null,
      'lastEditedByTitle': null,
      'lastEditedAt': null,
      'otherEditorCount': 0,
      'historyTruncated': false,
      'originBeaconKind': null,
      'savedByMe': false,
    };

    http.Response json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

    final repository = (await tester.runAsync(
      () => http.runWithClient(
        () async {
          final remote = RemoteApiService(
            const Env(),
            const WebSocketClientRealtimeSocketFactory(),
          );
          await remote.setSessionAuth();
          await remote.getAuthToken();
          addTearDown(remote.close);
          return BeaconFactCardRepository(remote);
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/session/access-token')) {
            return json({
              'subject': _author.id,
              'access_token': 'test-token',
              'expires_in': 3600,
            });
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final name = body['operationName'] as String;
          operations.add(name);
          return json({
            'data': switch (name) {
              'BeaconFactCardList' => {
                '__typename': 'query_root',
                'BeaconFactCardList': [
                  row('f1', 'Fact f1'),
                  if (copied) row('Fcopied000001', _savedText),
                ],
              },
              'BeaconFactCardSavedList' => {
                '__typename': 'query_root',
                'BeaconFactCardSavedList': [
                  {
                    '__typename': 'v2_BeaconFactCardSavedRow',
                    'factCardId': _savedId,
                    'available': true,
                    'beaconId': _otherBeacon,
                    'beaconKind': 0,
                    'factText': _savedText,
                    'attachmentsJson': '[]',
                  },
                ],
              },
              'BeaconFactCardCopy' => () {
                copied = true;
                copyVars = body['variables'] as Map<String, dynamic>;
                return {
                  '__typename': 'mutation_root',
                  'BeaconFactCardCopy': {
                    '__typename': 'v2_BeaconFactCardCopyResult',
                    'factCardId': 'Fcopied000001',
                    'outcome': 'created',
                  },
                };
              }(),
              _ => null,
            },
          });
        }),
      ),
    ))!;
    registerFactRepository(repository);
    final cubit = await _loadedCubit(tester, _WireFacts(repository));

    await _openFactsSheet(tester, cubit);
    expect(find.text('Fact f1'), findsOneWidget);
    expect(find.text(_savedText), findsNothing);

    await _openMenu(tester);
    await tester.tap(find.text(_pickFromAvailable));
    await tester.pumpAndSettle();
    await tester.tap(_inPicker(find.text(_savedText)));
    await tester.runAsync(
      () => Future<void>.delayed(
        const Duration(milliseconds: 100),
      ),
    );
    await tester.pumpAndSettle();

    expect(operations.where((o) => o == 'BeaconFactCardCopy'), hasLength(1));
    expect(copyVars, {
      'sourceFactCardId': _savedId,
      'destinationBeaconId': _beaconId,
    });
    expect(
      cubit.state.factCards.map((f) => f.id),
      containsAll(['f1', 'Fcopied000001']),
    );
    expect(find.byType(FactPickerSheet), findsNothing);
    expect(find.text(_savedText), findsOneWidget);
  });
}

/// The view case's fact list read through the real repository.
class _WireFacts extends FakeBeaconViewFactCardRepository {
  _WireFacts(this.real);

  final BeaconFactCardRepository real;

  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) =>
      real.list(beaconId: beaconId);
}
