// Real browser, real stack: a cold boot of the app on the Field URL — what a
// reload (F5) of the Field does — shows every person on the Field inside the
// main Field viewport before the user touches anything. Nobody presses
// «Показать всё поле» and nobody pans or zooms: the Field must not stay a
// blank map (contour only) while the minimap already shows the people.
//
// The viewer's Field is like the accounts QA reloads with: people in a tag
// whose saved magnet sits away from the viewer. The first boot signs the
// viewer in, sets that up and checks their Field has people; the test then
// puts the browser on the Field URL and boots the app again from scratch in
// the same page (fresh dependencies, session from the stored
// account, the Field URL as the initial route), so the Field mounts as the
// first screen like after a reload.
//
// The reload keeps the order seen on the dev host (bead notes, 2026-11-10):
// the Field's people are laid out and framed first, and the saved tag magnet
// read finishes afterwards and re-seats the tagged people away from the
// viewer. The test holds that read in the browser's network layer until the
// Field's first automatic frame has run, then lets it through; no repository
// or response is faked. Before the fix the camera stayed on the first frame
// and the re-seated people were left outside the map.
//
// Each test sets the app's window itself — 1280×800, or 375×667 in Russian
// — before the reload and checks the app really got that size, so one run
// covers both windows QA reloads in (the runner's default 1600×1024 Chrome
// window holds either). The resize test then changes the window of the open
// Field, 1280×800 → 375×667 → 1280×800, as QA did with device emulation.
//   ./scripts/run_client_integration_web_local.sh \
//     integration_test/constellation_field_cold_reload_frames_every_node_test.dart

import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_tag_magnet_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_viewport_overlay.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/test_ids.dart';
import 'package:web/web.dart' as web;

import 'support/e2e_test_helpers.dart';

/// The desktop window and the phone (iPhone SE) QA reloads the Field in.
const _desktopWindow = Size(1280, 800);
const _phoneWindow = Size(375, 667);

/// How long after the Field's people are laid out (or the window changes)
/// the camera may take to frame them. QA saw the map blank for 10–13 s; a working Field frames
/// within a few frames.
const _frameDeadline = Duration(seconds: 5);

@JS('eval')
external JSAny? _evaluate(JSString source);

/// Holds the app's saved tag magnet read (`ConstellationTagMagnets`) in the
/// browser's fetch until [release]: the server still answers it, only later.
final class _MagnetReadGate {
  void install() => _evaluate(
    r"""
(() => {
  const original = window.fetch;
  const gate = { held: 0, open: false, waiting: [],
    release() { this.open = true; for (const r of this.waiting.splice(0)) r(); },
    restore() { this.release(); window.fetch = original; delete window.__dc48MagnetGate; } };
  window.__dc48MagnetGate = gate;
  window.fetch = async function(input, init) {
    const request = new Request(input, init);
    if (!gate.open && /\/graphql(?:\?|$)/.test(request.url)) {
      const body = await request.clone().text();
      if (body.includes('ConstellationTagMagnets')) {
        gate.held++;
        await new Promise(resolve => gate.waiting.push(resolve));
      }
    }
    return original.call(this, input, init);
  };
})();
"""
        .toJS,
  );

  /// How many magnet reads are being held now or were held.
  int get held =>
      (_evaluate('window.__dc48MagnetGate.held'.toJS)! as JSNumber).toDartInt;

  void release() => _evaluate('window.__dc48MagnetGate.release()'.toJS);

  void restore() => _evaluate(
    'window.__dc48MagnetGate && window.__dc48MagnetGate.restore()'.toJS,
  );
}

Finder get _fieldViewport => find.descendant(
  of: find.byType(ConstellationBody),
  matching: find.byType(InteractiveViewer),
);

InteractiveViewer _fieldViewer(WidgetTester tester) =>
    tester.widget<InteractiveViewer>(_fieldViewport);

