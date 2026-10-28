import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:logging/logging.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_tag_magnet.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_tag_magnet_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_tag_magnet_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_overflow_group.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_magnet_control.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_magnet_layer.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/constellation_tag_lens_body_harness.dart';
import '../../support/test_realtime_sync.dart';

class _FieldRepository implements ConstellationRepositoryPort {
  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    final base = tagLensHarnessField();
    return base.copyWith(
      posts: [
        ConstellationPost(
          id: 'bob-post',
          authorId: 'bob',
          rootExcerpt: 'Sharing garden tools',
          lastActivityAt: DateTime.utc(2026, 10, 28),
        ),
      ],
      requests: [
        ...base.requests,
        for (var i = 0; i < 40; i++)
          ConstellationRequest(
            id: 'viewer-request-$i',
            authorId: 'ego',
            title: 'Viewer request $i',
            status: 0,
            isMine: true,
          ),
      ],
    );
  }
}

// The persistence boundary survives both Field instances, like the server does.
class _SavedMagnets implements ConstellationTagMagnetRepositoryPort {
  List<ConstellationTagMagnet> saved = [];
  int reads = 0;
  Completer<void>? readGate;

  @override
  Future<List<ConstellationTagMagnet>> list() async {
    reads++;
    await readGate?.future;
    return [...saved];
  }

  @override
  Future<ConstellationTagMagnet> upsert({
    required String tagId,
    required double xUnits,
    required double yUnits,
    required String clientOpId,
  }) async {
    final magnet = ConstellationTagMagnet(
      tagId: tagId,
      xUnits: xUnits,
      yUnits: yUnits,
      revision: 1,
    );
    saved = [magnet];
    return magnet;
  }

  @override
  Future<void> remove({
    required String tagId,
    required String clientOpId,
  }) async => saved = [];
}

Future<ConstellationCubit> _open(_SavedMagnets repository, Size size) async {
  final realtime = buildTestRealtimeSync();
  addTearDown(realtime.port.dispose);
  final cubit = ConstellationCubit(
    case_: ConstellationStoreFixture(
      _FieldRepository(),
      accountId: 'ego',
    ).store,
    viewer: tagLensHarnessEgo,
    ownTagIdsOf: (id) => {
      for (final membership in tagLensMemberships)
        if (membership.personIds.contains(id)) membership.tagId,
    },
    tagMagnetCase: ConstellationTagMagnetCase(
      repository,
      realtime.case_,
      env: const Env(),
      logger: Logger('restored magnet clearance'),
    ),
  );
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
  cubit.updateLabelBudgetContext(viewport: size, textScaleFactor: 1);
  return cubit;
}

