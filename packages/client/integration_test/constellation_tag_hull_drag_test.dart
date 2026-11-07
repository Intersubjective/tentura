import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_state.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_graph_scene.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_hull_layer.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'support/e2e_test_helpers.dart';

// #1021 on the real stack in a browser: press and hold on empty space in a
// tag's hull lifts the whole tag; a quick drag there pans; a hold on a node
// lifts only that node; release pins, one Undo restores; the hull's
// screen-reader text is Russian.

const _bobUnits = Offset(-0.6, 1.2);
const _carolUnits = Offset(0.6, 1.2);

Offset? _scene(WidgetTester tester, String personId) {
  final point = readConstellationCubit(tester).graphController.renderSnapshot
      .resolvePosition(
        constellationGraphNodeIdForTarget(
          ConstellationAnchorTarget.person(personId),
        ),
      );
  return point == null ? null : Offset(point.x, point.y);
}

Offset _cameraOrigin(WidgetTester tester) =>
    readConstellationCubit(tester).graphController.sceneToViewportLocal(
      Offset.zero,
    );

ConstellationSelectionCubit _selection(WidgetTester tester) =>
    maybeConstellationSelection(
      tester.element(find.byType(ConstellationBody)),
    )!;

Future<void> _moveInSteps(
  WidgetTester tester,
  TestGesture gesture, {
  Offset step = const Offset(10, 6),
}) async {
  for (var i = 0; i < 8; i++) {
    await gesture.moveBy(step);
    await tester.pump(const Duration(milliseconds: 16));
  }
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

void _expectUnits(Map<String, Offset> actual, Map<String, Offset> expected) {
  for (final MapEntry(:key, :value) in expected.entries) {
    expect(actual[key], isNotNull, reason: '$key keeps a saved pin');
    expect(actual[key]!.dx, closeTo(value.dx, 1e-3), reason: '$key x');
    expect(actual[key]!.dy, closeTo(value.dy, 1e-3), reason: '$key y');
  }
}

/// Taps the Undo the user sees right after a drop: the Arranging toolbar's
/// Undo, or an Undo snack bar action.
Future<void> _tapVisibleUndo(WidgetTester tester, L10n l10n) async {
  final toolbarUndo = find.byKey(const Key('constellation.arranging.undo'));
  final snackUndo = find.byWidgetPredicate(
    (widget) =>
        widget is SnackBarAction && widget.label == l10n.constellationUndo,
  );
  await pumpUntil(
    tester,
    () =>
        (finderHasMatch(toolbarUndo) &&
            tester.widget<IconButton>(toolbarUndo.first).onPressed != null) ||
        finderHasMatch(snackUndo),
    label: 'an Undo offered after the drop',
  );
  final toolbarEnabled =
      finderHasMatch(toolbarUndo) &&
      tester.widget<IconButton>(toolbarUndo.first).onPressed != null;
  await tester.tap(toolbarEnabled ? toolbarUndo.first : snackUndo.first);
  await _settle(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tag hull press-and-hold drag on the real Field', (
    tester,
  ) async {
    e2eDrainExceptions = false;
    await launchApp(app.main);
    await pumpBounded(tester);

    final runId = uniqueRunId('hull-drag');
    final fixture = await bootstrapWitnessFixture(runId: runId);
    final bob = fixture.bobUserId;
    final carol = fixture.carolUserId;
    await loginAs(tester, fixture.aliceEmail);
    await pumpBounded(tester, frames: 12);

    final settings = GetIt.I<SettingsCubit>();
    final localeBefore = settings.state.localePreference;
    await settings.setLocalePreference(kLocalePreferenceRu);
    await pumpBounded(tester, frames: 12);
    final ru = await L10n.delegate.load(const Locale('ru'));

    final tagName = 'Круг ${DateTime.now().millisecondsSinceEpoch % 100000}';
    await createPersonTagWithMembers(name: tagName, personIds: [bob, carol]);
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
    for (final MapEntry(:key, :value) in original.entries) {
      await upsertConstellationAnchor(
        targetKind: 'PERSON',
        targetId: key,
        xUnits: value.dx,
        yUnits: value.dy,
      );
    }
    await reloadConstellation(tester);
    await GetIt.I<PeopleTagsCase>().load();
    await setConstellationViewMode(tester, ConstellationViewMode.map);
    await pumpUntil(
      tester,
      () => _scene(tester, bob) != null && _scene(tester, carol) != null,
      label: 'Bob and Carol laid out',
      timeout: const Duration(seconds: 45),
    );
    // Frame the tagged pair as a user zooming in on it would: at the
    // whole-Field zoom a touch target around a node covers the space
    // between them.
    readConstellationCubit(tester).graphController.fitToNodeIds([
      for (final id in [bob, carol])
        constellationGraphNodeIdForTarget(ConstellationAnchorTarget.person(id)),
    ], padding: 96);
    await _settle(tester);
    debugPrint(
      '[e2e] hull drag camera scale='
      '${readConstellationCubit(tester).graphController.cameraScale}',
    );

    // A two-member hull is a disc around each member; grab its empty space
    // above Bob (his name label hangs below him).
    Offset emptyHullScene() =>
        _scene(tester, bob)! -
        const Offset(0, kConstellationTagHullPadding * 0.7);
    expect(
      readConstellationCubit(tester).mapNodeAtSceneCentre(emptyHullScene()),
      isNull,
      reason: 'the grab point is empty hull space, not a node',
    );

    await runE2eStep('hull semantics are Russian', () async {
      final handle = tester.ensureSemantics();
      await pumpBounded(tester);
      // The hull's own node; people nodes also list their tags, next to
      // their (Latin, user-data) display names.
      final texts = <String>[];
      void visit(SemanticsNode node) {
        final data = node.getSemanticsData();
        if (data.label.contains(tagName) && data.hint.isNotEmpty) {
          texts.add(
            '${data.label} ${data.hint}'.replaceAll(tagName, '').trim(),
          );
        }
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(
        tester
            .binding
            .renderViews
            .first
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!,
      );
      expect(
        texts.where((t) => t.contains(ru.constellationTagHullDragHint)),
        isNotEmpty,
        reason: 'the hull names its tag and the press-and-hold move: $texts',
      );
      for (final text in texts) {
        expect(text, isNot(contains(RegExp('[A-Za-z]'))), reason: text);
      }
      handle.dispose();
    });

    for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
      for (final arranging in [false, true]) {
        final mode = arranging ? 'while Arranging' : 'outside Arranging';
        final input = '${kind.name} $mode';

        Future<void> setMode() async {
          final selection = _selection(tester);
          if (arranging) {
            selection.enterArranging();
          } else {
            selection.exitArranging();
          }
          await pumpBounded(tester, frames: 8);
        }

        await runE2eStep('$input: a quick drag on the hull pans', () async {
          await setMode();
          final writes = readConstellationCubit(tester).writeCount;
          final bobBefore = _scene(tester, bob)!;
          final cameraBefore = _cameraOrigin(tester);
          final gesture = await tester.startGesture(
            globalForConstellationScene(tester, emptyHullScene()),
            kind: kind,
          );
          await _moveInSteps(tester, gesture);
          expect(_cameraOrigin(tester), isNot(cameraBefore), reason: 'pans');
          expect(_scene(tester, bob), bobBefore, reason: 'no node moves');
          // Pan back so the hull stays in view for the next steps.
          await _moveInSteps(tester, gesture, step: const Offset(-10, -6));
          await gesture.up();
          await _settle(tester);
          expect(_scene(tester, bob), bobBefore, reason: 'no node moves');
          expect(
            readConstellationCubit(tester).writeCount,
            writes,
            reason: 'panning saves nothing',
          );
          _expectUnits(await _savedUnits([bob, carol]), original);
        });

        await runE2eStep('$input: a hold on the hull moves the whole tag, '
            'release pins it, Undo restores', () async {
          await setMode();
          final writes = readConstellationCubit(tester).writeCount;
          final bobBefore = _scene(tester, bob)!;
          final carolBefore = _scene(tester, carol)!;
          final cameraBefore = _cameraOrigin(tester);
          final gesture = await tester.startGesture(
            globalForConstellationScene(tester, emptyHullScene()),
            kind: kind,
          );
          await tester.pump(const Duration(milliseconds: 550));
          await _moveInSteps(tester, gesture);
          final bobDelta = _scene(tester, bob)! - bobBefore;
          final carolDelta = _scene(tester, carol)! - carolBefore;
          expect(
            bobDelta.distance,
            greaterThan(25),
            reason:
                'tag lifted (bob=$bobDelta carol=$carolDelta '
                'arranging=${_selection(tester).state.arranging})',
          );
          expect(
            (carolDelta - bobDelta).distance,
            lessThan(1),
            reason: 'every member follows the hull',
          );
          expect(_cameraOrigin(tester), cameraBefore, reason: 'no pan');
          await gesture.up();
          await _settle(tester);
          expect(
            readConstellationCubit(tester).writeCount,
            writes + 1,
            reason: 'one batch pins the whole tag',
          );
          final dropped = await _savedUnits([bob, carol]);
          for (final id in [bob, carol]) {
            expect(dropped[id], isNot(original[id]), reason: '$id re-pinned');
          }
          await _tapVisibleUndo(tester, ru);
          _expectUnits(await _savedUnits([bob, carol]), original);
        });

        await runE2eStep(
          '$input: a hold on a node lifts only that node',
          () async {
            await setMode();
            final bobBefore = _scene(tester, bob)!;
            final carolBefore = _scene(tester, carol)!;
            final gesture = await tester.startGesture(
              globalForConstellationScene(tester, bobBefore),
              kind: kind,
            );
            await tester.pump(const Duration(milliseconds: 550));
            await _moveInSteps(tester, gesture);
            expect(
              (_scene(tester, bob)! - bobBefore).distance,
              greaterThan(25),
              reason: 'the held node moves',
            );
            expect(_scene(tester, carol), carolBefore, reason: 'Carol stays');
            await gesture.up();
            await _settle(tester);
            final dropped = await _savedUnits([bob, carol]);
            expect(dropped[bob], isNot(original[bob]), reason: 'Bob re-pinned');
            _expectUnits(dropped, {carol: original[carol]!});
            // Put Bob back for the next step; the Undo is proven for the
            // hull drop above, a single-node drop is not this feature.
            await upsertConstellationAnchor(
              targetKind: 'PERSON',
              targetId: bob,
              xUnits: original[bob]!.dx,
              yUnits: original[bob]!.dy,
            );
            await reloadConstellation(tester);
            await _settle(tester);
            _expectUnits(await _savedUnits([bob, carol]), original);
          },
        );
      }
    }

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
