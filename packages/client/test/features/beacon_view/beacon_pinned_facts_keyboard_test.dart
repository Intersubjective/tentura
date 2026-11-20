import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_fact_card.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_facts_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/remote_wire_harness.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart' show pumpUntil;

const _beaconId = 'Bfacts000001';
const _author = Profile(id: 'Uauthor00001', displayName: 'Author');
const _viewer = Profile(id: 'Uviewer000001', displayName: 'Viewer');
const _firstFact = 'Meeting at the station';
const _secondFact = 'Bring a flashlight';
const _openLabel = 'Open pinned facts';

final _l10n = lookupL10n(const Locale('ru'));
final _title = find.text(_l10n.beaconFactsSheetTitle);
final _close = find.widgetWithIcon(IconButton, Icons.close);
final _add = find.byKey(TestIds.key(TestIds.beaconFactsAdd));

Map<String, Object?> _factRow(
  String id,
  String text,
  DateTime createdAt,
  int visibility,
) => {
  '__typename': 'v2_BeaconFactCardRow',
  'id': id,
  'beaconId': _beaconId,
  'factText': text,
  'visibility': visibility,
  'pinnedBy': _author.id,
  'pinnedByTitle': _author.displayName,
  'status': BeaconFactCardStatusBits.active,
  'createdAt': createdAt.toIso8601String(),
  'attachmentsJson': '[]',
  'revisionSeq': 1,
  'otherEditorCount': 0,
  'historyTruncated': false,
  'savedByMe': false,
};

class _WireFacts extends FakeBeaconViewFactCardRepository {
  _WireFacts(this.repository);

  final BeaconFactCardRepository repository;

  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) =>
      repository.list(beaconId: beaconId);
}

Future<void> _openSheet(
  WidgetTester tester, {
  Profile profile = _author,
  bool twoFacts = false,
  int visibility = BeaconFactCardVisibilityBits.public,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final getIt = GetIt.instance;
  if (!getIt.isRegistered<Logger>()) {
    getIt.registerSingleton<Logger>(Logger('pinned facts test'));
    addTearDown(() async => getIt.unregister<Logger>());
  }

  final sent = <WireSent>[];
  final cubit = (await tester.runAsync(() async {
    late BeaconViewCubit cubit;
    await withRemoteWire(
      {
        'BeaconFactCardList': {
          '__typename': 'query_root',
          'BeaconFactCardList': [
            if (twoFacts)
              _factRow(
                'Fsecond00001',
                _secondFact,
                DateTime.utc(2026),
                visibility,
              ),
            _factRow(
              'Ffirst000001',
              _firstFact,
              DateTime.utc(2026, 1, 2),
              visibility,
            ),
          ],
        },
      },
      sent,
      (remote) async {
        await remote.getAuthToken();
        cubit = BeaconViewCubit(
          id: _beaconId,
          myProfile: profile,
          beaconViewCase: buildTestBeaconViewCase(
            beaconRepo: TrackingBeaconRepository()
              ..fetchByIdHandler = (_) async => Beacon(
                id: _beaconId,
                title: 'Station meeting',
                createdAt: DateTime.utc(2026),
                updatedAt: DateTime.utc(2026),
                author: _author,
              ),
            factCardsRepo: _WireFacts(BeaconFactCardRepository(remote)),
          ),
          effects: FakeUiEffectPort(),
        );
        addTearDown(cubit.close);
        await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);
      },
    );
    return cubit;
  }))!;
  expect(
    sent.map((request) => request.operationName),
    contains('BeaconFactCardList'),
  );
  expect(cubit.state.canCoordinateInBeaconRoom, profile == _author);

  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('ru'),
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                showBeaconPinnedFactsSheet(context, cubit: cubit),
              ),
              child: const Text(_openLabel),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text(_openLabel));
  await tester.pumpAndSettle();
  expect(_title, findsOneWidget);
  expect(find.text(_firstFact), findsOneWidget);
  expect(_add, profile == _author ? findsOneWidget : findsNothing);
}

Finder _card(String text) => find.ancestor(
  of: find.text(text),
  matching: find.byType(BeaconPinnedFactCard),
);

Finder _manage(String text) => find.descendant(
  of: _card(text),
  matching: find.widgetWithIcon(IconButton, Icons.more_horiz),
);

bool _hasPrimaryFocus(Finder control) {
  final elements = control.evaluate().toSet();
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  if (elements.contains(focused)) return true;
  var inside = false;
  focused.visitAncestorElements((element) {
    inside = elements.contains(element);
    return !inside;
  });
  return inside;
}

Future<void> _tab(WidgetTester tester, {bool backward = false}) async {
  final sheetRoute = ModalRoute.of(tester.element(_title));
  if (backward) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (backward) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
  final focused = FocusManager.instance.primaryFocus?.context;
  expect(focused, isNotNull, reason: 'Tab must keep focus in the dialog');
  expect(ModalRoute.of(focused!), same(sheetRoute));
}

