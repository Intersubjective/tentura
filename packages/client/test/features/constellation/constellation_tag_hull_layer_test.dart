// The tag lens paints a soft hull around the people of every own tag that has
// someone on the Field. Selecting a tag highlights its hull; automatic tags
// have no hull, and painting one never moves a node.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_tag_colors.dart';
import 'package:tentura/features/constellation/domain/constellation_tag_filter.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_hull_layer.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/constellation_tag_lens_body_harness.dart';
import '../../support/phone_surface.dart';

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
({Path path, Paint fill, Paint? stroke, RenderObject box}) _drawnHull(
  WidgetTester tester,
  String tagId, {
  bool expectStroke = false,
}) {
  Path? path;
  Paint? fill;
  Paint? stroke;
  final box = tester.renderObject(_hullOf(tagId));
  if (expectStroke) {
    expect(
      box,
      paints
        ..something((name, arguments) {
          if (name != #drawPath) return false;
          path = arguments[0] as Path;
          fill = arguments[1] as Paint;
          return fill!.style == PaintingStyle.fill;
        })
        ..something((name, arguments) {
          if (name != #drawPath) return false;
          stroke = arguments[1] as Paint;
          return stroke!.style == PaintingStyle.stroke;
        }),
      reason: 'the hull of $tagId draws fill then outline',
    );
  } else {
    expect(
      box,
      paints..something((name, arguments) {
        if (name != #drawPath) return false;
        path = arguments[0] as Path;
        fill = arguments[1] as Paint;
        return fill!.style == PaintingStyle.fill;
      }),
      reason: 'the hull of $tagId draws a fill path',
    );
  }
  return (path: path!, fill: fill!, stroke: stroke, box: box);
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
      expect(hull.fill.style, PaintingStyle.fill);
      expect(hull.fill.color.a, greaterThan(0));
      expect(hull.fill.color.a, lessThan(1), reason: 'a soft hull');
      expect(
        _rgb(hull.fill.color),
        anyOf(_rgb(swatch.container), _rgb(swatch.accent)),
      );
    });

    testWidgets('each selected tag is drawn in its own colour', (tester) async {
      final m = await mountTagLensBody(tester);

      m.lens
        ..toggleOwn(tagLensNeighbour.id)
        ..toggleOwn(tagLensWorkshop.id);
      await settleTagLensBody(tester);

      final neighbour = _drawnHull(tester, tagLensNeighbour.id).fill.color;
      final workshop = _drawnHull(tester, tagLensWorkshop.id).fill.color;
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

    testWidgets('selected tag hull paints above overlapping unselected hulls', (
      tester,
    ) async {
      final m = await mountTagLensBody(tester);

      m.lens.toggleOwn(tagLensGarden.id);
      await settleTagLensBody(tester);

      final order = _paintOrder(tester);
      final gardenAt = order[tester.renderObject(_hullOf(tagLensGarden.id))]!;
      final workshopAt =
          order[tester.renderObject(_hullOf(tagLensWorkshop.id))]!;
      expect(
        gardenAt,
        greaterThan(workshopAt),
        reason: 'the highlighted hull paints on top',
      );
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
    testWidgets('every own tag with field people has a hull before selection', (
      tester,
    ) async {
      await mountTagLensBody(tester);

      expect(_hullOf(tagLensNeighbour.id), findsOneWidget);
      expect(_hullOf(tagLensWorkshop.id), findsOneWidget);
      expect(_hullOf(tagLensGarden.id), findsOneWidget);
      expect(_hullOf(tagLensEmpty.id), findsNothing);
      expect(_anyHull(), findsNWidgets(3));
    });

    testWidgets('a selected own tag keeps every hull and highlights its own', (
      tester,
    ) async {
      final m = await mountTagLensBody(tester);

      m.lens.toggleOwn(tagLensNeighbour.id);
      await settleTagLensBody(tester);

      expect(_hullOf(tagLensNeighbour.id), findsOneWidget);
      expect(_hullOf(tagLensWorkshop.id), findsOneWidget);
      expect(_hullOf(tagLensGarden.id), findsOneWidget);
      expect(_anyHull(), findsNWidgets(3));

      final selected = _drawnHull(
        tester,
        tagLensNeighbour.id,
        expectStroke: true,
      );
      final dim = _drawnHull(tester, tagLensWorkshop.id);
      expect(selected.stroke, isNotNull);
      expect(dim.stroke, isNull);
      expect(selected.fill.color.a, greaterThan(dim.fill.color.a));
    });

    testWidgets('every selected own tag gets a highlighted hull', (
      tester,
    ) async {
      final m = await mountTagLensBody(tester);

      m.lens
        ..toggleOwn(tagLensNeighbour.id)
        ..toggleOwn(tagLensWorkshop.id);
      await settleTagLensBody(tester);

      expect(_hullOf(tagLensNeighbour.id), findsOneWidget);
      expect(_hullOf(tagLensWorkshop.id), findsOneWidget);
      expect(_anyHull(), findsNWidgets(3));
      expect(
        _drawnHull(tester, tagLensNeighbour.id, expectStroke: true).stroke,
        isNotNull,
      );
      expect(
        _drawnHull(tester, tagLensWorkshop.id, expectStroke: true).stroke,
        isNotNull,
      );
      expect(_drawnHull(tester, tagLensGarden.id).stroke, isNull);
    });

    testWidgets('deselecting a tag dims its hull but keeps it visible', (
      tester,
    ) async {
      final m = await mountTagLensBody(tester);
      m.lens
        ..toggleOwn(tagLensNeighbour.id)
        ..toggleOwn(tagLensWorkshop.id);
      await settleTagLensBody(tester);

      m.lens.toggleOwn(tagLensNeighbour.id);
      await settleTagLensBody(tester);

      expect(_hullOf(tagLensNeighbour.id), findsOneWidget);
      expect(_hullOf(tagLensWorkshop.id), findsOneWidget);
      expect(_drawnHull(tester, tagLensNeighbour.id).stroke, isNull);
      expect(
        _drawnHull(tester, tagLensWorkshop.id, expectStroke: true).stroke,
        isNotNull,
      );
    });

    testWidgets(
      'clearing the selection dims every hull but keeps them visible',
      (
        tester,
      ) async {
        final m = await mountTagLensBody(tester);
        m.lens
          ..toggleOwn(tagLensNeighbour.id)
          ..toggleOwn(tagLensGarden.id);
        await settleTagLensBody(tester);
        expect(
          _drawnHull(tester, tagLensNeighbour.id, expectStroke: true).stroke,
          isNotNull,
        );

        m.lens.clear();
        await settleTagLensBody(tester);

        expect(_anyHull(), findsNWidgets(3));
        expect(_drawnHull(tester, tagLensNeighbour.id).stroke, isNull);
        expect(_drawnHull(tester, tagLensGarden.id).stroke, isNull);
      },
    );

    testWidgets('a selected automatic tag has no hull of its own', (
      tester,
    ) async {
      final m = await mountTagLensBody(tester);

      m.lens.toggleAuto(ConstellationAutoTagKind.mutualContact);
      await settleTagLensBody(tester);

      expect(_anyHull(), findsNWidgets(3));
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
      expect(_anyHull(), findsNWidgets(3));
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
        expect(_hullOf(tagLensEmpty.id), findsNothing);
        expect(_anyHull(), findsNWidgets(3));
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

  group('tag lens hull highlight at phone width', () {
    testWidgets('RU 375x667 keeps every hull visible without overflow', (
      tester,
    ) async {
      final m = await mountTagLensBody(
        tester,
        locale: const Locale('ru'),
        surfaceSize: kPhoneSurface,
      );

      expect(_anyHull(), findsNWidgets(3));

      m.lens.toggleOwn(tagLensGarden.id);
      await settleTagLensBody(tester);

      expect(
        _drawnHull(tester, tagLensGarden.id, expectStroke: true).stroke,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
