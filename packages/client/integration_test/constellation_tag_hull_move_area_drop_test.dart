import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_state.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_graph_scene.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_hull_layer.dart';
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'support/browser_graphql_transport_probe.dart';
import 'support/e2e_test_helpers.dart';

// #1021 «Move area» on the real stack in a browser: a right click on empty
// space in a tag's hull offers «Move area «<tag>»»; after choosing it the
// area follows the mouse with no button held, and one left click drops it.
// The drop pins every member in ONE batch the server stores, offers ONE Undo
// that restores every member, survives «Done» and a Field reload, and opens
// no person panel although the click lands on a member carried under the
// pointer. The same on a 375×667 phone in Russian with a finger tap.
//
// Choosing «Move area» outside Arranging enters Arranging (kept on purpose),
// and Arranging stays open after the drop.

const _desktopWindow = Size(1280, 800);
const _phoneWindow = Size(375, 667);
const _bobUnits = Offset(-0.6, 1.2);
const _carolUnits = Offset(0.6, 1.2);
const _undoKey = Key('constellation.arranging.undo');
const _doneKey = Key('constellation.arranging.done');

Offset? _scene(WidgetTester tester, String personId) {
  final point = readConstellationCubit(tester).graphController.renderSnapshot
      .resolvePosition(
        constellationGraphNodeIdForTarget(
          ConstellationAnchorTarget.person(personId),
        ),
      );
  return point == null ? null : Offset(point.x, point.y);
}

ConstellationSelectionCubit _selection(WidgetTester tester) =>
    maybeConstellationSelection(
      tester.element(find.byType(ConstellationBody)),
    )!;

L10n _l10n(WidgetTester tester) =>
    L10n.of(tester.element(find.byType(ConstellationBody)))!;

void _setWindow(WidgetTester tester, Size window) {
  tester.view.physicalSize = window * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
}

/// Reloads the Field data the way a tab reselect does, holding the cubit the
/// Field already uses: while the new data loads the map may briefly be
/// rebuilt without its body.
Future<void> _reloadField(WidgetTester tester) async {
  final cubit = readConstellationCubit(tester);
  await cubit.load();
  await pumpUntil(
    tester,
    () =>
        finderHasMatch(find.byType(ConstellationBody)) &&
        cubit.state.field != null &&
        cubit.state.composition != null,
    label: 'Field reloaded',
    timeout: const Duration(seconds: 45),
  );
  await pumpBounded(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await pumpBounded(tester, frames: 24);
  await pumpUntil(
    tester,
    () =>
        readConstellationCubit(tester).state.placementPhase ==
        ConstellationPlacementPhase.idle,
    label: 'constellation placement idle',
    timeout: const Duration(seconds: 30),
  );
  await pumpBounded(tester, frames: 12);
}

Future<Map<String, Offset>> _savedUnits(List<String> ids) async {
  final anchors = await fetchConstellationAnchors();
  return {
    for (final id in ids)
      if (constellationAnchorByTarget(
            anchors,
            targetKind: 'PERSON',
            targetId: id,
          )
          case final anchor?)
        id: Offset(
          (anchor['xUnits'] as num).toDouble(),
          (anchor['yUnits'] as num).toDouble(),
        ),
  };
}

void _expectUnits(
  Map<String, Offset> actual,
  Map<String, Offset> expected, {
  required String reason,
}) {
  for (final MapEntry(:key, :value) in expected.entries) {
    expect(actual[key], isNotNull, reason: '$reason: $key keeps a saved pin');
    expect(actual[key]!.dx, closeTo(value.dx, 1e-3), reason: '$reason: $key x');
    expect(actual[key]!.dy, closeTo(value.dy, 1e-3), reason: '$reason: $key y');
  }
}

/// Anchor batches written since the probe was last cleared. Every step
/// clears the probe after its setup writes (made through the test helpers on
/// the same browser transport), so what is left is what the app sent.
List<Map<String, dynamic>> _appApplies(BrowserGraphqlTransportProbe network) =>
    network.applies;

/// Steps on the Field's Undo stack: the arrangement history the Undo button
/// walks back.
int _undoDepth() => GetIt.I<ConstellationPlacementCase>().history.length;

/// The click (or tap) about to drop the area lands on the person's node:
/// its centre is under the pointer.
void _expectPointerOnPerson(
  WidgetTester tester,
  Offset global,
  Iterable<String> personIds, {
  required String reason,
}) {
  final scene = readConstellationCubit(
    tester,
  ).graphController.globalToScene(global)!;
  final distances = {
    for (final id in personIds) id: (_scene(tester, id)! - scene).distance,
  };
  expect(
    distances.values.any((d) => d < 10),
    isTrue,
    reason: '$reason: the drop point is on a person node ($distances)',
  );
}

Set<String> _personTargets(Map<String, dynamic> apply) => {
  for (final op
      in ((apply['variables'] as Map)['ops'] as List)
          .cast<Map<String, dynamic>>())
    if (op['targetKind'] == 'PERSON') op['targetId'] as String,
};

/// Lets the app send and finish whatever it writes after a gesture: waits
/// (up to 10 s) until [atLeast] batches completed, then keeps pumping until
/// no new batch has started for 2 s, so a late duplicate batch is counted.
/// Does not fail when nothing is sent: the caller asserts the count.
Future<void> _letWritesLand(
  WidgetTester tester,
  BrowserGraphqlTransportProbe network, {
  required int atLeast,
}) async {
  bool landed() {
    final applies = _appApplies(network);
    return applies.length >= atLeast &&
        applies.every((e) => e['completed'] == true) &&
        !readConstellationCubit(tester).state.hasPendingPlacementWrite;
  }

  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline) && !landed()) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  // Quiet period: 2 s with no new batch.
  var count = _appApplies(network).length;
  var quietSince = DateTime.now();
  final quietDeadline = DateTime.now().add(const Duration(seconds: 8));
  while (DateTime.now().isBefore(quietDeadline) &&
      DateTime.now().difference(quietSince) < const Duration(seconds: 2)) {
    await tester.pump(const Duration(milliseconds: 100));
    final now = _appApplies(network).length;
    if (now != count) {
      count = now;
      quietSince = DateTime.now();
    }
  }
  // No wait for the move to end here: a drop that never ends the move must
  // show up as the assertions below failing, not as a timeout.
  await pumpBounded(tester, frames: 24);
}

