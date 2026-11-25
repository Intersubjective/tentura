import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/l10n/l10n.dart';

import 'support/e2e_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('touch long-press and mouse secondary-click on the Field both '
      'open the add-person sheet', (tester) async {
    await launchApp(app.main);
    final fixture = await bootstrapFixture(runId: uniqueRunId('add-person'));
    await loginAs(tester, fixture.authorEmail);
    await openConstellation(tester);

    final field = find.byType(ConstellationBody);
    final context = tester.element(field);
    final cubit = readConstellationCubit(tester);
    expect(cubit.phantomsEnabled, isTrue);
    final l10n = L10n.of(context);
    if (l10n == null) throw StateError('The Field has no localizations');
    final holdHint = find.byKey(const Key('constellation.field_hold_hint'));
    if (holdHint.evaluate().isNotEmpty) {
      await tapAndSettle(
        tester,
        find.descendant(of: holdHint, matching: find.text(l10n.buttonOk)),
      );
    }
    await pumpUntil(
      tester,
      () => cubit.fieldInitialFrameCompletedForTest,
      label: 'the Field camera has framed the map',
    );
    final viewer = find.descendant(
      of: field,
      matching: find.byType(InteractiveViewer),
    );
    final viewport = tester.renderObject(viewer);
    bool hitsViewport(Offset point) => tester
        .hitTestOnBinding(point)
        .path
        .any((entry) => entry.target == viewport);
    final point = _emptyFieldPoint(
      tester,
      tester.getRect(viewer),
      hitsViewport,
    );
    final menuEntry = find.descendant(
      of: find.byWidgetPredicate((widget) => widget is PopupMenuItem<Object?>),
      matching: find.text(l10n.personCreateCanvasAction),
    );
    final name = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == l10n.personCreateName,
    );

    Future<void> openSheet() async {
      await pumpUntilVisible(
        tester,
        menuEntry,
        label: 'add-person entry in the canvas create menu',
      );
      expect(
        find.byKey(const Key('constellation.canvas.create_menu.request')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('constellation.canvas.create_menu.post')),
        kPostsEnabled ? findsOneWidget : findsNothing,
      );
      await tapAndSettle(tester, menuEntry);
      await pumpUntilVisible(tester, name);
      expect(menuEntry, findsNothing);
      expect(find.text(l10n.personCreateSave), findsOneWidget);
      expect(find.text(l10n.personCreateCopyInvite), findsOneWidget);
      expect(find.text(l10n.personCreateShare), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await runE2eStep('touch long-press opens the add-person sheet', () async {
      await tester.longPressAt(point);
      await openSheet();
      Navigator.of(tester.element(name)).pop();
      await pumpUntil(
        tester,
        () => hitsViewport(point),
        label: 'Field accepts input after the sheet closes',
      );
      expect(name, findsNothing);
    });

    await runE2eStep(
      'mouse secondary-click opens the add-person sheet',
      () async {
        final mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await mouse.addPointer(location: point);
        await tester.pump();
        expect(hitsViewport(point), isTrue);
        await mouse.down(point);
        await tester.pump(const Duration(milliseconds: 50));
        await mouse.up();
        await mouse.removePointer();
        await openSheet();
      },
    );
  });
}

Offset _emptyFieldPoint(
  WidgetTester tester,
  Rect bounds,
  bool Function(Offset) hitsViewport,
) {
  final controller = readConstellationCubit(tester).graphController;
  final snapshot = controller.renderSnapshot;
  final nodeCentres = [
    for (final id in snapshot.topology.nodesById.keys)
      if (snapshot.resolvePosition(id) case final point?)
        globalForConstellationScene(tester, Offset(point.x, point.y)),
  ];
  final rejected = <String>[];
  // A phone's banners and controls can cover part of the map viewport.
  // Use a point whose hit test actually reaches the map, away from its nodes.
  for (final y in [0.5, 0.35, 0.65, 0.8]) {
    for (final x in [0.2, 0.8, 0.5]) {
      final point =
          bounds.topLeft + Offset(bounds.width * x, bounds.height * y);
      final scene = controller.globalToScene(point);
      final canPin =
          scene != null &&
          constellationPointWithinEnvelope((x: scene.dx, y: scene.dy));
      final empty = nodeCentres.every((node) => (point - node).distance > 56);
      final hitsMap = hitsViewport(point);
      if (canPin && empty && hitsMap) {
        return point;
      }
      rejected.add('$point scene=$scene empty=$empty map=$hitsMap');
    }
  }
  throw StateError(
    'No unobstructed empty point on the Field in $bounds. '
    'Nodes: $nodeCentres. Tried: $rejected',
  );
}