/// The Field viewport (the map the camera draws into) in its own coordinates.
Rect _viewportRect(WidgetTester tester) =>
    Offset.zero & tester.getSize(_fieldViewport);

/// Every node the Field has placed: what the minimap draws.
Set<String> _placedNodeIds(ConstellationCubit cubit) {
  final snapshot = cubit.graphController.renderSnapshot;
  return {
    for (final id in snapshot.topology.nodesById.keys)
      if (snapshot.resolvePosition(id) != null) id,
  };
}

bool _inside(Rect outer, Rect inner) =>
    inner.left >= outer.left - 0.5 &&
    inner.top >= outer.top - 0.5 &&
    inner.right <= outer.right + 0.5 &&
    inner.bottom <= outer.bottom + 0.5;

/// Placed nodes the current camera does not draw fully inside the viewport,
/// read from the frame the Field drew for that camera (the frame its viewport
/// overlay paints the node bodies from — the same measure the Field's camera
/// widget tests use); null while no frame
/// for the current camera has been drawn yet.
List<String>? _nodesOutOfView(WidgetTester tester, ConstellationCubit cubit) {
  final frame = tester
      .widget<ConstellationViewportOverlay>(
        find.byType(ConstellationViewportOverlay),
      )
      .frameHolder
      .frame;
  if (frame == null ||
      frame.cameraRevision != cubit.graphController.cameraRevision.value) {
    return null;
  }
  final viewport = _viewportRect(tester);
  return [
    for (final id in _placedNodeIds(cubit))
      if (frame.bodies[id] == null || !_inside(viewport, frame.bodies[id]!))
        '$id ${frame.bodies[id]}',
  ];
}

/// Sets the app's window to [window] logical pixels, as the browser reports
/// a window of that size; restored when the test ends.
void _useWindow(WidgetTester tester, Size window) {
  tester.view.physicalSize = window * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
}

/// The app's window really is [window] (not the runner's Chrome window).
void _expectAppWindow(WidgetTester tester, Size window) {
  final context = tester.element(find.byType(ConstellationBody));
  expect(
    MediaQuery.sizeOf(context),
    window,
    reason: 'the app runs in a ${window.width}×${window.height} window',
  );
}

