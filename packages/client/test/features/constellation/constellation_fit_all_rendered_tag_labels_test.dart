@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/data/repository/constellation_tag_magnet_repository.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_tag_magnet_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_camera_controls.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_magnet_control.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_magnet_layer.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';

import '../../support/constellation_tag_lens_body_harness.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';

const _tag = PersonTag(
  id: 'T-qa',
  name: 'QA-FX 1019 auto',
  glyph: 'Q',
  color: 0,
  ord: 0,
);

// Three close columns of people leave little room for the tag chip.
const _anchors = {
  'ego': (0.0, 0.0),
  'ann': (-0.45, -0.25),
  'bob': (0.45, 0.25),
  'cid': (-0.45, 0.0),
  'dan': (-0.45, 0.25),
  'eve': (0.0, -0.25),
  'flo': (0.0, 0.25),
  'gus': (0.45, -0.25),
  'hal': (0.45, 0.0),
};

const _tagOffsetFromCanvasCentre = Offset(-30, 30);

Offset get _tagScenePoint {
  final centre = constellationCanvasCentrePoint();
  return Offset(centre.x, centre.y) + _tagOffsetFromCanvasCentre;
}

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

Map<String, dynamic> _fieldResponse() {
  const loadedAt = '2026-11-19T12:00:00.000Z';
  final contacts = _anchors.keys.where((id) => id != 'ego').toList();
  return {
    '__typename': 'query_root',
    'constellationField': {
      '__typename': 'v2_ConstellationField',
      'loadedAt': loadedAt,
      'context': '',
      'peersCapped': false,
      'requestsCapped': false,
      'directContactIds': contacts,
      'peers': _anchors.keys.map(_peer).toList(),
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
          for (final MapEntry(:key, :value) in _anchors.entries)
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
  };
}

Map<String, dynamic> _savedTagResponse() {
  final point = _tagScenePoint;
  final units = constellationPointToV1Anchor((x: point.dx, y: point.dy));
  return {
    '__typename': 'query_root',
    'constellationTagMagnets': [
      {
        '__typename': 'v2_ConstellationTagMagnet',
        'tagId': _tag.id,
        'xUnits': units.xUnits,
        'yUnits': units.yUnits,
        'revision': 1,
      },
    ],
  };
}

final _magnetLayer = find.byType(ConstellationTagMagnetLayer);

Future<void> _withField(
  WidgetTester tester,
  Size size,
  Future<void> Function(ConstellationCubit cubit) run, {
  bool restoreSavedTag = false,
}) async {
  if (size == kPhoneSurface) await usePhoneSurface(tester);
  final realtime = buildTestRealtimeSync();
  addTearDown(realtime.port.dispose);
  final sent = <WireSent>[];
  await withRemoteWire(
    {
      'ConstellationFieldFetch': _fieldResponse(),
      if (restoreSavedTag) 'ConstellationTagMagnets': _savedTagResponse(),
    },
    sent,
    (remote) async {
      final harness = await mountTagLensBody(
        tester,
        fieldRepository: ConstellationRepository(remote),
        tagMagnetCase: restoreSavedTag
            ? ConstellationTagMagnetCase(
                ConstellationTagMagnetRepository(remote),
                realtime.case_,
              )
            : null,
        tagList: const [_tag],
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
      expect(tester.getSize(find.byType(Scaffold)), size);
      if (restoreSavedTag) {
        expect(
          sent.map((request) => request.operationName),
          contains('ConstellationTagMagnets'),
        );
      }
      await run(harness.field);
    },
  );
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

Rect _controlRect(WidgetTester tester) {
  final control = find.descendant(
    of: _magnetLayer,
    matching: find.byType(ConstellationTagMagnetControl),
  );
  expect(control, findsOneWidget);
  for (final content in [
    find.text(_tag.name),
    find.text(_tag.glyph),
    find.byIcon(Icons.more_vert),
  ]) {
    expect(find.descendant(of: control, matching: content), findsOneWidget);
  }
  return tester.getRect(control).shift(-tester.getTopLeft(_magnetLayer));
}

void _place(ConstellationCubit cubit, Offset scenePoint) {
  cubit.placeTagMagnet(
    tagId: _tag.id,
    position: scenePoint,
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

typedef _Camera = ({double scale, Offset centre});

bool _sameCamera(_Camera first, _Camera second) =>
    (first.scale - second.scale).abs() <= 1e-6 &&
    (first.centre - second.centre).distance * second.scale <= 0.1;

Rect _safeRect(WidgetTester tester) => _buttonInsets(
  tester,
).deflateRect(Offset.zero & tester.getSize(_magnetLayer));

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

Map<String, Rect> _clippedNodes(ConstellationCubit cubit, Rect safe) => {
  for (final entry in _nodeFootprints(cubit).entries)
    if (!_inside(entry.value, safe)) entry.key: entry.value,
};

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

  testWidgets(
    'Show whole field frames a placed tag chip and every node on desktop and phone',
    (tester) async {
      await _withField(tester, const Size(1280, 800), (cubit) async {
        final graph = cubit.graphController;
        final desktopSafe = _safeRect(tester);
        _place(
          cubit,
          graph.viewportLocalToScene(Offset(40, desktopSafe.center.dy + 100)),
        );
        await _settle(tester);
        expect(_controlRect(tester).left, lessThan(desktopSafe.left));

        await _tapFitAll(tester);
        final desktopChip = _controlRect(tester);
        final desktopFailures = {
          ..._clippedNodes(cubit, desktopSafe),
          if (!_inside(desktopChip, desktopSafe)) 'Tag chip': desktopChip,
        };
        expect(
          desktopFailures,
          isEmpty,
          reason: 'Desktop safe rect: $desktopSafe',
        );

        cubit.removeTagMagnet(_tag.id);
        await usePhoneSurface(tester);
        await _settle(tester);
        expect(tester.getSize(find.byType(Scaffold)), kPhoneSurface);
        await _tapFitAll(tester);
        final safe = _safeRect(tester);
        final insets = _buttonInsets(tester);
        // The nearby people push the rendered control to the left of its
        // anchor. Fit must accommodate the whole chip where it actually lands.
        _place(cubit, _tagScenePoint);
        await _settle(tester);
        expect(_controlRect(tester).left, lessThan(safe.left));
        final before = _camera(cubit, safe);

        await _tapFitAll(tester);
        final first = _camera(cubit, safe);
        final firstChip = _controlRect(tester);
        final firstClippedNodes = _clippedNodes(cubit, safe);

        await _tapFitAll(tester);
        final second = _camera(cubit, safe);
        final secondChip = _controlRect(tester);

        graph.jumpToPosition(second.centre + const Offset(80, 100));
        await _settle(tester);
        expect(_sameCamera(_camera(cubit, safe), second), isFalse);
        cubit.fitWholeField(insets: insets);
        await _settle(tester);
        final direct = _camera(cubit, safe);
        final directChip = _controlRect(tester);

        expect(first.scale, greaterThan(0));
        expect(first.scale, lessThanOrEqualTo(1));
        expect(tester.takeException(), isNull);
        expect(
          {
            if (_sameCamera(before, first)) 'Camera stayed unchanged': first,
            if (!_inside(firstChip, safe)) 'Chip after first tap': firstChip,
            if (firstClippedNodes.isNotEmpty)
              'Clipped nodes': firstClippedNodes,
            if (!_sameCamera(first, second)) 'Camera after second tap': second,
            if (!_inside(secondChip, safe)) 'Chip after second tap': secondChip,
            if (!_sameCamera(first, direct)) 'Camera after direct fit': direct,
            if (!_inside(directChip, safe)) 'Chip after direct fit': directChip,
          },
          isEmpty,
          reason: 'The camera must frame the chip and nodes within $safe',
        );
      });
    },
  );

  testWidgets(
    'Show whole field brings a tag chip restored from the server into the phone viewport',
    (tester) async {
      await _withField(
        tester,
        kPhoneSurface,
        (cubit) async {
          // Start at the node-centred view even if the automatic entry camera
          // has already framed the restored tag.
          final centre = constellationCanvasCentrePoint();
          cubit.graphController.fitToRect(
            Rect.fromCenter(
              center: Offset(centre.x, centre.y),
              width: 100,
              height: 100,
            ),
            viewportInsets: _buttonInsets(tester),
            maxScale: 1,
          );
          await _settle(tester);
          final safe = _safeRect(tester);
          expect(_controlRect(tester).left, lessThan(safe.left));
          await _tapFitAll(tester);
          expect(tester.takeException(), isNull);
          final chip = _controlRect(tester);
          expect(
            _inside(chip, safe),
            isTrue,
            reason: 'The restored tag chip $chip must fit inside $safe',
          );
        },
        restoreSavedTag: true,
      );
    },
  );
}