Future<void> _tabTo(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 12 && !_hasPrimaryFocus(target); i++) {
    await _tab(tester);
  }
  expect(_hasPrimaryFocus(target), isTrue, reason: 'Tab should reach $target');
}

Future<void> _tabToManage(WidgetTester tester, String text) async {
  final manage = _manage(text);
  for (var i = 0; i < 12; i++) {
    await _tab(tester);
    if (_hasPrimaryFocus(manage)) return;
    if (_hasPrimaryFocus(_add) || _hasPrimaryFocus(_close)) break;
  }
  fail('Tab skipped the Manage fact button for "$text" before Add fact');
}

void _expectVisibleManageButton(WidgetTester tester, String text) {
  final card = _card(text);
  final icon = find.descendant(
    of: card,
    matching: find.byIcon(Icons.more_horiz),
  );
  expect(icon.hitTestable(), findsOneWidget);
  expect(
    find.descendant(
      of: card,
      matching: find.byTooltip(_l10n.beaconRoomFactManageSheetTitle),
    ),
    findsOneWidget,
  );
  RenderObject? ancestor = tester.renderObject(icon);
  while (ancestor != null) {
    if (ancestor is RenderOpacity) expect(ancestor.opacity, greaterThan(0));
    if (ancestor is RenderAnimatedOpacity) {
      expect(ancestor.opacity.value, greaterThan(0));
    }
    ancestor = ancestor.parent;
  }
}

void _expectFactActions(
  WidgetTester tester, {
  required String visibilityAction,
}) {
  final title = find.text(_l10n.beaconRoomFactManageSheetTitle);
  expect(title, findsOneWidget);
  final actionsRoute = ModalRoute.of(tester.element(title));
  expect(actionsRoute?.isCurrent, isTrue);
  for (final label in [
    _l10n.beaconRoomFactCardActionEdit,
    _l10n.beaconRoomFactCardActionEditHistory,
    visibilityAction,
    _l10n.beaconRoomFactCardActionRemove,
  ]) {
    final action = find.text(label);
    expect(action, findsOneWidget);
    expect(ModalRoute.of(tester.element(action)), same(actionsRoute));
  }
}

void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.linux);

  testWidgets('Enter and a mouse click open the same public fact actions', (
    tester,
  ) async {
    await _openSheet(tester);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(_card(_firstFact)));
    await tester.pumpAndSettle();
    _expectVisibleManageButton(tester, _firstFact);
    await mouse.moveTo(tester.getCenter(_manage(_firstFact)));
    await mouse.down(tester.getCenter(_manage(_firstFact)));
    await mouse.up();
    await mouse.removePointer();
    await tester.pumpAndSettle();
    _expectFactActions(
      tester,
      visibilityAction: _l10n.beaconRoomFactCardActionMakePrivate,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text(_l10n.beaconRoomFactManageSheetTitle), findsNothing);

    await _tabTo(tester, _close);
    await _tabToManage(tester, _firstFact);
    _expectVisibleManageButton(tester, _firstFact);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    _expectFactActions(
      tester,
      visibilityAction: _l10n.beaconRoomFactCardActionMakePrivate,
    );
  }, variant: desktop);

  testWidgets('Space opens private fact actions without mouse hover', (
    tester,
  ) async {
    await _openSheet(tester, visibility: BeaconFactCardVisibilityBits.room);
    await _tabTo(tester, _close);
    await _tabToManage(tester, _firstFact);
    _expectVisibleManageButton(tester, _firstFact);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    _expectFactActions(
      tester,
      visibilityAction: _l10n.beaconRoomFactCardActionMakePublic,
    );
  }, variant: desktop);

  testWidgets('Tab cycles inside the sheet and reaches each coordinator '
      'manage button in display order', (tester) async {
    await _openSheet(tester, profile: _viewer);
    await _tabTo(tester, _close);
    await _tab(tester);
    await _tabTo(tester, _close);
    expect(_add, findsNothing);
    await tester.tap(_close);
    await tester.pumpAndSettle();
    expect(_title, findsNothing);

    await _openSheet(tester, twoFacts: true);
    expect(
      tester.getTopLeft(_card(_firstFact)).dy,
      lessThan(tester.getTopLeft(_card(_secondFact)).dy),
    );
    await _tabTo(tester, _close);
    await _tab(tester, backward: true);
    expect(
      _hasPrimaryFocus(_add),
      isTrue,
      reason: 'Shift+Tab wraps to Add fact',
    );
    await _tab(tester);
    expect(_hasPrimaryFocus(_close), isTrue, reason: 'Tab wraps to Close');

    final visited = <String>[];
    for (var i = 0; i < 12; i++) {
      await _tab(tester);
      if (_hasPrimaryFocus(_add) || _hasPrimaryFocus(_close)) break;
      for (final text in [_firstFact, _secondFact]) {
        if (_hasPrimaryFocus(_manage(text))) visited.add(text);
      }
    }
    expect(visited, [_firstFact, _secondFact]);
    expect(_hasPrimaryFocus(_add), isTrue);
  }, variant: desktop);
}