/// Signs in Eve (whose Field has people in a tag seated by a saved magnet,
/// like the accounts QA reloads with), then reloads the app on the Field URL
/// in a [window]-sized window, in Russian. The saved magnet read of the
/// reloaded app is held until the Field's first automatic frame has run, then
/// let through, and the tagged people re-seated by it. Returns that Field;
/// nobody has touched it.
Future<ConstellationCubit> _coldReloadField(
  WidgetTester tester, {
  required Size window,
}) async {
  e2eDrainExceptions = false;
  await launchApp(app.main);
  await pumpBounded(tester);

  // Eve ⇄ Carol and Carol ⇄ Bob trust each other: Eve's Field has people
  // beside Eve herself.
  final fixture = await bootstrapWitnessFixture(
    runId: uniqueRunId('field-cold-reload'),
  );
  await loginAs(tester, fixture.eveEmail);
  await pumpBounded(tester, frames: 12);
  final settings = GetIt.I<SettingsCubit>();
  final localeBefore = settings.state.localePreference;
  await settings.setLocalePreference(kLocalePreferenceRu);
  await pumpBounded(tester, frames: 12);

  // Eve keeps Carol and Bob in a tag whose saved magnet sits away from her,
  // so the tag's people are seated there.
  final tagId = await createPersonTagWithMembers(
    name: 'Работа ${DateTime.now().millisecondsSinceEpoch % 100000}',
    personIds: [fixture.carolUserId, fixture.bobUserId],
  );
  await GetIt.I<ConstellationTagMagnetCase>().save(
    tagId: tagId,
    xUnits: 14,
    yUnits: -10,
  );

  // Eve and Carol trust each other directly, so both are on Eve's Field;
  // Bob, two hops away, arrives only when the server's trust ranking has
  // caught up, so he is framed if placed but not waited for.
  final people = {'fp:${fixture.eveUserId}', 'fp:${fixture.carolUserId}'};
  bool peoplePlaced(ConstellationCubit cubit) =>
      _placedNodeIds(cubit).containsAll(people);

  await openConstellation(tester);
  await setConstellationViewMode(tester, ConstellationViewMode.map);
  var reloads = 0;
  await pumpUntilAsync(
    tester,
    () async {
      if (peoplePlaced(readConstellationCubit(tester))) {
        return true;
      }
      if (++reloads % 15 == 0) {
        await reloadConstellation(tester);
      }
      return false;
    },
    label: 'Eve and Carol placed on the Field',
    timeout: const Duration(seconds: 90),
  );

  // Reload: the page drops the running app, the browser is on the Field URL
  // in a window of the given size, and the app boots from scratch. The old
  // widget tree goes first, so nothing in it outlives the services the new
  // boot replaces.
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpBounded(tester, frames: 8);
  _useWindow(tester, window);
  web.window.history.replaceState(null, '', kPathConstellation);
  // The page's initial route is read once per page load; a reload reads the
  // Field URL, so the relaunch is given it the same way.
  final dispatcher = tester.binding.platformDispatcher
    ..defaultRouteNameTestValue = kPathConstellation;
  addTearDown(dispatcher.clearDefaultRouteNameTestValue);
  final magnetRead = _MagnetReadGate()..install();
  addTearDown(magnetRead.restore);
  await launchApp(app.main);
  addTearDown(
    () => GetIt.I<SettingsCubit>().setLocalePreference(localeBefore),
  );

  await pumpUntil(
    tester,
    () => finderHasMatch(find.byType(ConstellationBody)),
    label: 'the Field is the first screen after the reload',
    timeout: const Duration(seconds: 60),
  );
  _expectAppWindow(tester, window);
  final cubit = readConstellationCubit(tester);
  await pumpUntil(
    tester,
    () =>
        cubit.state.field != null &&
        cubit.graphController.canLayout &&
        peoplePlaced(cubit),
    label: 'the reloaded Field has laid out its people',
    timeout: const Duration(seconds: 60),
  );
  expect(
    cubit.state.viewMode,
    ConstellationViewMode.map,
    reason: 'the reload opens the map, not the list',
  );
  expect(
    Localizations.localeOf(
      tester.element(find.byType(ConstellationBody)),
    ).languageCode,
    'ru',
  );

  // The Field framed what it had; the saved magnet is still on its way.
  await pumpUntil(
    tester,
    () => cubit.fieldInitialFrameCompletedForTest,
    label: 'the reloaded Field ran its first automatic frame',
    timeout: const Duration(seconds: 30),
  );
  expect(
    magnetRead.held,
    greaterThan(0),
    reason: 'the saved magnet read was still out when the Field framed',
  );
  final carol = 'fp:${fixture.carolUserId}';
  final carolBefore = cubit.graphController.getPositionOrNullForId(carol);
  magnetRead.release();
  await pumpUntil(
    tester,
    () {
      final now = cubit.graphController.getPositionOrNullForId(carol);
      return now != null &&
          carolBefore != null &&
          (now - carolBefore).distance > 1 &&
          !cubit.graphController.isLayoutSettling;
    },
    label: 'the saved magnet re-seated Carol',
    timeout: const Duration(seconds: 30),
  );
  return cubit;
}

