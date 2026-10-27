import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_magnet_control.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_magnet_layer.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';

import '../../support/constellation_tag_lens_body_harness.dart';

Finder _map() => find.byType(GraphView<NodeDetails, EdgeDetails>);

// Include the glyph, caption and menu button in the collision rectangle.
Finder _magnet() => find.descendant(
  of: find.byType(ConstellationTagMagnetLayer),
  matching: find.byType(ConstellationTagMagnetControl),
);

Future<TagLensBodyHarness> _mount(
  WidgetTester tester,
  Size size,
  ConstellationPresentationFrameHolder holder, {
  ConstellationField? field,
}) async {
  final body = await mountTagLensBody(
    tester,
    field: field,
    bodyBuilder: () => Align(
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: size,
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(size: size),
            child: ConstellationBody(
              legendExpanded: false,
              onToggleLegend: () {},
              presentationFrameHolder: holder,
              // Exercise the feature independently of its release gate.
              // ignore: avoid_redundant_argument_values
              peopleTagsEnabled: true,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  body.field.updateLabelBudgetContext(viewport: size, textScaleFactor: 1);
  await settleTagLensBody(tester);
  expect(tester.getSize(_map()).width, size.width);
  expect(holder.frame, isNotNull);
  return body;
}

Future<void> _place(
  WidgetTester tester,
  TagLensBodyHarness body,
  Offset viewportPoint,
) async {
  final global = tester.getTopLeft(_map()) + viewportPoint;
  final scene = body.field.graphController.globalToScene(global);
  expect(scene, isNotNull, reason: 'the drop point is on the map');
  // No members: magnet placement cannot move the nodes we are measuring.
  body.field.placeTagMagnet(
    tagId: tagLensEmpty.id,
    position: scene!,
    tagsOfPerson: body.rig.peopleTags.tagsOfPerson,
  );
  for (var frame = 0; frame < 90; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(_magnet(), findsOneWidget);
}

bool _intersectsCircle(Rect label, Rect body) {
  final nearest = Offset(
    body.center.dx.clamp(label.left, label.right),
    body.center.dy.clamp(label.top, label.bottom),
  );
  return (nearest - body.center).distance < body.shortestSide / 2;
}

void _expectClear(
  WidgetTester tester,
  ConstellationPresentationFrame frame,
) {
  final magnet = tester.getRect(_magnet()).shift(-tester.getTopLeft(_map()));
  final mapBounds = Offset.zero & tester.getSize(_map());
  expect(
    mapBounds.intersect(magnet),
    magnet,
    reason: 'the whole magnet control remains visible',
  );
  final collisions = <String>[
    for (final entry in frame.bodies.entries)
      if (_intersectsCircle(magnet, entry.value)) 'node circle ${entry.key}',
    for (final entry in frame.labels.entries)
      if (magnet.overlaps(entry.value)) 'node label ${entry.key}',
    for (final entry in frame.chips.entries)
      if (magnet.overlaps(entry.value)) 'overflow chip ${entry.key}',
  ];
  expect(
    collisions,
    isEmpty,
    reason: 'magnet $magnet must clear all painted circles, labels and chips',
  );
}

void main() {
  group('magnet labels clear Field obstacles', () {
    for (final target in ['ego', 'bob']) {
      testWidgets(
        'at 375x667 a magnet near $target clears viewer and neighbour circles and labels',
        (tester) async {
          final holder = ConstellationPresentationFrameHolder();
          final body = await _mount(tester, const Size(375, 667), holder);
          final frame = holder.frame!;
          for (final id in ['fp:ego', 'fp:bob']) {
            expect(frame.bodies, contains(id), reason: '$id circle is painted');
            expect(frame.labels, contains(id), reason: '$id label is painted');
          }
          final drop = frame.bodies['fp:$target']!.center;
          expect((Offset.zero & tester.getSize(_map())).contains(drop), isTrue);

          await _place(tester, body, drop);

          _expectClear(tester, holder.frame!);
        },
      );
    }

    testWidgets(
      'at 1280 pixels a magnet below the viewer clears the request overflow chip',
      (tester) async {
        final holder = ConstellationPresentationFrameHolder();
        final field = tagLensHarnessField();
        final body = await _mount(
          tester,
          const Size(1280, 900),
          holder,
          field: field.copyWith(
            requests: [
              ...field.requests,
              for (var i = 0; i < 40; i++)
                ConstellationRequest(
                  id: 'viewer-request-$i',
                  authorId: 'ego',
                  title: 'Viewer request $i',
                  status: 0,
                  isMine: true,
                ),
            ],
          ),
        );
        expect(
          holder.frame!.chips,
          contains('ego'),
          reason: 'the viewer has a visible +N more chip',
        );
        final chip = find.byKey(const Key('constellation.overflow.ego'));
        expect(chip, findsOneWidget);
        final drop = tester.getCenter(chip) - tester.getTopLeft(_map());
        expect(holder.frame!.chips['ego']!.contains(drop), isTrue);

        await _place(tester, body, drop);

        expect(chip, findsOneWidget, reason: 'placing a magnet keeps the chip');
        _expectClear(tester, holder.frame!);
      },
    );
  });
}