bool _undoEnabled(WidgetTester tester) {
  final undo = find.byKey(_undoKey);
  return finderHasMatch(undo) &&
      tester.widget<IconButton>(undo.first).onPressed != null;
}

void _expectNoPersonPanel(WidgetTester tester, {required String reason}) {
  expect(
    readConstellationCubit(tester).state.selectedPersonId,
    isNull,
    reason: '$reason: the drop click selects nobody',
  );
  expect(
    find.byType(GraphPersonContextPanel),
    findsNothing,
    reason: '$reason: no person panel opens',
  );
}

/// Right click on [hullScene] (empty space inside the tag's hull); the menu
/// must offer exactly one entry, «Move area «[tagName]»». Returns the
/// global centre of that entry.
Future<Offset> _openMoveAreaMenu(
  WidgetTester tester,
  Offset hullScene,
  String tagName,
) async {
  final rightClick = await tester.startGesture(
    globalForConstellationScene(tester, hullScene),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await tester.pump();
  await rightClick.up();
  await rightClick.removePointer();
  final label = _l10n(tester).constellationTagHullMoveArea(tagName);
  await pumpUntilVisible(tester, find.text(label), label: 'the hull menu');
  await pumpBounded(tester, frames: 12);
  expect(
    find.byType(PopupMenuItem<bool>),
    findsOneWidget,
    reason: 'the hull menu has exactly one entry',
  );
  return tester.getCenter(find.text(label));
}

/// The desktop move: left click «Move area», hover (no button held) by
/// [travel] from the hull point, then one left click drops the area there.
/// The area's handle follows the pointer, so the drop click lands on a
/// member node.
Future<void> _mouseMoveArea(
  WidgetTester tester, {
  required Offset hullScene,
  required String tagName,
  required Offset travel,
  required Iterable<String> dropOnPersons,
}) async {
  final item = await _openMoveAreaMenu(tester, hullScene, tagName);
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: item);
  await tester.pump();
  await mouse.down(item);
  await tester.pump();
  await mouse.up();
  await pumpBounded(tester, frames: 24);
  expect(
    _selection(tester).state.arranging,
    isTrue,
    reason: 'choosing «Move area» enters Arranging',
  );
  final from = globalForConstellationScene(tester, hullScene);
  final to = from + travel;
  for (var i = 0; i <= 12; i++) {
    await mouse.moveTo(Offset.lerp(item, from, i / 12)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  for (var i = 1; i <= 12; i++) {
    await mouse.moveTo(Offset.lerp(from, to, i / 12)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(
    tester
        .widget<ConstellationTagHullLayer>(
          find.byType(ConstellationTagHullLayer),
        )
        .liftedTagId,
    isNotNull,
    reason: 'the area is lifted and follows the mouse',
  );
  _expectPointerOnPerson(tester, to, dropOnPersons, reason: 'mouse drop');
  await mouse.down(to);
  await tester.pump();
  await mouse.up();
  await tester.pump();
  await mouse.removePointer();
}

/// The phone move: tap «Переместить область», then a finger tap (a finger
/// has no hover) drops the area there. The tap lands on a person node away
/// from the lift point (where the handle already sits), so the area travels:
/// a carried member when one is on screen and uncovered, else another person
/// on the Field. A node off the 375 px screen cannot be tapped; when none
/// away from the lift point is on screen, the tap lands on the handle, the
/// carried member the lift put under the right-click point (on screen, as the
/// user just pressed there): the drop then keeps the lift's move.
Future<void> _touchMoveArea(
  WidgetTester tester, {
  required Offset hullScene,
  required String tagName,
  required List<String> members,
}) async {
  final item = await _openMoveAreaMenu(tester, hullScene, tagName);
  await tester.tapAt(item);
  await pumpBounded(tester, frames: 24);
  expect(
    _selection(tester).state.arranging,
    isTrue,
    reason: 'choosing «Move area» enters Arranging',
  );
  final others = [
    for (final peer in readConstellationCubit(tester).state.field!.peers)
      if (!members.contains(peer.id)) peer.id,
  ];
  // The map's viewport: chrome drawn over the map (toolbars, sheets) sits
  // beside it in the Field's stack, so a tap that reaches it reaches the map.
  final viewport = tester.renderObject(
    find
        .descendant(
          of: find.byType(ConstellationBody),
          matching: find.byType(InteractiveViewer),
        )
        .first,
  );
  final screen =
      Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
  String? target;
  Offset? at;
  final tried = <String>[];
  final handle = members.where(
    (id) => (_scene(tester, id)! - hullScene).distance <= 30,
  );
  for (final id in [
    ...members.where((id) => !handle.contains(id)),
    ...others,
    ...handle,
  ]) {
    final scene = _scene(tester, id);
    if (scene == null) continue;
    final global = globalForConstellationScene(tester, scene);
    tried.add('$id@$global');
    if (!screen.deflate(8).contains(global)) continue;
    if (tester
        .hitTestOnBinding(global)
        .path
        .any((entry) => entry.target == viewport)) {
      (target, at) = (id, global);
      break;
    }
  }
  expect(
    target,
    isNotNull,
    reason: 'a person node can be tapped on screen $screen: $tried',
  );
  _expectPointerOnPerson(tester, at!, [target!], reason: 'tap drop');
  await tester.tapAt(at);
  await tester.pump();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('«Move area» drop on the real Field: one batch, one Undo, '
      'persists after Done and reload, opens no person panel', (
    tester,
  ) async {
    e2eDrainExceptions = false;
    _setWindow(tester, _desktopWindow);
    await launchApp(app.main);
    await pumpBounded(tester);

    final runId = uniqueRunId('hull-move-area');
    final fixture = await bootstrapWitnessFixture(runId: runId);
    final bob = fixture.bobUserId;
    final carol = fixture.carolUserId;
    final members = [bob, carol];
    await loginAs(tester, fixture.aliceEmail);
    await pumpBounded(tester, frames: 12);

    final settings = GetIt.I<SettingsCubit>();
    final localeBefore = settings.state.localePreference;
    addTearDown(() => settings.setLocalePreference(localeBefore));

    final tagName = 'Area ${DateTime.now().millisecondsSinceEpoch % 100000}';
    final tagId = await createPersonTagWithMembers(
      name: tagName,
      personIds: members,
    );
    await openConstellation(tester);
    await pumpUntil(
      tester,
      () {
        final ids = {
          for (final p in readConstellationCubit(tester).state.field!.peers)
            p.id,
        };
        return ids.contains(bob) && ids.contains(carol);
      },
      label: 'Bob and Carol on the Field',
      timeout: const Duration(seconds: 45),
    );
    final original = {bob: _bobUnits, carol: _carolUnits};

    Future<void> resetPins() async {
      for (final MapEntry(:key, :value) in original.entries) {
        await upsertConstellationAnchor(
          targetKind: 'PERSON',
          targetId: key,
          xUnits: value.dx,
          yUnits: value.dy,
        );
      }
      // Close a person panel left open (as Esc does) and leave Arranging.
      readConstellationCubit(tester).selectPerson(null);
      _selection(tester).exitArranging();
      await pumpBounded(tester, frames: 8);
      await _reloadField(tester);
      await GetIt.I<PeopleTagsCase>().load();
      await setConstellationViewMode(tester, ConstellationViewMode.map);
      await pumpUntil(
        tester,
        () => _scene(tester, bob) != null && _scene(tester, carol) != null,
        label: 'Bob and Carol laid out',
        timeout: const Duration(seconds: 45),
      );
      readConstellationCubit(tester).graphController.fitToNodeIds([
        for (final id in members)
          constellationGraphNodeIdForTarget(
            ConstellationAnchorTarget.person(id),
          ),
      ], padding: 96);
      await _settle(tester);
      _expectUnits(await _savedUnits(members), original, reason: 'reset');
    }

    // A two-member hull is a disc around each member; its empty space above
    // Bob (his name label hangs below him) is where the user right-clicks.
    Offset emptyHullScene() =>
        _scene(tester, bob)! -
        const Offset(0, kConstellationTagHullPadding * 0.7);

    final network = BrowserGraphqlTransportProbe()..install();
    addTearDown(() {
      binding.reportData = {'lastTraffic': network.entries};
      network.dispose();
    });

    /// After a drop: exactly one new app batch reached the server, it pins
    /// exactly the tag's members, the server stores moved anchors, Undo is
    /// enabled, and no person panel opened. Returns the stored units.
    Future<Map<String, Offset>> expectOneBatchDrop(
      String when, {
      required int undoDepthBefore,
      List<String>? tagMembers,
    }) async {
      final members = tagMembers ?? [bob, carol];
      await _letWritesLand(tester, network, atLeast: 1);
      expect(
        readConstellationCubit(tester).state.placementPhase,
        ConstellationPlacementPhase.idle,
        reason: '$when: the drop ends the move',
      );
      final applies = _appApplies(network);
      expect(
        applies,
        hasLength(1),
        reason:
            '$when: the drop sends exactly one anchor batch to the server '
            '(writeCount=${readConstellationCubit(tester).writeCount})',
      );
      expect(
        _personTargets(applies.single),
        members.toSet(),
        reason: '$when: the batch pins exactly the tag members',
      );
      expect(
        (applies.single['response'] as Map?)?['errors'],
        isNull,
        reason: when,
      );
      await _settle(tester);
      final stored = await _savedUnits(members);
      for (final id in members) {
        expect(stored[id], isNotNull, reason: '$when: $id stays pinned');
        expect(
          (stored[id]! - original[id]!).distance,
          greaterThan(0.05),
          reason: '$when: the server stores $id where it was dropped',
        );
      }
      expect(_undoEnabled(tester), isTrue, reason: '$when: Undo is enabled');
      expect(
        _undoDepth(),
        undoDepthBefore + 1,
        reason: '$when: the whole area move is ONE Undo step',
      );
      _expectNoPersonPanel(tester, reason: when);
      expect(
        _selection(tester).state.arranging,
        isTrue,
        reason: '$when: Arranging stays open after the drop',
      );
      return stored;
    }

    Future<void> expectOneUndoRestores(
      String when, {
      required int undoDepthBefore,
      List<String>? tagMembers,
    }) async {
      final members = tagMembers ?? [bob, carol];
      network.clear();
      await tester.tap(find.byKey(_undoKey));
      await _letWritesLand(tester, network, atLeast: 1);
      expect(
        _appApplies(network),
        hasLength(1),
        reason: '$when: one Undo issues one more write',
      );
      _expectUnits(
        await _savedUnits(members),
        {for (final id in members) id: original[id]!},
        reason: '$when: one Undo puts every member back',
      );
      expect(
        _undoDepth(),
        undoDepthBefore,
        reason: '$when: the move is undone; Undo no longer offers it',
      );
      expect(
        _undoEnabled(tester),
        undoDepthBefore > 0,
        reason: '$when: Undo is enabled only for earlier moves',
      );
    }

    Future<void> expectPersistsAfterDoneAndReload(
      String when,
      Map<String, Offset> stored,
    ) async {
      final dropped = {for (final id in members) id: _scene(tester, id)!};
      await tapConstellationControl(tester, find.byKey(_doneKey));
      expect(_selection(tester).state.arranging, isFalse, reason: when);
      await _reloadField(tester);
      await setConstellationViewMode(tester, ConstellationViewMode.map);
      await pumpUntil(
        tester,
        () => members.every((id) => _scene(tester, id) != null),
        label: 'members laid out after reload',
        timeout: const Duration(seconds: 45),
      );
      await _settle(tester);
      final saved = await _savedUnits(members);
      _expectUnits(saved, stored, reason: '$when: after Done + reload');
      for (final id in members) {
        expect(
          (saved[id]! - original[id]!).distance,
          greaterThan(0.05),
          reason: '$when: $id is not back at its pre-move pin',
        );
        expect(
          (_scene(tester, id)! - dropped[id]!).distance,
          lessThan(2),
          reason: '$when: $id is drawn where it was dropped',
        );
      }
    }

    await runE2eStep('desktop outside Arranging: a left click drops the '
        'area in one batch and one Undo restores every member', () async {
      await resetPins();
      network.clear();
      final depth = _undoDepth();
      await _mouseMoveArea(
        tester,
        hullScene: emptyHullScene(),
        tagName: tagName,
        travel: const Offset(90, 50),
        dropOnPersons: members,
      );
      await expectOneBatchDrop('outside Arranging', undoDepthBefore: depth);
      await expectOneUndoRestores(
        'outside Arranging',
        undoDepthBefore: depth,
      );
    });

    await runE2eStep('desktop outside Arranging: the dropped area survives '
        'Done and a Field reload', () async {
      await resetPins();
      network.clear();
      final depth = _undoDepth();
      await _mouseMoveArea(
        tester,
        hullScene: emptyHullScene(),
        tagName: tagName,
        travel: const Offset(90, 50),
        dropOnPersons: members,
      );
      final stored = await expectOneBatchDrop(
        'outside Arranging, persist',
        undoDepthBefore: depth,
      );
      await expectPersistsAfterDoneAndReload(
        'outside Arranging',
        stored,
      );
    });

    await runE2eStep('desktop: after a move cancelled with Esc, the next '
        '«Move area» drop still writes one batch that survives Done and '
        'reload', () async {
      await resetPins();
      network.clear();
      final item = await _openMoveAreaMenu(tester, emptyHullScene(), tagName);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: item);
      await tester.pump();
      await mouse.down(item);
      await tester.pump();
      await mouse.up();
      await pumpBounded(tester, frames: 24);
      final from = globalForConstellationScene(tester, emptyHullScene());
      for (var i = 1; i <= 12; i++) {
        await mouse.moveTo(
          Offset.lerp(item, from + const Offset(60, 40), i / 12)!,
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      final depthBeforeEsc = _undoDepth();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await mouse.removePointer();
      await _settle(tester);
      await _letWritesLand(tester, network, atLeast: 0);
      expect(_appApplies(network), isEmpty, reason: 'Esc writes nothing');
      expect(
        _undoDepth(),
        depthBeforeEsc,
        reason: 'a cancelled move adds no Undo step',
      );
      // Arranging stays open after Esc; its Undo offers only the moves of
      // earlier steps, none for the cancelled one.
      expect(
        _undoEnabled(tester),
        depthBeforeEsc > 0,
        reason: 'Esc adds nothing for Undo to offer',
      );
      _expectUnits(await _savedUnits(members), original, reason: 'after Esc');

      final depth = _undoDepth();
      await _mouseMoveArea(
        tester,
        hullScene: emptyHullScene(),
        tagName: tagName,
        travel: const Offset(90, 50),
        dropOnPersons: members,
      );
      final stored = await expectOneBatchDrop(
        'after an Esc-cancelled move',
        undoDepthBefore: depth,
      );
      await expectPersistsAfterDoneAndReload(
        'after an Esc-cancelled move',
        stored,
      );
    });

    await runE2eStep('desktop in Arranging: the drop writes one batch, one '
        'Undo restores, and a second drop survives Done and reload', () async {
      await resetPins();
      _selection(tester).enterArranging();
      await pumpBounded(tester, frames: 8);
      network.clear();
      final depth = _undoDepth();
      await _mouseMoveArea(
        tester,
        hullScene: emptyHullScene(),
        tagName: tagName,
        travel: const Offset(-80, 60),
        dropOnPersons: members,
      );
      await expectOneBatchDrop('in Arranging', undoDepthBefore: depth);
      await expectOneUndoRestores('in Arranging', undoDepthBefore: depth);
      network.clear();
      await _mouseMoveArea(
        tester,
        hullScene: emptyHullScene(),
        tagName: tagName,
        travel: const Offset(-80, 60),
        dropOnPersons: members,
      );
      final stored = await expectOneBatchDrop(
        'in Arranging, persist',
        undoDepthBefore: depth,
      );
      await expectPersistsAfterDoneAndReload('in Arranging', stored);
    });

    await runE2eStep(
      'desktop: dropping the area onto a person outside the tag writes one '
      'batch of the members only and opens no panel for that person',
      () async {
        // Carol leaves the tag: she is now a non-member on the Field.
        await GetIt.I<PeopleTagsCase>().removeFromTag(
          personId: carol,
          tagId: tagId,
        );
        await resetPins();
        network.clear();
        final depth = _undoDepth();
        final from = globalForConstellationScene(tester, emptyHullScene());
        final onCarol = globalForConstellationScene(
          tester,
          _scene(tester, carol)!,
        );
        await _mouseMoveArea(
          tester,
          hullScene: emptyHullScene(),
          tagName: tagName,
          travel: onCarol - from,
          dropOnPersons: [carol],
        );
        await expectOneBatchDrop(
          'onto non-member Carol',
          undoDepthBefore: depth,
          tagMembers: [bob],
        );
        expect(
          _scene(tester, carol),
          isNotNull,
          reason: 'Carol is still on the Field',
        );
        _expectUnits(
          await _savedUnits([carol]),
          {carol: original[carol]!},
          reason: 'Carol is not in the tag and keeps her pin',
        );
        await expectOneUndoRestores(
          'onto non-member Carol',
          undoDepthBefore: depth,
          tagMembers: [bob],
        );
        // Carol rejoins the tag for the steps that follow.
        await GetIt.I<PeopleTagsCase>().addToTag(
          personId: carol,
          tagId: tagId,
        );
      },
    );

    await runE2eStep(
      '375×667 RU: one «Переместить область» entry; a tap '
      'drops the area in one batch that survives «Готово» and reload',
      () async {
        await settings.setLocalePreference(kLocalePreferenceRu);
        _setWindow(tester, _phoneWindow);
        await pumpBounded(tester, frames: 24);
        final ru = await L10n.delegate.load(const Locale('ru'));
        expect(
          ru.constellationTagHullMoveArea(tagName),
          'Переместить область «$tagName»',
        );
        await resetPins();
        network.clear();
        final depth = _undoDepth();
        await _touchMoveArea(
          tester,
          hullScene: emptyHullScene(),
          tagName: tagName,
          members: members,
        );
        final stored = await expectOneBatchDrop(
          '375×667 RU',
          undoDepthBefore: depth,
        );
        await expectPersistsAfterDoneAndReload('375×667 RU', stored);
      },
    );

    _selection(tester).exitArranging();
    await settings.setLocalePreference(localeBefore);
    await goToPath(tester, kPathMyWork);
    await pumpBounded(tester, frames: 24);
    await logout(tester);
    await pumpBounded(tester, frames: 48);
    final leaked = <Object?>[];
    Object? exception;
    while ((exception = tester.takeException()) != null) {
      leaked.add(exception);
    }
    expect(leaked, isEmpty, reason: 'uncaught async exceptions: $leaked');
  });
}