/// Within [_frameDeadline], with nobody touching the camera or pressing
/// fit-all, every placed Field node (what the minimap shows) is drawn inside
/// the map viewport — the map is never left blank.
Future<void> _expectEveryPlacedNodeInView(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required String when,
}) async {
  List<String>? outOfView;
  final deadline = DateTime.now().add(_frameDeadline);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    drainTesterExceptions(tester);
    outOfView = _nodesOutOfView(tester, cubit);
    if (outOfView != null && outOfView.isEmpty) {
      break;
    }
  }
  expect(
    cubit.graphController.userCameraInputRevision.value,
    0,
    reason: '$when: nobody touched the camera',
  );
  expect(
    _viewportRect(tester).isEmpty,
    isFalse,
    reason: '$when: the map has a size',
  );
  expect(
    outOfView,
    isNotNull,
    reason: '$when: the Field drew a frame for its current camera',
  );
  expect(
    outOfView,
    isEmpty,
    reason:
        '$when: within ${_frameDeadline.inSeconds} s every placed Field node '
        'is drawn inside the map viewport ${_viewportRect(tester)} (camera '
        'scale ${cubit.graphController.cameraScale}, matrix '
        '${_fieldViewer(tester).transformationController?.value}); outside '
        'or not drawn: $outOfView',
  );
}

/// The camera the window shows now is the one the Field's own fit-all gives
/// for this window: automatic framing after a resize goes through the same
/// fit-all path. A camera kept from the previous window size is not. Presses
/// the control, so call it last.
Future<void> _expectCameraIsFitAllForThisWindow(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required String when,
}) async {
  final control = find.byKey(TestIds.key(TestIds.constellationFitAll));
  expect(control.hitTestable(), findsOneWidget, reason: '$when: fit-all');
  final scale = cubit.graphController.cameraScale;
  final translation = _fieldViewer(
    tester,
  ).transformationController!.value.getTranslation();

  await tester.tap(control);
  await pumpBounded(tester, frames: 20);

  final fitScale = cubit.graphController.cameraScale;
  final fitTranslation = _fieldViewer(
    tester,
  ).transformationController!.value.getTranslation();
  expect(
    scale,
    closeTo(fitScale, 0.01),
    reason: '$when: the camera scale $scale is the fit-all scale $fitScale',
  );
  expect(
    (translation - fitTranslation).length,
    lessThanOrEqualTo(8),
    reason:
        '$when: the camera position $translation is the fit-all position '
        '$fitTranslation',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a cold reload of the Field URL in a 1280×800 window draws '
      'every Field node inside the map viewport before any user input or '
      'fit-all', (tester) async {
    final cubit = await _coldReloadField(tester, window: _desktopWindow);
    await _expectEveryPlacedNodeInView(tester, cubit, when: '1280×800 reload');
  });

  testWidgets('a cold reload of the Field URL on a 375×667 phone in Russian '
      'draws every Field node inside the map viewport before any user input '
      'or fit-all', (tester) async {
    final cubit = await _coldReloadField(tester, window: _phoneWindow);
    await _expectEveryPlacedNodeInView(tester, cubit, when: '375×667 reload');
  });

  testWidgets('resizing the window of an untouched open Field, 1280×800 → '
      '375×667 → 1280×800, re-frames every Field node into the new window', (
    tester,
  ) async {
    final cubit = await _coldReloadField(tester, window: _desktopWindow);
    await _expectEveryPlacedNodeInView(tester, cubit, when: '1280×800 reload');

    tester.view.physicalSize = _phoneWindow * tester.view.devicePixelRatio;
    await pumpBounded(tester, frames: 12);
    _expectAppWindow(tester, _phoneWindow);
    await _expectEveryPlacedNodeInView(
      tester,
      cubit,
      when: 'resized to 375×667',
    );

    tester.view.physicalSize = _desktopWindow * tester.view.devicePixelRatio;
    await pumpBounded(tester, frames: 12);
    _expectAppWindow(tester, _desktopWindow);
    await _expectEveryPlacedNodeInView(
      tester,
      cubit,
      when: 'resized back to 1280×800',
    );
    await _expectCameraIsFitAllForThisWindow(
      tester,
      cubit,
      when: 'resized back to 1280×800',
    );
  });
}
