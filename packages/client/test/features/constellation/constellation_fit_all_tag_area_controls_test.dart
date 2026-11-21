@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_camera_controls.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_magnet_control.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_magnet_layer.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';

import '../../support/constellation_tag_lens_body_harness.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';

const _qaTag = PersonTag(
  id: 'T-qa',
  name: 'QA-FX 1019 auto',
  glyph: 'Q',
  color: 0,
  ord: 0,
);

const _anchors = {
  'ego': (0.0, 0.0),
  'ann': (-0.45, -0.25),
  'bob': (0.45, 0.25),
};

const _wideAnchors = {
  'ego': (0.0, 0.0),
  'ann': (-1.8, -0.25),
  'bob': (0.8, 0.25),
};

Map<String, dynamic> _peer(String id) => {
  '__typename': 'v2_ConstellationPeer',
  'id': id,
  'displayName': id,
  'contactOnly': false,
  'presence': 'visible',
  'visible': true,
  'isNew': false,
  'bondContexts': <dynamic>[],
};

Future<ConstellationField> _loadField(
  Map<String, (double, double)> anchors,
) async {
  const loadedAt = '2026-11-19T12:00:00.000Z';
  final contacts = anchors.keys.where((id) => id != 'ego').toList();
  late final ConstellationField field;
  await withRemoteWire(
    {
      'ConstellationFieldFetch': {
        '__typename': 'query_root',
        'constellationField': {
          '__typename': 'v2_ConstellationField',
          'loadedAt': loadedAt,
          'context': '',
          'peersCapped': false,
          'requestsCapped': false,
          'directContactIds': contacts,
          'peers': anchors.keys.map(_peer).toList(),
          'edges': [
            for (final id in contacts)
              {
                '__typename': 'v2_ConstellationEdge',
                'src': 'ego',
                'dst': id,
                'tier': 1,
              },
          ],
          'requests': <dynamic>[],
          'posts': <dynamic>[],
          'memberWebs': <dynamic>[],
          'anchorProjection': {
            '__typename': 'v2_ConstellationAnchorProjection',
            'revision': '1',
            'anchors': [
              for (final MapEntry(:key, :value) in anchors.entries)
                {
                  '__typename': 'v2_ConstellationAnchor',
                  'targetKind': 'PERSON',
                  'targetId': key,
                  'xUnits': value.$1,
                  'yUnits': value.$2,
                  'coordinateSpaceVersion': 1,
                  'revision': '1',
                  'placedAt': loadedAt,
                },
            ],
            'pinnedPeers': contacts.map(_peer).toList(),
            'pinnedRequests': <dynamic>[],
            'supportPeers': <dynamic>[],
            'supportEdges': <dynamic>[],
            'serverFilteredBeaconIds': <dynamic>[],
            'serverFilteredBeaconCount': 0,
          },
        },
      },
    },
    [],
    (remote) async {
      field = await ConstellationRepository(remote).fetch();
    },
  );
  return field;
}

final _magnetLayer = find.byType(ConstellationTagMagnetLayer);

