// The tag view is a separate look at the members of the selected tags. It must
// leave the main Field exactly as it was (no composed position changes, no
// anchors written), lay out the same way every time, work for automatic tags,
// never pin on drag, offer the others-mode choice, find / forward from inside
// it, and move with a 400–500 ms transition unless motion is reduced.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/env.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/domain/constellation_tag_filter.dart';
import 'package:tentura/features/constellation/domain/constellation_tag_view_scope.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_apply_via_writes.dart';
import '../../support/constellation_tag_lens_body_harness.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';

/// A server that records anchor writes and never answers them.
final class _SilentAnchorRepository implements ConstellationWriteFake {
  final applyCalls = <List<ConstellationAnchorApplyOp>>[];

  @override
  Future<String> restoreLayoutSnapshot({
    required String snapshotId,
    required String clientOpId,
  }) => throw UnimplementedError('restore is not used by this test');

  @override
  Future<ConstellationAnchorResetResult> reset({
    required String clientOpId,
    bool saveHistory = false,
  }) => throw UnimplementedError('reset is not used by this test');

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) {
    applyCalls.add(List.of(ops));
    return Completer<ConstellationAnchorApplyResult>().future;
  }

  @override
  Future<ConstellationAnchorUpsertResult> upsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) => throw StateError('Placement must use batched apply');

  @override
  Future<ConstellationAnchorDeleteResult> delete({
    required ConstellationAnchorTarget target,
  }) => throw StateError('Unpin must use batched apply');
}

typedef _Mounted = ({TagLensBodyHarness body, _SilentAnchorRepository server});

Widget _body({bool reduceMotion = false}) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
    child: ConstellationBody(
      legendExpanded: false,
      onToggleLegend: () {},
      arrangeV2Enabled: true,
    ),
  ),
);

Future<_Mounted> _mount(
  WidgetTester tester, {
  bool reduceMotion = false,
  bool withRouter = false,
  ConstellationField? field,
}) async {
  final server = _SilentAnchorRepository();
  final sync = buildTestRealtimeSync();
  addTearDown(sync.port.dispose);
  final body = await mountTagLensBody(
    tester,
    field: field,
    withRouter: withRouter,
    bodyBuilder: () => _body(reduceMotion: reduceMotion),
    placementFor: (store) => ConstellationPlacementCase(
      server,
      store,
      FakeClockPort(),
      FakeWakeUpPort(),
      realtime: sync.case_,
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationTagViewModeTest'),
    ),
  );
  return (body: body, server: server);
}

const _everyone = ['ann', 'bob', 'cid', 'dan'];

/// Where the displayed graph has each person right now.
Map<String, Offset?> _positions(ConstellationCubit cubit) => {
  for (final id in _everyone)
    id: cubit.graphController.getPositionOrNullForId('fp:$id'),
};

Finder _node(String personId) =>
    find.byKey(TestIds.key(TestIds.graphNode(personId)));

/// The dot drawn for a non-member in "others as dots" mode.
Finder _dot(String personId) =>
    find.byKey(Key('constellation-tag-view-dot-$personId'));

void _enterNeighbour(TagLensBodyHarness m) => m.field.enterTagView(
  filter: const ConstellationTagFilter(selectedOwn: {'T-neighbour'}),
  ownTagIdsOf: m.rig.peopleTags.tagsOfPerson,
);

void _enterAutoITrust(TagLensBodyHarness m) => m.field.enterTagView(
  filter: const ConstellationTagFilter(
    selectedAuto: {ConstellationAutoTagKind.iTrust},
  ),
  ownTagIdsOf: m.rig.peopleTags.tagsOfPerson,
);

/// The Field of the tag-lens harness where Bob and Cid trust-by-me carry the
/// automatic "I trust" tag.
ConstellationField _fieldWithAutomaticTags() {
  final base = tagLensHarnessField();
  return base.copyWith(
    peers: [
      for (final p in base.peers)
        if (p.id == 'bob' || p.id == 'cid')
          p.copyWith(autoTagKinds: {ConstellationAutoTagKind.iTrust})
        else
          p,
    ],
  );
}

