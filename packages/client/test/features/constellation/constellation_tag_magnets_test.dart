import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/domain/constellation_tag_filter.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_row.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_tag_lens_body_harness.dart';

Finder _chip(String name) => find.descendant(
  of: find.byType(ConstellationTagRow),
  matching: find.ancestor(
    of: find.text(name),
    matching: find.byType(PersonTagChip),
  ),
);

// The chip stays in the row. A magnet is a second, independently positioned
// label on the Field, not a selected chip or the tag lens's result caption.
Finder _magnet(String name) => find.byElementPredicate(
  (element) {
    final widget = element.widget;
    if (widget is! Text || widget.data != name) return false;
    var inRow = false;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is ConstellationTagRow) inRow = true;
      return !inRow;
    });
    return !inRow;
  },
  description: 'the $name magnet label outside the tag row',
);

Finder _map() => find.byType(GraphView<NodeDetails, EdgeDetails>);

Future<TagLensBodyHarness> _mount(
  WidgetTester tester, {
  ConstellationField? field,
}) => mountTagLensBody(
  tester,
  field: field,
  bodyBuilder: () => ConstellationBody(
    legendExpanded: false,
    onToggleLegend: () {},
    // Explicitly exercise the enabled feature, independently of ship gates.
    // ignore: avoid_redundant_argument_values
    peopleTagsEnabled: true,
    // Keep tag-view entry enabled even before the arrangement ship gate flips.
    // ignore: avoid_redundant_argument_values
    arrangeV2Enabled: true,
    // Keep membership behavior explicit across changes to the release default.
    // ignore: avoid_redundant_argument_values
    fieldMembershipV2Enabled: true,
  ),
);

Offset _person(TagLensBodyHarness body, String id) {
  final at = body.field.graphController.getPositionOrNullForId('fp:$id');
  expect(at, isNotNull, reason: '$id is present on the Field');
  return at!;
}

Map<String, Offset> _people(
  TagLensBodyHarness body, {
  Iterable<String> ids = const ['ann', 'bob', 'cid', 'dan'],
}) => {for (final id in ids) id: _person(body, id)};

