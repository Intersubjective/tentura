// The tag lens paints a soft hull around the people of every selected own
// tag, between the edges and the nodes. Automatic tags have no hull, and
// painting one never moves a node.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_tag_colors.dart';
import 'package:tentura/features/constellation/domain/constellation_tag_filter.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_hull_layer.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/constellation_tag_lens_body_harness.dart';

/// Every hull on screen, whichever tag it belongs to.
Finder _anyHull() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      key.value.startsWith('constellation-tag-hull-');
});

Finder _hullOf(String tagId) =>
    find.byKey(ConstellationTagHullLayer.hullKey(tagId));

Finder _node(String personId) =>
    find.byKey(TestIds.key(TestIds.graphNode(personId)));

/// What the keyed hull widget draws: its first `drawPath` call. The widget
/// must paint the hull path itself, so the path is in its own local space.
({Path path, Paint paint, RenderObject box}) _drawnHull(
  WidgetTester tester,
  String tagId,
) {
  Path? path;
  Paint? paint;
  final box = tester.renderObject(_hullOf(tagId));
  expect(
    box,
    paints..something((name, arguments) {
      if (name != #drawPath) return false;
      path = arguments[0] as Path;
      paint = arguments[1] as Paint;
      return true;
    }),
    reason: 'the hull of $tagId draws a path',
  );
  return (path: path!, paint: paint!, box: box);
}

/// The centre of person [personId]'s node in the hull's own space.
Offset _centreInHull(
  WidgetTester tester,
  RenderObject box,
  String personId,
) => (box as RenderBox).globalToLocal(tester.getCenter(_node(personId)));

double _area(Path path) {
  final bounds = path.getBounds();
  return bounds.width * bounds.height;
}

int _rgb(Color color) => color.toARGB32() & 0xFFFFFF;

/// Pre-order position of every render object: the order they paint in.
Map<RenderObject, int> _paintOrder(WidgetTester tester) {
  final order = <RenderObject, int>{};
  void visit(RenderObject object) {
    order[object] = order.length;
    object.visitChildren(visit);
  }

  visit(tester.binding.renderViews.single);
  return order;
}

void main() {
  group('tag lens hull geometry', () {
    testWidgets('is a translucent fill in the tag colour', (tester) async {
      final m = await mountTagLensBody(tester);

      m.lens.toggleOwn(tagLensNeighbour.id);
      await settleTagLensBody(tester);

      final hull = _drawnHull(tester, tagLensNeighbour.id);
      final swatch = Theme.of(
        tester.element(_hullOf(tagLensNeighbour.id)),
      ).extension<TenturaTagColors>()!.swatches[tagLensNeighbour.color];
      expect(hull.paint.style, PaintingStyle.fill);
      expect(hull.paint.color.a, greaterThan(0));
      expect(hull.paint.color.a, lessThan(1), reason: 'a soft hull');
      expect(
        _rgb(hull.paint.color),
        anyOf(_rgb(swatch.container), _rgb(swatch.accent)),
      );
    });

    testWidgets('each selected tag is drawn in its own colour', (tester) async {
      final m = await mountTagLensBody(tester);

      m.lens
        ..toggleOwn(tagLensNeighbour.id)
        ..toggleOwn(tagLensWorkshop.id);
      await settleTagLensBody(tester);

      final neighbour = _drawnHull(tester, tagLensNeighbour.id).paint.color;
      final workshop = _drawnHull(tester, tagLensWorkshop.id).paint.color;
      expect(_rgb(neighbour), isNot(_rgb(workshop)));
    });

    testWidgets('encloses every person of the tag', (tester) async {
      final m = await mountTagLensBody(tester);

      m.lens.toggleOwn(tagLensGarden.id);
      await settleTagLensBody(tester);

      final hull = _drawnHull(tester, tagLensGarden.id);
      for (final id in ['ann', 'bob', 'cid']) {
        expect(
          hull.path.contains(_centreInHull(tester, hull.box, id)),
          isTrue,
          reason: '$id is inside the Garden hull',
        );
      }
    });

    testWidgets('is padded around a tag of one person', (tester) async {
      final m = await mountTagLensBody(tester);

      m.lens.toggleOwn(tagLensWorkshop.id);
      await settleTagLensBody(tester);

      final hull = _drawnHull(tester, tagLensWorkshop.id);
      final ann = _centreInHull(tester, hull.box, 'ann');
      expect(hull.path.contains(ann), isTrue);
      for (final step in const [
        Offset(4, 0),
        Offset(-4, 0),
        Offset(0, 4),
        Offset(0, -4),
      ]) {
        expect(hull.path.contains(ann + step), isTrue, reason: '$step');
      }
    });

    testWidgets('a tag of more people covers more than a tag of one', (
      tester,
    ) async {
      final m = await mountTagLensBody(tester);

      m.lens
        ..toggleOwn(tagLensWorkshop.id)
        ..toggleOwn(tagLensGarden.id);
      await settleTagLensBody(tester);

      expect(
        _area(_drawnHull(tester, tagLensGarden.id).path),
        greaterThan(_area(_drawnHull(tester, tagLensWorkshop.id).path)),
      );
    });
  });

  group('tag lens hull layering', () {
    testWidgets('is painted beneath the people it surrounds', (tester) async {
      final m = await mountTagLensBody(tester);

      m.lens.toggleOwn(tagLensGarden.id);
      await settleTagLensBody(tester);

      final order = _paintOrder(tester);
      final hullAt = order[tester.renderObject(_hullOf(tagLensGarden.id))]!;
      for (final id in ['ann', 'bob', 'cid']) {
        expect(
          hullAt,
          lessThan(order[tester.renderObject(_node(id))]!),
          reason: 'the hull paints before (under) $id',
        );
      }
    });

    testWidgets('a person under the hull can still be tapped', (tester) async {
      final m = await mountTagLensBody(tester);
      m.lens.toggleOwn(tagLensGarden.id);
      await settleTagLensBody(tester);
      expect(_hullOf(tagLensGarden.id), findsOneWidget);

      await tester.tap(_node('ann'));
      await settleTagLensBody(tester);

      expect(m.field.state.selectedPersonId, 'ann');
    });
  });

  group('tag lens hull presence', () {
    testWidgets('no hull is painted while no tag is selected', (tester) async {
      await mountTagLensBody(tester);

      expect(_anyHull(), findsNothing);
    });

    testWidgets('a selected own tag gets one hull', (tester) async {
      final m = await mountTagLensBody(tester);

      m.lens.toggleOwn(tagLensNeighbour.id);
      await settleTagLensBody(tester);

      expect(_hullOf(tagLensNeighbour.id), findsOneWidget);
      expect(_anyHull(), findsOneWidget);
    });

    testWidgets('every selected own tag gets its own hull', (tester) async {
      final m = await mountTagLensBody(tester);

      m.lens
        ..toggleOwn(tagLensNeighbour.id)
        ..toggleOwn(tagLensWorkshop.id);
      await settleTagLensBody(tester);

      expect(_hullOf(tagLensNeighbour.id), findsOneWidget);
      expect(_hullOf(tagLensWorkshop.id), findsOneWidget);
      expect(_anyHull(), findsNWidgets(2));
    });

    testWidgets('deselecting a tag removes only its hull', (tester) async {
      final m = await mountTagLensBody(tester);
      m.lens
        ..toggleOwn(tagLensNeighbour.id)
        ..toggleOwn(tagLensWorkshop.id);
      await settleTagLensBody(tester);

      m.lens.toggleOwn(tagLensNeighbour.id);
      await settleTagLensBody(tester);

      expect(_hullOf(tagLensNeighbour.id), findsNothing);
      expect(_hullOf(tagLensWorkshop.id), findsOneWidget);
    });

    testWidgets('clearing the selection removes every hull', (tester) async {
      final m = await mountTagLensBody(tester);
      m.lens
        ..toggleOwn(tagLensNeighbour.id)
        ..toggleOwn(tagLensGarden.id);
      await settleTagLensBody(tester);
      expect(_anyHull(), findsNWidgets(2), reason: 'positive control');

      m.lens.clear();
      await settleTagLensBody(tester);

      expect(_anyHull(), findsNothing);
    });

    testWidgets('a selected automatic tag has no hull', (tester) async {
      final m = await mountTagLensBody(tester);

      m.lens.toggleAuto(ConstellationAutoTagKind.mutualContact);
      await settleTagLensBody(tester);

      expect(_anyHull(), findsNothing);
    });

    testWidgets('an automatic tag selected beside an own tag adds no hull', (
      tester,
    ) async {
      final m = await mountTagLensBody(tester);

      m.lens
        ..toggleOwn(tagLensNeighbour.id)
        ..toggleAuto(ConstellationAutoTagKind.iTrust);
      await settleTagLensBody(tester);

      expect(_hullOf(tagLensNeighbour.id), findsOneWidget);
      expect(_anyHull(), findsOneWidget);
    });

    testWidgets(
      'a selected own tag nobody on the Field belongs to has no hull',
      (
        tester,
      ) async {
        final m = await mountTagLensBody(tester);

        m.lens.toggleOwn(tagLensEmpty.id);
        await settleTagLensBody(tester);

        expect(m.lens.state.selectedOwn, {tagLensEmpty.id});
        expect(_anyHull(), findsNothing);
      },
    );

    testWidgets('the "and" mode keeps a hull for each selected tag', (
      tester,
    ) async {
      final m = await mountTagLensBody(tester);

      m.lens
        ..toggleOwn(tagLensNeighbour.id)
        ..toggleOwn(tagLensWorkshop.id)
        ..setMode(ConstellationTagFilterMode.and);
      await settleTagLensBody(tester);

      expect(_hullOf(tagLensNeighbour.id), findsOneWidget);
      expect(_hullOf(tagLensWorkshop.id), findsOneWidget);
    });

    testWidgets('painting a hull leaves every node where it was', (
      tester,
    ) async {
      final m = await mountTagLensBody(tester);
      final controller = m.field.graphController;
      final ids = [for (final n in controller.nodes) n.id];
      final positions = {
        for (final id in ids) id: controller.getPositionOrNullForId(id),
      };
      expect(ids, isNotEmpty, reason: 'positive control');

      m.lens.toggleOwn(tagLensGarden.id);
      await settleTagLensBody(tester);

      expect(_hullOf(tagLensGarden.id), findsOneWidget);
      for (final id in ids) {
        expect(
          controller.getPositionOrNullForId(id),
          positions[id],
          reason: id,
        );
      }
    });
  });
}