Future<ConstellationCubit> _mount(
  WidgetTester tester,
  Size size,
  List<PersonTag> tags, {
  Map<String, (double, double)> anchors = _anchors,
}) async {
  if (size == kPhoneSurface) await usePhoneSurface(tester);
  final harness = await mountTagLensBody(
    tester,
    field: await _loadField(anchors),
    tagList: tags,
    surfaceSize: size,
    locale: const Locale('ru'),
    bodyBuilder: () => ConstellationBody(
      legendExpanded: false,
      onToggleLegend: () {},
      // Exercise the tag layer independently of the rollout default.
      // ignore: avoid_redundant_argument_values
      peopleTagsEnabled: true,
    ),
  );
  await _settle(tester);
  expect(_magnetLayer, findsOneWidget);
  expect(
    harness.field.graphController.viewportSize,
    tester.getSize(_magnetLayer),
  );
  return harness.field;
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 40; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

EdgeInsets _buttonInsets(WidgetTester tester) => tester
    .widget<ConstellationCameraControls>(
      find.byType(ConstellationCameraControls),
    )
    .viewportInsets;

Finder _control(PersonTag tag) => find.descendant(
  of: _magnetLayer,
  matching: find.ancestor(
    of: find.text(tag.name),
    matching: find.byType(ConstellationTagMagnetControl),
  ),
);

Rect _controlRect(WidgetTester tester, PersonTag tag) {
  final control = _control(tag);
  expect(control, findsOneWidget);
  expect(
    find.descendant(of: control, matching: find.byIcon(Icons.more_vert)),
    findsOneWidget,
  );
  return tester.getRect(control).shift(-tester.getTopLeft(_magnetLayer));
}

void _place(
  ConstellationCubit cubit,
  PersonTag tag,
  Offset viewportPoint,
) {
  cubit.placeTagMagnet(
    tagId: tag.id,
    position: cubit.graphController.viewportLocalToScene(viewportPoint),
    // Keep the placed nodes fixed while the label tests the camera bounds.
    tagsOfPerson: (_) => const {},
  );
}

Future<void> _tapFitAll(WidgetTester tester) async {
  final button = find.byTooltip('Показать всё поле');
  expect(button.hitTestable(), findsOneWidget);
  await tester.tap(button);
  await _settle(tester);
}

_Camera _camera(
  ConstellationCubit cubit,
  Rect safe,
) => (
  scale: cubit.graphController.cameraScale,
  centre: cubit.graphController.viewportLocalToScene(safe.center),
);

Offset _viewerPosition(ConstellationCubit cubit) {
  final point = cubit.graphController.renderSnapshot.resolvePosition('fp:ego')!;
  return Offset(point.x, point.y);
}

typedef _Camera = ({double scale, Offset centre});

void _expectSameCamera(_Camera actual, _Camera expected, String reason) {
  expect(actual.scale, closeTo(expected.scale, 1e-6), reason: reason);
  expect(
    (actual.centre - expected.centre).distance,
    lessThan(0.01),
    reason: reason,
  );
}

Rect _viewport(WidgetTester tester) =>
    Offset.zero & tester.getSize(_magnetLayer);

Future<_Camera> _fitWithoutMagnets(
  WidgetTester tester,
  ConstellationCubit cubit,
  EdgeInsets insets,
) async {
  expect(
    find.descendant(
      of: _magnetLayer,
      matching: find.byType(ConstellationTagMagnetControl),
    ),
    findsNothing,
  );
  final safe = insets.deflateRect(_viewport(tester));
  cubit.graphController.jumpToPosition(
    _viewerPosition(cubit) + const Offset(500, 300),
    resetScale: true,
  );
  await _settle(tester);
  expect(_inside(_nodeFootprints(cubit)['fp:ann']!, safe), isFalse);

  cubit.fitWholeField(insets: insets);
  await _settle(tester);
  final footprints = _nodeFootprints(cubit);
  _expectInside(safe, footprints);
  final envelope = footprints.values.reduce((a, b) => a.expandToInclude(b));
  expect((envelope.center - safe.center).distance, lessThan(0.1));
  return _camera(cubit, safe);
}

Map<String, Rect> _nodeFootprints(ConstellationCubit cubit) {
  final graph = cubit.graphController;
  final snapshot = graph.renderSnapshot;
  expect(
    snapshot.topology.nodesById.keys,
    unorderedEquals([for (final person in _anchors.keys) 'fp:$person']),
  );
  final footprints = <String, Rect>{};
  for (final node in snapshot.topology.nodesById.values) {
    final point = snapshot.resolvePosition(node.id)!;
    final bounds = constellationPlacedNodeBounds(
      centre: (x: point.x, y: point.y),
      size: (width: node.size.width, height: node.size.height),
      footprint: cubit.layoutFootprints[node.id],
    );
    footprints[node.id] = Rect.fromPoints(
      graph.sceneToViewportLocal(Offset(bounds.left, bounds.top)),
      graph.sceneToViewportLocal(Offset(bounds.right, bounds.bottom)),
    );
  }
  return footprints;
}

bool _inside(Rect rect, Rect safe) =>
    rect.left >= safe.left &&
    rect.top >= safe.top &&
    rect.right <= safe.right &&
    rect.bottom <= safe.bottom;

Map<String, Rect> _clipped(Rect safe, Map<String, Rect> rects) => {
  for (final entry in rects.entries)
    if (!_inside(entry.value, safe)) entry.key: entry.value,
};

void _expectInside(Rect safe, Map<String, Rect> rects) {
  expect(
    _clipped(safe, rects),
    isEmpty,
    reason: 'Every listed footprint fits within $safe',
  );
}

// The tag fit depends on actual screen-space text widths.
Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final weight in const ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('fonts/Inter-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadInter);

  for (final (surface, size) in [
    ('375 × 667 phone', kPhoneSurface),
    ('1280 × 800 desktop', const Size(1280, 800)),
  ]) {
    testWidgets(
      'Show whole field brings a clipped tag name and menu inside the $surface',
      (tester) async {
        final phone = size == kPhoneSurface;
        final cubit = await _mount(
          tester,
          size,
          const [_qaTag],
          anchors: phone ? _wideAnchors : _anchors,
        );
        final insets = _buttonInsets(tester);
        final safe = insets.deflateRect(_viewport(tester));
        final nodeOnlyCamera = await _fitWithoutMagnets(tester, cubit, insets);

        final dropPoint = Offset(-30, safe.center.dy + 100);
        _place(cubit, _qaTag, dropPoint);
        await _settle(tester);
        final beforeFit = _controlRect(tester, _qaTag);
        expect((beforeFit.center - dropPoint).distance, lessThan(0.1));
        expect(beforeFit.left, isNegative);
        expect(
          _nodeFootprints(cubit).values.every(
            (footprint) => beforeFit.center.dx < footprint.left,
          ),
          isTrue,
          reason: 'The tag sits to the left of every node',
        );

        await _tapFitAll(tester);
        final fromButton = _camera(cubit, safe);
        final controlRects = {'Fit-all button': _controlRect(tester, _qaTag)};
        _expectInside(safe, _nodeFootprints(cubit));
        expect(fromButton.scale, lessThanOrEqualTo(1));
        if (phone) {
          // The direct call must recover the same camera from a different view.
          cubit.graphController.jumpToPosition(
            fromButton.centre + const Offset(80, 100),
          );
          await _settle(tester);
          expect(
            (_camera(cubit, safe).centre - fromButton.centre).distance,
            greaterThan(10),
          );
          cubit.fitWholeField(insets: insets);
          await _settle(tester);
          final direct = _camera(cubit, safe);
          expect(direct.scale, closeTo(fromButton.scale, 1e-6));
          expect((direct.centre - fromButton.centre).distance, lessThan(0.1));
          controlRects['Direct fitWholeField call'] = _controlRect(
            tester,
            _qaTag,
          );
          _expectInside(safe, _nodeFootprints(cubit));
        } else {
          // This compact desktop arrangement has room for the tag at 1×.
          expect(fromButton.scale, 1);
        }
        cubit.removeTagMagnet(_qaTag.id);
        await _settle(tester);
        _expectSameCamera(
          await _fitWithoutMagnets(tester, cubit, insets),
          nodeOnlyCamera,
          'Removing the last magnet restores the original fit-all camera',
        );
        expect(tester.takeException(), isNull);
        _expectInside(safe, controlRects);
      },
    );
  }

  testWidgets(
    'Show whole field fits nodes and other tag controls beside an over-wide tag',
    (tester) async {
      const longTag = PersonTag(
        id: 'T-wide',
        name: 'ШШШШШШШШШШШШШШШШШШШШШ',
        glyph: 'Ш',
        color: 0,
        ord: 2,
      );
      const normalTags = [_qaTag, tagLensWorkshop];
      final cubit = await _mount(tester, kPhoneSurface, [
        ...normalTags,
        longTag,
      ]);
      final insets = _buttonInsets(tester);
      final viewport = _viewport(tester);
      final safe = insets.deflateRect(viewport);

      _place(cubit, _qaTag, Offset(safe.left - 40, safe.center.dy + 100));
      _place(
        cubit,
        tagLensWorkshop,
        Offset(safe.right + 40, safe.center.dy - 100),
      );
      _place(cubit, longTag, Offset(safe.center.dx, safe.top - 80));
      await _settle(tester);

      expect(_controlRect(tester, _qaTag).left, lessThan(safe.left));
      expect(
        _controlRect(tester, tagLensWorkshop).right,
        greaterThan(safe.right),
      );
      final longBeforeFit = _controlRect(tester, longTag);
      expect(longBeforeFit.width, greaterThan(safe.width));
      expect(longBeforeFit.width, lessThan(viewport.width));
      expect(longBeforeFit.top, lessThan(safe.top));

      Map<String, Rect> clippedNormalControls() => _clipped(safe, {
        for (final tag in normalTags) tag.name: _controlRect(tester, tag),
      });

      await _tapFitAll(tester);
      final fromButton = _camera(cubit, safe);
      expect(fromButton.scale.isFinite, isTrue);
      expect(fromButton.scale, greaterThan(0));
      expect(fromButton.scale, lessThanOrEqualTo(1));
      _expectInside(safe, _nodeFootprints(cubit));
      final buttonClipping = clippedNormalControls();
      final longAfterFit = _controlRect(tester, longTag);

      cubit.graphController.jumpToPosition(
        fromButton.centre + const Offset(80, 100),
      );
      await _settle(tester);
      expect(
        (_camera(cubit, safe).centre - fromButton.centre).distance,
        greaterThan(10),
      );
      cubit.fitWholeField(insets: insets);
      await _settle(tester);
      final direct = _camera(cubit, safe);
      expect(direct.scale, closeTo(fromButton.scale, 1e-6));
      expect((direct.centre - fromButton.centre).distance, lessThan(0.1));
      final directClipping = clippedNormalControls();
      expect(tester.takeException(), isNull);

      expect(
        {
          if (buttonClipping.isNotEmpty)
            'Clipped after tapping': buttonClipping,
          if (directClipping.isNotEmpty)
            'Clipped after direct fit': directClipping,
          if (longAfterFit.top < safe.top || longAfterFit.bottom > safe.bottom)
            'Over-wide control clipped vertically': longAfterFit,
          if (longAfterFit.center.dx < safe.left ||
              longAfterFit.center.dx > safe.right)
            'Over-wide control centre outside the safe width':
                longAfterFit.center,
        },
        isEmpty,
        reason: 'The fit must respect the button-inset safe rect $safe',
      );
    },
  );

  testWidgets(
    'Show whole field fits tag controls on three sides and every node',
    (tester) async {
      const tags = [_qaTag, tagLensWorkshop, tagLensGarden];
      final cubit = await _mount(tester, kPhoneSurface, tags);
      const insets = EdgeInsets.fromLTRB(8, 24, 42, 96);
      final viewport = _viewport(tester);
      final safe = insets.deflateRect(viewport);
      const floor = 0.9;
      const floorInsets = EdgeInsets.fromLTRB(80, 24, 114, 96);
      final floorViewport = floorInsets.deflateRect(viewport);
      final seed = _viewerPosition(cubit) + const Offset(500, 300);
      final graph = cubit.graphController;
      Future<_Camera> resetCamera() async {
        graph.fitToRect(
          Rect.fromCenter(center: seed, width: 10, height: 10),
          viewportInsets: floorInsets,
          maxScale: 0.5,
        );
        await _settle(tester);
        final camera = _camera(cubit, floorViewport);
        expect(camera.scale, 0.5);
        expect(
          (camera.centre - _viewerPosition(cubit)).distance,
          greaterThan(400),
        );
        return camera;
      }

      cubit.fitWholeField(insets: floorInsets);
      await _settle(tester);
      expect(
        graph.cameraScale,
        lessThan(floor),
        reason: 'The tighter viewport makes the requested floor take effect',
      );
      final initialCamera = await resetCamera();
      final initialViewport = _viewport(tester);
      final unmagnetisedFootprints = _nodeFootprints(cubit);
      cubit.frameField(insets: floorInsets, floor: floor);
      await _settle(tester);
      final withoutTags = _camera(cubit, floorViewport);
      expect(withoutTags.scale, greaterThanOrEqualTo(floor));
      expect(
        (withoutTags.centre - _viewerPosition(cubit)).distance,
        lessThan((initialCamera.centre - _viewerPosition(cubit)).distance),
      );
      cubit.fitWholeField(insets: insets);
      await _settle(tester);

      final dropPoints = {
        _qaTag: Offset(safe.left + 40, safe.center.dy + 170),
        tagLensWorkshop: Offset(safe.right - 40, safe.center.dy - 135),
        tagLensGarden: Offset(safe.center.dx, safe.top - 40),
      };
      for (final MapEntry(key: tag, value: point) in dropPoints.entries) {
        _place(cubit, tag, point);
      }
      await _settle(tester);
      for (final MapEntry(key: tag, value: point) in dropPoints.entries) {
        final rect = _controlRect(tester, tag);
        expect((rect.center - point).distance, lessThan(0.1));
        expect(
          _inside(rect, safe),
          isFalse,
          reason: '${tag.name} starts clipped',
        );
      }

      _expectSameCamera(
        await resetCamera(),
        initialCamera,
        'Both floor comparisons start from the same panned, zoomed-out view',
      );
      expect(_viewport(tester), initialViewport);
      expect(_nodeFootprints(cubit), unmagnetisedFootprints);
      cubit.frameField(insets: floorInsets, floor: floor);
      await _settle(tester);
      _expectSameCamera(
        _camera(cubit, floorViewport),
        withoutTags,
        'The same nodes, insets and floor produce the same camera with magnets',
      );

      final buttonSafe = _buttonInsets(tester).deflateRect(_viewport(tester));
      await _tapFitAll(tester);
      expect(cubit.graphController.cameraScale, lessThanOrEqualTo(1));
      _expectInside(buttonSafe, _nodeFootprints(cubit));
      final buttonClipping = _clipped(buttonSafe, {
        for (final tag in tags) tag.name: _controlRect(tester, tag),
      });

      cubit.fitWholeField(insets: insets);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(cubit.graphController.cameraScale, lessThanOrEqualTo(1));
      _expectInside(safe, _nodeFootprints(cubit));
      final customInsetsClipping = _clipped(safe, {
        for (final tag in tags) tag.name: _controlRect(tester, tag),
      });
      expect({
        if (buttonClipping.isNotEmpty) 'Fit-all button': buttonClipping,
        if (customInsetsClipping.isNotEmpty)
          'Direct fit-all with custom insets': customInsetsClipping,
      }, isEmpty);
    },
  );
}