Finder _map() => find.byType(GraphView<NodeDetails, EdgeDetails>);
Finder _magnet() => find.descendant(
  of: find.byType(ConstellationTagMagnetLayer),
  matching: find.byType(ConstellationTagMagnetControl),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

// Assert the actual labelled control, not just the overlay's collision metadata.
void _expectClusterOverflow(
  WidgetTester tester,
  ConstellationPresentationFrameHolder holder,
  String authorId,
) {
  expect(holder.frame, isNotNull);
  expect(
    holder.frame!.chips,
    contains(authorId),
    reason: '$authorId has enough requests to require a +N more chip',
  );
  final group = find.byWidgetPredicate(
    (w) => w is ConstellationOverflowGroup && w.authorId == authorId,
  );
  expect(
    group,
    findsOneWidget,
    reason:
        '$authorId builds exactly one overflow control, including occluded controls',
  );
  final control = tester.widget<ConstellationOverflowGroup>(group);
  expect(control.hiddenCount, greaterThan(0));
  final chip = find.byKey(Key('constellation.overflow.$authorId'));
  expect(chip, findsOneWidget);
  expect(find.descendant(of: group, matching: chip), findsOneWidget);
  final l10n = L10n.of(tester.element(group))!;
  expect(
    find.descendant(
      of: chip,
      matching: find.text(l10n.constellationMoreRequests(control.hiddenCount)),
    ),
    findsOneWidget,
    reason: 'the collision obstacle is the rendered +N more control',
  );
  final rendered = tester.getRect(chip).shift(-tester.getTopLeft(_map()));
  expect(
    rendered,
    rectMoreOrLessEquals(holder.frame!.chips[authorId]!),
    reason: 'the painted overflow control matches its clearance rectangle',
  );
  expect(
    rendered.overlaps(Offset.zero & tester.getSize(_map())),
    isTrue,
    reason: 'the overflow control is on the visible map',
  );
}

void _expectClear(
  WidgetTester tester,
  ConstellationPresentationFrameHolder holder,
) {
  expect(_magnet(), findsOneWidget);
  final frame = holder.frame!;
  expect(frame.bodies, contains('fp:ego'));
  expect(frame.labels, contains('fp:ego'));
  expect(frame.bodies, contains('fp:bob'));
  // Unconditional: a missing viewer chip must fail even if absent from frame.chips.
  _expectClusterOverflow(tester, holder, 'ego');
  for (final authorId in frame.chips.keys.where((id) => id != 'ego')) {
    _expectClusterOverflow(tester, holder, authorId);
  }
  final magnet = tester.getRect(_magnet()).shift(-tester.getTopLeft(_map()));
  final collisions = <String>[];
  for (final entry in frame.bodies.entries) {
    final circle = entry.value;
    final nearest = Offset(
      circle.center.dx.clamp(magnet.left, magnet.right),
      circle.center.dy.clamp(magnet.top, magnet.bottom),
    );
    if ((nearest - circle.center).distance < circle.shortestSide / 2) {
      collisions.add('circle ${entry.key}');
    }
  }
  final renderedCategories = <String>{};
  final mapOrigin = tester.getTopLeft(_map());
  final viewport = Offset.zero & tester.getSize(_map());
  for (final element in find.byType(GraphNodeWidget).evaluate()) {
    final nodeWidget = element.widget as GraphNodeWidget;
    final finder = find.byWidget(nodeWidget);
    final rect = tester.getRect(finder).shift(-mapOrigin);
    if (!rect.overlaps(viewport)) continue;
    final node = nodeWidget.nodeDetails;
    final category = switch (node) {
      FieldPersonNode(:final person) =>
        person.id == 'ego' ? 'viewer' : 'person',
      FieldBeaconNode(request: final request?) => 'request',
      FieldBeaconNode(post: final post?) => 'post',
      _ => throw StateError('Unexpected Field node: $node'),
    };
    renderedCategories.add(category);
    expect(
      frame.bodies,
      contains(node.graphNodeId),
      reason: 'every rendered $category node has a clearance obstacle',
    );
    if (node is FieldPersonNode) {
      final nearest = Offset(
        rect.center.dx.clamp(magnet.left, magnet.right),
        rect.center.dy.clamp(magnet.top, magnet.bottom),
      );
      if ((nearest - rect.center).distance < rect.shortestSide / 2) {
        collisions.add('rendered $category ${node.id}');
      }
    } else if (magnet.overlaps(rect)) {
      collisions.add('rendered $category ${node.id}');
    }
  }
  expect(
    renderedCategories,
    containsAll([
      'viewer',
      'person',
      // The desktop fixture displays request and post tiles; the phone's
      // zoom policy can hide those tiles. Every displayed tile is checked above.
      if (viewport.width > 1000) 'request',
      if (viewport.width > 1000) 'post',
    ]),
    reason: 'the fixtures exercise every visible Field node category',
  );
  for (final entry in frame.labels.entries) {
    if (magnet.overlaps(entry.value)) collisions.add('label ${entry.key}');
  }
  for (final entry in frame.chips.entries) {
    if (magnet.overlaps(entry.value)) collisions.add('overflow ${entry.key}');
  }
  expect(
    collisions,
    isEmpty,
    reason: 'magnet $magnet must clear painted obstacles',
  );
}

void main() {
  group('persisted Field magnet presentation', () {
    for (final size in [const Size(375, 667), const Size(1280, 900)]) {
      testWidgets(
        'reload at ${size.width.toInt()} pixels keeps magnets clear and builds one overflow control per cluster',
        (tester) async {
          final repository = _SavedMagnets();
          var first = await _open(repository, size);
          final active = ValueNotifier(first);
          addTearDown(active.dispose);
          var holder = ConstellationPresentationFrameHolder();
          final harness = await mountTagLensBody(
            tester,
            bodyBuilder: () => ValueListenableBuilder<ConstellationCubit>(
              valueListenable: active,
              builder: (_, cubit, _) => BlocProvider.value(
                value: cubit,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox.fromSize(
                    size: size,
                    child: MediaQuery(
                      data: MediaQueryData(size: size),
                      child: ConstellationBody(
                        key: ObjectKey(cubit),
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
            ),
          );
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await _settle(tester);
          expect(holder.frame!.bodies, contains('fp:ego'));
          _expectClusterOverflow(tester, holder, 'ego');
          if (size.width > 1000) {
            // A memberless magnet cannot move the graph. Pick a genuinely empty
            // screen region and compare its rendered scene position across reload.
            final viewport = Offset.zero & tester.getSize(_map());
            final obstacles = [
              ...holder.frame!.bodies.values,
              ...holder.frame!.labels.values,
              ...holder.frame!.chips.values,
            ];
            final candidates = <Rect>[
              for (var y = 16.0; y + 64 < viewport.height; y += 20)
                for (var x = 16.0; x + 220 < viewport.width; x += 20)
                  Rect.fromLTWH(x, y, 220, 64),
            ];
            final clear = candidates.where(
              (r) => obstacles.every((o) => !r.overlaps(o.inflate(12))),
            );
            expect(
              clear,
              isNotEmpty,
              reason: 'a clear persisted spot is available',
            );
            final safeScene = first.graphController.globalToScene(
              tester.getTopLeft(_map()) + clear.first.center,
            )!;
            first.placeTagMagnet(
              tagId: tagLensEmpty.id,
              position: safeScene,
              tagsOfPerson: harness.rig.peopleTags.tagsOfPerson,
            );
            await _settle(tester);
            _expectClear(tester, holder);
            final placedScene = first.graphController.globalToScene(
              tester.getCenter(_magnet()),
            )!;
            expect(repository.saved.single.tagId, tagLensEmpty.id);
            final reopened = await _open(repository, size);
            holder = ConstellationPresentationFrameHolder();
            active.value = reopened;
            await _settle(tester);
            _expectClear(tester, holder);
            final reloadedScene = reopened.graphController.globalToScene(
              tester.getCenter(_magnet()),
            )!;
            expect(
              (reloadedScene - placedScene).distance,
              lessThan(0.01),
              reason:
                  'a clear persisted magnet keeps its original rendered spot',
            );
            reopened.removeTagMagnet(tagLensEmpty.id);
            await _settle(tester);
            first = reopened;
          }
          final drop = holder.frame!.bodies['fp:ego']!.center;
          final scene = first.graphController.globalToScene(
            tester.getTopLeft(_map()) + drop,
          );
          expect(scene, isNotNull);
          first.placeTagMagnet(
            tagId: tagLensWorkshop.id,
            position: scene!,
            tagsOfPerson: harness.rig.peopleTags.tagsOfPerson,
          );
          await _settle(tester);
          expect(repository.saved, hasLength(1));
          expect(_magnet(), findsOneWidget);
          final reads = repository.reads;

          // Replace the entire Field and its frame cache; only server data survives.
          repository.readGate = Completer<void>();
          final restored = await _open(repository, size);
          holder = ConstellationPresentationFrameHolder();
          active.value = restored;
          await _settle(tester);
          expect(_magnet(), findsNothing);
          _expectClusterOverflow(tester, holder, 'ego');
          repository.readGate!.complete();
          for (var frame = 0; frame < 90; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            if (holder.frame != null && _magnet().evaluate().isNotEmpty) {
              _expectClear(tester, holder);
            }
          }
          expect(repository.reads, greaterThan(reads));
          expect(restored.tagMagnets, contains(tagLensWorkshop.id));
          _expectClear(tester, holder);
        },
      );
    }
  });
}