// Use several frames so both the drag recognizer and a soft layout force can
// advance; a single long pump does not advance a simulation frame by frame.
Future<void> _drift(WidgetTester tester) async {
  for (var frame = 0; frame < 90; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Offset _dropPoint(WidgetTester tester, {bool left = false}) {
  final map = tester.getRect(_map());
  return Offset(left ? map.left + 100 : map.right - 100, map.top + 180);
}

Future<Offset> _dropTag(
  WidgetTester tester,
  TagLensBodyHarness body,
  String name,
  Offset target,
) async {
  expect(_chip(name), findsOneWidget, reason: 'own tag is available to drag');
  expect(tester.getRect(_map()).contains(target), isTrue);
  final sceneTarget = body.field.graphController.globalToScene(target);
  expect(sceneTarget, isNotNull);
  final start = tester.getCenter(_chip(name));
  final gesture = await tester.startGesture(start);
  // Supports the touch long-press drag without changing canvas long press.
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  for (var step = 1; step <= 12; step++) {
    await gesture.moveTo(Offset.lerp(start, target, step / 12)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await _drift(tester);
  return sceneTarget!;
}

void _expectMagnet(WidgetTester tester, String name) {
  expect(
    _magnet(name),
    findsOneWidget,
    reason: 'placing $name creates its own label on the Field',
  );
  expect(_chip(name), findsOneWidget, reason: 'the original tag is retained');
  expect(
    tester.getRect(_map()).contains(tester.getCenter(_magnet(name))),
    isTrue,
    reason: 'the label belongs to the map',
  );
  final labelBounds = tester.getRect(_magnet(name));
  expect(
    tester.getRect(_map()).intersect(labelBounds),
    labelBounds,
    reason: 'the whole label is visible inside the map after placement',
  );
  expect(
    _magnet(name).hitTestable(),
    findsOneWidget,
    reason: 'the placed label is reachable for its magnet menu',
  );
}

ConstellationField _withPinnedBob() {
  final field = tagLensHarnessField();
  final revision = ConstellationAnchorRevision(BigInt.one);
  return field.copyWith(
    anchorProjection: ConstellationAnchorProjection(
      revision: revision,
      anchors: [
        ConstellationAnchor(
          target: ConstellationAnchorTarget.person('bob'),
          position: const ConstellationAnchorPosition(
            xUnits: -1.5,
            yUnits: 0.5,
            coordinateSpaceVersion: 1,
          ),
          revision: revision,
          placedAt: DateTime.utc(2026, 10, 26),
        ),
      ],
      pinnedPeers: field.peers.where((person) => person.id == 'bob').toList(),
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

void main() {
  group('own tag magnets on the Field', () {
    testWidgets('dropping an own tag creates a label at the drop position', (
      tester,
    ) async {
      // A clear drop keeps its position. Request satellites attracted with
      // their author can occupy this spot and legitimately force clearance.
      final body = await _mount(
        tester,
        field: tagLensHarnessField().copyWith(requests: const []),
      );
      final target = _dropPoint(tester);

      final placed = await _dropTag(tester, body, 'Workshop', target);
      expect(body.field.tagMagnets[tagLensWorkshop.id], placed);

      _expectMagnet(tester, 'Workshop');
      expect(
        (tester.getCenter(_magnet('Workshop')) - target).distance,
        lessThan(kMinInteractiveDimension),
        reason: 'the label is placed where the chip was released',
      );
      expect(body.lens.state.isEmpty, isTrue);
      expect(body.field.state.tagView, isNull);
      expect(body.rig.repository.appliedOps, isEmpty);
    });

    // E9b does not prescribe a menu placement coordinate; either menu must
    // place a fully visible, interactive label on the current Field.
    testWidgets('a tag menu places a visible interactive magnet on the Field', (
      tester,
    ) async {
      await _mount(tester);

      await tester.longPress(_chip('Workshop'));
      await settleTagLensBody(tester);
      expect(find.text('Place as magnet'), findsOneWidget);
      await tester.tap(find.text('Place as magnet'));
      await _drift(tester);

      _expectMagnet(tester, 'Workshop');
    });

    testWidgets(
      'a secondary-tap menu places a visible interactive magnet on the Field',
      (
        tester,
      ) async {
        await _mount(tester);

        await tester.tap(
          _chip('Workshop'),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await settleTagLensBody(tester);

        expect(find.text('Place as magnet'), findsOneWidget);
        await tester.tap(find.text('Place as magnet'));
        await _drift(tester);
        _expectMagnet(tester, 'Workshop');
      },
    );

    testWidgets('unpinned members drift toward their magnet without pinning', (
      tester,
    ) async {
      final body = await _mount(tester);
      final before = _people(body);

      final target = await _dropTag(
        tester,
        body,
        'Neighbour',
        _dropPoint(tester),
      );

      for (final id in ['cid', 'dan']) {
        expect(
          _person(body, id),
          before[id],
          reason: '$id is not in Neighbour and must not be attracted',
        );
      }
      for (final id in ['ann', 'bob']) {
        final after = _person(body, id);
        expect(
          (after - target).distance,
          lessThan((before[id]! - target).distance - 1),
          reason: '$id belongs to Neighbour and must drift toward its magnet',
        );
        expect(
          (after - target).distance,
          greaterThan(1),
          reason: 'a magnet attracts softly instead of snapping people onto it',
        );
        expect(
          body.field.isAnchored(ConstellationAnchorTarget.person(id)),
          isFalse,
          reason: 'soft attraction never creates a person pin',
        );
      }
      expect(body.rig.repository.appliedOps, isEmpty);
    });

    testWidgets('a person with two magnet tags settles between their labels', (
      tester,
    ) async {
      final body = await _mount(tester);
      final before = _people(body);
      final left = await _dropTag(
        tester,
        body,
        'Neighbour',
        _dropPoint(tester, left: true),
      );
      for (final id in ['cid', 'dan']) {
        expect(
          _person(body, id),
          before[id],
          reason:
              '$id is not in Neighbour and stays put after the first magnet',
        );
      }
      final afterLeft = _person(body, 'ann');
      final right = await _dropTag(
        tester,
        body,
        'Workshop',
        _dropPoint(tester),
      );
      await _drift(tester);

      for (final id in ['cid', 'dan']) {
        expect(
          _person(body, id),
          before[id],
          reason:
              '$id belongs to neither magnet tag and must remain unaffected',
        );
      }
      final after = _person(body, 'ann');
      final midpoint = (left + right) / 2;
      expect(
        (after - midpoint).distance,
        lessThan((before['ann']! - midpoint).distance - 1),
        reason: 'Ann has both tags and is attracted to their combined centre',
      );
      expect(
        (after - right).distance,
        lessThan((afterLeft - right).distance - 1),
        reason: 'adding the second magnet contributes attraction of its own',
      );
      final axis = right - left;
      final relative = after - left;
      final fraction =
          (relative.dx * axis.dx + relative.dy * axis.dy) /
          axis.distanceSquared;
      expect(fraction, inExclusiveRange(0, 1));
      expect(
        (after - midpoint).distance,
        lessThan(axis.distance / 2),
        reason: 'Ann sits between the magnets rather than at either label',
      );
      expect(
        body.field.isAnchored(ConstellationAnchorTarget.person('ann')),
        isFalse,
      );
      _expectMagnet(tester, 'Neighbour');
      _expectMagnet(tester, 'Workshop');
    });

    testWidgets(
      'a magnet moves free members while a pinned member stays fixed',
      (
        tester,
      ) async {
        final body = await _mount(tester, field: _withPinnedBob());
        final before = _people(body);
        final anchors = List.of(
          body.field.state.field!.resolvedAnchorProjection.anchors,
        );
        expect(
          body.field.isAnchored(ConstellationAnchorTarget.person('bob')),
          isTrue,
          reason: 'Bob really is pinned before the magnet is placed',
        );

        final target = await _dropTag(
          tester,
          body,
          'Neighbour',
          _dropPoint(tester),
        );

        expect(
          (_person(body, 'ann') - target).distance,
          lessThan((before['ann']! - target).distance - 1),
          reason: 'the magnet is active for its free member',
        );
        expect(_person(body, 'bob'), before['bob']);
        await _drift(tester);
        expect(_person(body, 'bob'), before['bob']);
        expect(
          body.field.state.field!.resolvedAnchorProjection.anchors,
          anchors,
        );
      },
    );

    testWidgets(
      'tag view hides magnets and disables their placement without moving people',
      (
        tester,
      ) async {
        final body = await _mount(tester);
        void enterTagView() => body.field.enterTagView(
          filter: const ConstellationTagFilter(selectedOwn: {'T-neighbour'}),
          ownTagIdsOf: body.rig.peopleTags.tagsOfPerson,
        );
        enterTagView();
        await _drift(tester);
        expect(body.field.state.tagView?.scope.memberIds, {'ann', 'bob'});
        final tagViewBefore = _people(body, ids: ['ann', 'bob']);
        body.field.exitTagView();
        await _drift(tester);

        await _dropTag(tester, body, 'Neighbour', _dropPoint(tester));
        _expectMagnet(tester, 'Neighbour');
        enterTagView();
        await _drift(tester);

        expect(body.field.state.tagView?.scope.memberIds, {'ann', 'bob'});
        expect(
          _magnet('Neighbour'),
          findsNothing,
          reason: 'Field magnet labels are absent in tag view',
        );
        expect(_people(body, ids: ['ann', 'bob']), tagViewBefore);
        await _drift(tester);
        expect(
          _people(body, ids: ['ann', 'bob']),
          tagViewBefore,
          reason: 'no force runs in tag view',
        );

        await _dropTag(tester, body, 'Workshop', _dropPoint(tester));
        expect(
          _magnet('Workshop'),
          findsNothing,
          reason: 'dragging a tag cannot place a magnet in tag view',
        );
        expect(_magnet('Neighbour'), findsNothing);
        expect(_people(body, ids: ['ann', 'bob']), tagViewBefore);

        await tester.longPress(_chip('Workshop'));
        await settleTagLensBody(tester);
        expect(
          find.text('Place as magnet'),
          findsNothing,
          reason: 'the magnet placement menu action is unavailable in tag view',
        );
        expect(find.text('Remove'), findsNothing);
        expect(body.field.state.tagView?.scope.memberIds, {'ann', 'bob'});
        expect(_people(body, ids: ['ann', 'bob']), tagViewBefore);
        expect(body.rig.repository.appliedOps, isEmpty);
      },
    );

    testWidgets(
      'Remove stops attraction while retaining the tag and members',
      (
        tester,
      ) async {
        final body = await _mount(tester);
        final members = Set.of(body.rig.peopleTags.peopleInTag('T-workshop'));
        final before = _person(body, 'ann');
        final formerMagnet = await _dropTag(
          tester,
          body,
          'Workshop',
          _dropPoint(tester),
        );
        _expectMagnet(tester, 'Workshop');
        expect(
          (_person(body, 'ann') - formerMagnet).distance,
          lessThan((before - formerMagnet).distance - 1),
          reason: 'the magnet actively attracts Ann before Remove',
        );

        await tester.longPress(_magnet('Workshop'));
        await settleTagLensBody(tester);
        expect(find.text('Remove'), findsOneWidget);
        await tester.tap(find.text('Remove'));
        await _drift(tester);

        expect(_magnet('Workshop'), findsNothing);
        expect(_chip('Workshop'), findsOneWidget);
        expect(body.rig.peopleTags.peopleInTag('T-workshop'), members);
        expect(body.rig.repository.appliedOps, isEmpty);

        final afterRemoval = _people(body);
        final annDistanceAfterRemoval =
            (afterRemoval['ann']! - formerMagnet).distance;
        await _drift(tester);
        expect(
          (_person(body, 'ann') - formerMagnet).distance,
          greaterThanOrEqualTo(annDistanceAfterRemoval - 1e-6),
          reason: 'removing the label must also stop its soft attraction',
        );

        // Ann may already have reached equilibrium. A newly tagged person is
        // away from it, so a hidden magnet with a retained force cannot pass
        // merely because its original member has stopped moving.
        expect(members, isNot(contains('dan')));
        await body.rig.peopleTags.addToTag(
          personId: 'dan',
          tagId: 'T-workshop',
        );
        expect(
          body.rig.peopleTags.peopleInTag('T-workshop'),
          {...members, 'dan'},
          reason: 'Dan really joins the retained tag after its magnet is gone',
        );
        for (var pass = 0; pass < 3; pass++) {
          expect(body.field.graphController.requestSceneLayout(), isNotNull);
          await _drift(tester);
          expect(
            (_person(body, 'ann') - formerMagnet).distance,
            greaterThanOrEqualTo(annDistanceAfterRemoval - 1e-6),
            reason: 'a later layout must not resume the removed attraction',
          );
          expect(
            _person(body, 'dan'),
            afterRemoval['dan'],
            reason: 'new tag members must not drift toward a removed magnet',
          );
          expect(_magnet('Workshop'), findsNothing);
        }
      },
    );
  });
}
