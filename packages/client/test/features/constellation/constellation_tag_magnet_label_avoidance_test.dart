import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_row.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';

import '../../support/constellation_tag_lens_body_harness.dart';

const _phone = Size(375, 667);
const _desktop = Size(1200, 900);

Finder _map() => find.byType(GraphView<NodeDetails, EdgeDetails>);

// The whole magnet label (the chip), not only its caption text. The tag row
// holds a chip with the same caption, so rows are excluded.
Finder _magnetLabel(String name) => find
    .ancestor(
      of: find.byElementPredicate((element) {
        final widget = element.widget;
        if (widget is! Text || widget.data != name) return false;
        var inRow = false;
        element.visitAncestorElements((ancestor) {
          if (ancestor.widget is ConstellationTagRow) inRow = true;
          return !inRow;
        });
        return !inRow;
      }, description: 'the $name magnet caption outside the tag row'),
      matching: find.byType(PersonTagChip),
    )
    .first;

Finder _nodeLabel(String personId) =>
    find.byKey(ValueKey('constellation.label.fp:$personId'));

// The harness fixes the test surface, so a phone is a phone-sized, phone-metric
// box inside it; the Field lays out against that box from the first frame.
Future<TagLensBodyHarness> _mountAt(WidgetTester tester, Size size) async {
  final body = await mountTagLensBody(
    tester,
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
              // Explicitly exercise the enabled feature, independent of ship gates.
              // ignore: avoid_redundant_argument_values
              peopleTagsEnabled: true,
            ),
          ),
        ),
      ),
    ),
  );
  body.field.updateLabelBudgetContext(viewport: size, textScaleFactor: 1);
  await settleTagLensBody(tester);
  return body;
}

// A tag nobody belongs to: placing it attracts no one, so the viewer label
// is exactly where it was measured when the magnet lands.
Future<void> _placeMagnetAt(
  WidgetTester tester,
  TagLensBodyHarness body,
  Offset global,
) async {
  final scene = body.field.graphController.globalToScene(global);
  expect(scene, isNotNull, reason: 'the point lies on the map');
  body.field.placeTagMagnet(
    tagId: tagLensEmpty.id,
    position: scene!,
    tagsOfPerson: body.rig.peopleTags.tagsOfPerson,
  );
  for (var frame = 0; frame < 90; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  group('tag magnet label placement on the Field', () {
    testWidgets(
      'on a phone, a magnet dropped on the viewer label does not cover it',
      (tester) async {
        final body = await _mountAt(tester, _phone);
        expect(
          _nodeLabel('ego'),
          findsOneWidget,
          reason: 'positive control: the viewer node has a label to avoid',
        );
        final viewerLabel = tester.getRect(_nodeLabel('ego'));
        expect(
          (Offset.zero & _phone).contains(viewerLabel.center),
          isTrue,
          reason: 'positive control: the viewer label is on the phone screen',
        );

        await _placeMagnetAt(tester, body, viewerLabel.center);

        expect(_magnetLabel('Nobody'), findsOneWidget);
        final viewerLabelAfter = tester.getRect(_nodeLabel('ego'));
        final magnet = tester.getRect(_magnetLabel('Nobody'));
        expect(
          magnet.overlaps(viewerLabelAfter),
          isFalse,
          reason:
              'magnet $magnet must stay clear of the viewer label '
              '$viewerLabelAfter',
        );
      },
    );

    testWidgets(
      'on a phone, a magnet dropped next to the viewer node avoids the label',
      (tester) async {
        final body = await _mountAt(tester, _phone);
        expect(_nodeLabel('ego'), findsOneWidget);
        final viewerLabel = tester.getRect(_nodeLabel('ego'));
        expect((Offset.zero & _phone).contains(viewerLabel.center), isTrue);

        // Just beside the label's centre, as in a casual drop near the node.
        await _placeMagnetAt(
          tester,
          body,
          viewerLabel.center + const Offset(12, 4),
        );

        final magnet = tester.getRect(_magnetLabel('Nobody'));
        final viewerLabelAfter = tester.getRect(_nodeLabel('ego'));
        expect(magnet.overlaps(viewerLabelAfter), isFalse);
        expect(
          tester.getRect(_map()).intersect(magnet),
          magnet,
          reason: 'moving away from the label keeps the magnet on the map',
        );
      },
    );

    testWidgets('on desktop, a magnet away from labels stays where dropped', (
      tester,
    ) async {
      final body = await _mountAt(tester, _desktop);
      final map = tester.getRect(_map());
      final drop = Offset(map.right - 100, map.top + 180);
      for (final id in ['ego', 'ann', 'bob', 'cid', 'dan']) {
        if (_nodeLabel(id).evaluate().isEmpty) continue;
        expect(
          tester.getRect(_nodeLabel(id)).inflate(60).contains(drop),
          isFalse,
          reason: 'precondition: no $id label near the drop point',
        );
      }

      await _placeMagnetAt(tester, body, drop);

      expect(
        (tester.getCenter(_magnetLabel('Nobody')) - drop).distance,
        lessThan(kMinInteractiveDimension),
        reason: 'with no label in the way the magnet stays at the drop point',
      );
    });
  });
}