void main() {
  group('entering and leaving the tag view', () {
    testWidgets('leaves every main-Field position as it was and writes no '
        'anchors', (tester) async {
      final m = await _mount(tester);
      final before = _positions(m.body.field);
      final writes = m.body.field.writeCount;
      final composition = m.body.field.state.composition!;
      final composedAnchors = List.of(composition.anchorOverlay.anchors);
      expect(before.values, everyElement(isNotNull), reason: 'control');

      _enterNeighbour(m.body);
      await settleTagLensBody(tester);
      expect(m.body.field.state.tagView, isNotNull, reason: 'control');
      m.body.field.exitTagView();
      await settleTagLensBody(tester);

      expect(m.body.field.state.tagView, isNull);
      expect(_positions(m.body.field), before);
      expect(
        m.body.field.state.composition!.eligiblePersonIds,
        composition.eligiblePersonIds,
        reason: 'the main Field composes the same people',
      );
      expect(
        m.body.field.state.composition!.keptPeerIds,
        composition.keptPeerIds,
      );
      expect(
        m.body.field.state.composition!.anchorOverlay.anchors,
        composedAnchors,
        reason: 'composed placements are unchanged',
      );
      expect(m.body.field.writeCount, writes);
      expect(m.server.applyCalls, isEmpty);
      expect(m.body.rig.repository.appliedOps, isEmpty);
    });

    testWidgets('re-entering the same tag view gives the same layout', (
      tester,
    ) async {
      final m = await _mount(tester);

      _enterNeighbour(m.body);
      await settleTagLensBody(tester);
      final first = _positions(m.body.field);
      m.body.field.exitTagView();
      await settleTagLensBody(tester);
      _enterNeighbour(m.body);
      await settleTagLensBody(tester);

      expect(first['ann'], isNotNull, reason: 'a member is laid out');
      expect(_positions(m.body.field), first);
    });

    testWidgets('an automatic-tag view shows the members of that tag', (
      tester,
    ) async {
      final m = await _mount(tester, field: _fieldWithAutomaticTags());

      _enterAutoITrust(m.body);
      await settleTagLensBody(tester);

      final view = m.body.field.state.tagView;
      expect(view, isNotNull);
      expect(view!.scope.memberIds, {'bob', 'cid'});
      expect(_node('bob'), findsOneWidget);
      expect(_node('cid'), findsOneWidget);
    });
  });

  group('dragging in the tag view', () {
    testWidgets('writes nothing and the person snaps back', (tester) async {
      final m = await _mount(tester);
      _enterNeighbour(m.body);
      await settleTagLensBody(tester);
      final before = _positions(m.body.field);
      final writes = m.body.field.writeCount;

      final gesture = await tester.startGesture(
        tester.getCenter(_node('ann')),
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(10, 6));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        _positions(m.body.field)['ann'],
        isNot(before['ann']),
        reason: 'control: the person follows the pointer while held',
      );
      await gesture.up();
      await settleTagLensBody(tester);

      expect(m.server.applyCalls, isEmpty);
      expect(m.body.rig.repository.appliedOps, isEmpty);
      expect(m.body.field.writeCount, writes);
      expect(_positions(m.body.field), before);
    });
  });

  group('others mode', () {
    testWidgets('defaults to dots', (tester) async {
      final m = await _mount(tester);

      _enterNeighbour(m.body);
      await settleTagLensBody(tester);

      final view = m.body.field.state.tagView!;
      expect(view.others, ConstellationTagViewOthers.dots);
      expect(view.scope.dotIds, {'cid', 'dan'});
      expect(_dot('cid'), findsOneWidget);
      expect(_dot('dan'), findsOneWidget);
      expect(_dot('ann'), findsNothing, reason: 'members are not dots');
      expect(_dot('bob'), findsNothing, reason: 'members are not dots');
    });

    testWidgets('hide takes non-members out of the scene', (tester) async {
      final m = await _mount(tester);
      _enterNeighbour(m.body);
      await settleTagLensBody(tester);

      m.body.field.setTagViewOthers(ConstellationTagViewOthers.hide);
      await settleTagLensBody(tester);

      expect(_positions(m.body.field)['ann'], isNotNull);
      expect(_positions(m.body.field)['bob'], isNotNull);
      expect(_positions(m.body.field)['cid'], isNull);
      expect(_positions(m.body.field)['dan'], isNull);
      expect(_dot('cid'), findsNothing);
      expect(_dot('dan'), findsNothing);
    });

    testWidgets('as is keeps non-members in the scene, not as dots', (
      tester,
    ) async {
      final m = await _mount(tester);
      _enterNeighbour(m.body);
      await settleTagLensBody(tester);

      m.body.field.setTagViewOthers(ConstellationTagViewOthers.asIs);
      await settleTagLensBody(tester);

      expect(_positions(m.body.field)['cid'], isNotNull);
      expect(_positions(m.body.field)['dan'], isNotNull);
      expect(m.body.field.state.tagView!.scope.dotIds, isEmpty);
      expect(_dot('cid'), findsNothing);
      expect(_dot('dan'), findsNothing);
    });

    testWidgets('the header offers all three choices', (tester) async {
      final m = await _mount(tester);
      _enterNeighbour(m.body);
      await settleTagLensBody(tester);

      await tester.tap(find.byKey(const Key('constellation-tag-view-hide')));
      await settleTagLensBody(tester);
      expect(
        m.body.field.state.tagView!.others,
        ConstellationTagViewOthers.hide,
      );

      await tester.tap(find.byKey(const Key('constellation-tag-view-as-is')));
      await settleTagLensBody(tester);
      expect(
        m.body.field.state.tagView!.others,
        ConstellationTagViewOthers.asIs,
      );

      await tester.tap(find.byKey(const Key('constellation-tag-view-dots')));
      await settleTagLensBody(tester);
      expect(
        m.body.field.state.tagView!.others,
        ConstellationTagViewOthers.dots,
      );
    });
  });

  group('tag view header and actions', () {
    testWidgets('shows the tag name with its member count and an Exit', (
      tester,
    ) async {
      final m = await _mount(tester);

      _enterNeighbour(m.body);
      await settleTagLensBody(tester);

      expect(find.text('Neighbour · 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('constellation-tag-view-exit')));
      await settleTagLensBody(tester);

      expect(m.body.field.state.tagView, isNull);
      expect(find.text('Neighbour · 2'), findsNothing);
    });

    testWidgets('is drawn in the tag colour', (tester) async {
      final m = await _mount(tester);
      _enterNeighbour(m.body);
      await settleTagLensBody(tester);

      final header = find.text('Neighbour · 2');
      final swatch = tester
          .element(header)
          .tagColors
          .swatchFor(tagLensNeighbour.color);
      expect(tester.widget<Text>(header).style?.color, swatch.onContainer);
      expect(
        find.ancestor(
          of: header,
          matching: find.byWidgetPredicate(
            (w) =>
                (w is Material && w.color == swatch.container) ||
                (w is ColoredBox && w.color == swatch.container) ||
                (w is DecoratedBox &&
                    w.decoration is BoxDecoration &&
                    (w.decoration as BoxDecoration).color == swatch.container),
          ),
        ),
        findsWidgets,
      );
    });

    testWidgets('"Find in tag" looks a member up by name and selects them', (
      tester,
    ) async {
      final m = await _mount(tester);
      _enterNeighbour(m.body);
      await settleTagLensBody(tester);

      await tester.tap(find.text('Find in tag'));
      await settleTagLensBody(tester);
      await tester.enterText(
        find.byKey(const Key('constellation-tag-view-find-field')),
        'Bob',
      );
      await settleTagLensBody(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('constellation-tag-view-find-results')),
          matching: find.text('Bob'),
        ),
      );
      await settleTagLensBody(tester);

      expect(m.body.field.state.selectedPersonId, 'bob');
    });

    testWidgets('"Find in tag" does not offer people outside the tag', (
      tester,
    ) async {
      final m = await _mount(tester);
      _enterNeighbour(m.body);
      await settleTagLensBody(tester);

      await tester.tap(find.text('Find in tag'));
      await settleTagLensBody(tester);
      await tester.enterText(
        find.byKey(const Key('constellation-tag-view-find-field')),
        'Dan',
      );
      await settleTagLensBody(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('constellation-tag-view-find-results')),
          matching: find.text('Dan'),
        ),
        findsNothing,
      );
    });

    testWidgets('"Forward a request…" carries the viewed tag to the forward '
        'screen', (tester) async {
      final m = await _mount(
        tester,
        withRouter: true,
        field: tagLensHarnessFieldWithViewerRequests(),
      );
      _enterNeighbour(m.body);
      await settleTagLensBody(tester);

      await tester.tap(find.text('Forward a request…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Borrow a drill').last);
      await tester.pumpAndSettle();

      final route = m.body.router!.current;
      expect(route.name, 'ForwardBeaconRoute');
      expect(route.params.getString('id'), 'mine-open');
      expect(route.queryParams.getString('tags'), tagLensNeighbour.id);
    });
  });

  group('tapping a person in the tag view', () {
    testWidgets('selects them so their panel opens', (tester) async {
      final m = await _mount(tester);
      _enterNeighbour(m.body);
      await settleTagLensBody(tester);

      await tester.tap(_node('bob'));
      await settleTagLensBody(tester);

      expect(m.body.field.state.selectedPersonId, 'bob');
      expect(m.body.field.state.tagView, isNotNull, reason: 'still in view');
    });
  });

  group('entering the tag view animates from the Field places', () {
    testWidgets('takes between 400 and 500 ms', (tester) async {
      final m = await _mount(tester);
      final fieldPlaces = _positions(m.body.field);

      _enterNeighbour(m.body);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final before400 = _positions(m.body.field);
      await tester.pump(const Duration(milliseconds: 200));
      final after500 = _positions(m.body.field);
      await tester.pump(const Duration(seconds: 1));
      final settled = _positions(m.body.field);

      expect(settled['ann'], isNot(fieldPlaces['ann']), reason: 'it moved');
      expect(before400['ann'], isNot(settled['ann']), reason: 'not before 400');
      expect(after500, settled, reason: 'finished by 550 ms');
    });

    testWidgets('is instant with reduced motion', (tester) async {
      final m = await _mount(tester, reduceMotion: true);

      _enterNeighbour(m.body);
      await tester.pump();
      final immediately = _positions(m.body.field);
      await tester.pump(const Duration(milliseconds: 600));

      expect(immediately, _positions(m.body.field));
    });
  });

  group('leaving the tag view animates back to the Field places', () {
    testWidgets('takes between 400 and 500 ms', (tester) async {
      final m = await _mount(tester);
      final fieldPlaces = _positions(m.body.field);
      _enterNeighbour(m.body);
      await settleTagLensBody(tester);

      m.body.field.exitTagView();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final before400 = _positions(m.body.field);
      await tester.pump(const Duration(milliseconds: 200));
      final after500 = _positions(m.body.field);

      expect(
        before400['ann'],
        isNot(fieldPlaces['ann']),
        reason: 'not before 400',
      );
      expect(
        after500,
        fieldPlaces,
        reason: 'back at the Field places by 550 ms',
      );
    });

    testWidgets('is instant with reduced motion', (tester) async {
      final m = await _mount(tester, reduceMotion: true);
      final fieldPlaces = _positions(m.body.field);
      _enterNeighbour(m.body);
      await settleTagLensBody(tester);

      m.body.field.exitTagView();
      await tester.pump();

      expect(_positions(m.body.field), fieldPlaces);
    });
  });
}
