import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/ui/widget/constellation_tag_hull_layer.dart';

import '../../support/constellation_tag_lens_body_harness.dart';
import '../../support/phone_surface.dart';

Set<String> _peopleInTag(String tagId) {
  for (final m in tagLensMemberships) {
    if (m.tagId == tagId) {
      return m.personIds.toSet();
    }
  }
  return {};
}

const _ownTagsOnField = [
  tagLensNeighbour,
  tagLensWorkshop,
  tagLensGarden,
];

List<Offset> _memberCentres(
  TagLensBodyHarness harness,
  String tagId,
) {
  final controller = harness.field.graphController;
  return [
    for (final id in _peopleInTag(tagId))
      controller.getPositionOrNullForId('fp:$id')!,
  ];
}

Path _hullPath(TagLensBodyHarness harness, String tagId) =>
    buildConstellationTagHullPath(_memberCentres(harness, tagId));

/// A scene point inside [tagId]'s hull and not on any map node.
Offset _emptyPointInHull(
  TagLensBodyHarness harness,
  String tagId, {
  String? alsoInsideTagId,
  bool onlyThisTag = false,
}) {
  final path = _hullPath(harness, tagId);
  final alsoPath = alsoInsideTagId == null
      ? null
      : _hullPath(harness, alsoInsideTagId);
  final cubit = harness.field;
  final bounds = path.getBounds().inflate(4);
  for (var y = bounds.top; y <= bounds.bottom; y += 6) {
    for (var x = bounds.left; x <= bounds.right; x += 6) {
      final point = Offset(x, y);
      if (!path.contains(point)) {
        continue;
      }
      if (alsoPath != null && !alsoPath.contains(point)) {
        continue;
      }
      if (onlyThisTag) {
        var coveredByOther = false;
        for (final tag in _ownTagsOnField) {
          if (tag.id == tagId) {
            continue;
          }
          if (alsoInsideTagId != null && tag.id == alsoInsideTagId) {
            continue;
          }
          if (_hullPath(harness, tag.id).contains(point)) {
            coveredByOther = true;
            break;
          }
        }
        if (coveredByOther) {
          continue;
        }
      }
      if (cubit.mapNodeAtSceneCentre(point) != null) {
        continue;
      }
      return point;
    }
  }
  fail('no empty hull point for $tagId');
}

ConstellationTagHullHitTester _hitTester(TagLensBodyHarness harness) {
  return ConstellationTagHullHitTester(
    hitsMapNode: (point) => harness.field.mapNodeAtSceneCentre(point) != null,
  );
}

void _syncHitTester(
  ConstellationTagHullHitTester hit,
  TagLensBodyHarness harness, {
  Set<String> selectedTagIds = const {},
}) {
  hit.update(
    controller: harness.field.graphController,
    tags: _ownTagsOnField,
    selectedTagIds: selectedTagIds,
    peopleOf: _peopleInTag,
  );
}

void main() {
  group('constellation tag hull hit test', () {
    testWidgets('empty space inside one hull resolves to that tag', (
      tester,
    ) async {
      final harness = await mountTagLensBody(tester);
      await settleTagLensBody(tester);

      final hit = _hitTester(harness);
      _syncHitTester(hit, harness);

      final point = _emptyPointInHull(
        harness,
        tagLensGarden.id,
        onlyThisTag: true,
      );
      expect(hit.tagHullAt(point), tagLensGarden.id);
    });

    testWidgets('overlapping hulls pick the later-painted unselected tag', (
      tester,
    ) async {
      final harness = await mountTagLensBody(tester);
      await settleTagLensBody(tester);

      final hit = _hitTester(harness);
      _syncHitTester(hit, harness);

      final point = _emptyPointInHull(
        harness,
        tagLensWorkshop.id,
        alsoInsideTagId: tagLensGarden.id,
      );
      expect(hit.tagHullAt(point), tagLensGarden.id);
    });

    testWidgets('overlapping hulls pick the selected tag first', (
      tester,
    ) async {
      final harness = await mountTagLensBody(tester);
      harness.lens.toggleOwn(tagLensWorkshop.id);
      await settleTagLensBody(tester);

      final hit = _hitTester(harness);
      _syncHitTester(
        hit,
        harness,
        selectedTagIds: {tagLensWorkshop.id},
      );

      final point = _emptyPointInHull(
        harness,
        tagLensWorkshop.id,
        alsoInsideTagId: tagLensGarden.id,
      );
      expect(hit.tagHullAt(point), tagLensWorkshop.id);
    });

    testWidgets('a point on a person inside the hull returns null', (
      tester,
    ) async {
      final harness = await mountTagLensBody(tester);
      await settleTagLensBody(tester);

      final hit = _hitTester(harness);
      _syncHitTester(hit, harness);

      final ann = harness.field.graphController.getPositionOrNullForId(
        'fp:ann',
      )!;
      expect(harness.field.mapNodeAtSceneCentre(ann), isNotNull);
      expect(hit.tagHullAt(ann), isNull);
    });

    testWidgets('a point outside every hull returns null', (tester) async {
      final harness = await mountTagLensBody(tester);
      await settleTagLensBody(tester);

      final hit = _hitTester(harness);
      _syncHitTester(hit, harness);

      expect(hit.tagHullAt(const Offset(-5000, -5000)), isNull);
    });

    testWidgets('twenty pointer moves rebuild each hull path only once', (
      tester,
    ) async {
      final harness = await mountTagLensBody(tester);
      await settleTagLensBody(tester);

      final hit = _hitTester(harness);
      _syncHitTester(
        hit..clearPathBuildCountForTesting(),
        harness,
      );
      expect(hit.pathBuildCount, _ownTagsOnField.length);

      final probe = _emptyPointInHull(harness, tagLensGarden.id);
      for (var i = 0; i < 20; i++) {
        hit.tagHullAt(probe);
      }
      expect(hit.pathBuildCount, _ownTagsOnField.length);

      _syncHitTester(hit, harness);
      expect(hit.pathBuildCount, _ownTagsOnField.length);
    });

    testWidgets('RU 375x667 harness still hit-tests hull empty space', (
      tester,
    ) async {
      final harness = await mountTagLensBody(
        tester,
        locale: const Locale('ru'),
        surfaceSize: kPhoneSurface,
      );
      await settleTagLensBody(tester);

      final hit = _hitTester(harness);
      _syncHitTester(hit, harness);

      final point = _emptyPointInHull(
        harness,
        tagLensGarden.id,
        onlyThisTag: true,
      );
      expect(hit.tagHullAt(point), tagLensGarden.id);
      expect(tester.takeException(), isNull);
    });
  });

  group('buildConstellationTagHullPath', () {
    test('matches painter geometry for fixed centres', () {
      const centres = [
        Offset(100, 100),
        Offset(200, 120),
        Offset(150, 200),
      ];
      final path = buildConstellationTagHullPath(centres);
      for (final centre in centres) {
        expect(path.contains(centre), isTrue);
      }
      expect(path.contains(const Offset(1000, 1000)), isFalse);
    });
  });
}
