import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field_target_kind.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_hide_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_tag_magnet_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/l10n/l10n.dart';

import 'support/constellation_search_test_helpers.dart';
import 'support/e2e_test_helpers.dart';

Future<Finder> _search(
  WidgetTester tester,
  String query,
  String kind,
  String id,
) async {
  await tapConstellationControl(
    tester,
    find.byKey(const Key('constellation.app_bar.search')),
  );
  await tester.enterText(find.byType(TextField).last, query);
  final row = find.byKey(Key('constellation.field_search.$kind.$id'));
  await pumpUntil(
    tester,
    () => finderHasMatch(row.hitTestable()),
    label: 'the $kind result for $query from Field search',
  );
  final hidden = L10n.of(
    tester.element(row),
  )!.constellationFieldSearchStatusHidden;
  expect(
    find.descendant(of: row, matching: find.textContaining(hidden)),
    findsOneWidget,
  );
  return row;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Field search frames hidden items and handles taps over a magnet menu button',
    (tester) async {
      e2eDrainExceptions = false;
      await launchApp(app.main);
      final fixture = await bootstrapWitnessFixture(
        runId: uniqueRunId('hidden-field-search'),
      );
      final requestQuery = 'Boxes ${DateTime.now().millisecondsSinceEpoch}';
      final postQuery = 'Ladder ${DateTime.now().millisecondsSinceEpoch}';
      await loginAs(tester, fixture.carolEmail);
      final request = await createPublishedBeacon(title: requestQuery);
      await forwardBeaconTo(beaconId: request, recipientId: fixture.eveUserId);
      final post = await createPublishedPost(
        body: postQuery,
        recipientIds: [fixture.eveUserId],
      );

      await loginAs(tester, fixture.eveEmail);
      final hide = GetIt.I<ConstellationFieldHideCase>();
      await hide.hide(
        targetKind: ConstellationFieldTargetKind.request.wireValue,
        targetId: request,
      );
      await hide.hide(
        targetKind: ConstellationFieldTargetKind.post.wireValue,
        targetId: post,
      );
      // Keep the magnet away from node labels so they cannot displace the
      // real menu button when it is positioned under a search suggestion.
      final tag = await GetIt.I<PeopleTagsCase>().createTag(name: 'Supplies');
      await GetIt.I<ConstellationTagMagnetCase>().save(
        tagId: tag.id,
        xUnits: 24,
        yUnits: -18,
      );

      await openConstellation(tester);
      await setConstellationViewMode(tester, ConstellationViewMode.map);
      final cubit = readConstellationCubit(tester);
      final graph = cubit.graphController;
      final authorNodeId = 'fp:${fixture.carolUserId}';
      await pumpUntil(
        tester,
        () =>
            cubit.fieldInitialFrameCompletedForTest &&
            !graph.isLayoutSettling &&
            graph.getPositionOrNullForId(authorNodeId) != null,
        label: 'the Field places the author and frames the map',
      );

      final field = cubit.state.field!;
      final projection = field.resolvedAnchorProjection;
      final loadedIds = {
        ...field.requests.map((request) => request.id),
        ...field.posts.map((post) => post.id),
        ...projection.pinnedRequests.map((request) => request.id),
        ...projection.anchors.map((anchor) => anchor.target.id),
      };
      expect(loadedIds, isNot(contains(request)));
      expect(loadedIds, isNot(contains(post)));

      final failures = <String>[];
      final requestResult = (request, 'request', requestQuery);
      final postResult = (post, 'post', postQuery);
      for (final ((id, kind, query), corner) in [
        (requestResult, const Offset(2000, 2000)),
        (requestResult, const Offset(2000, 14000)),
        (postResult, const Offset(14000, 14000)),
      ]) {
        final row = await _search(tester, query, kind, id);
        final insets = fieldSearchPickInsets(cubit, tester.element(row));
        final viewport = Offset.zero & graph.viewportSize!;
        final safe = insets.deflateRect(viewport);
        expect(safe.isEmpty, isFalse);
        graph.zoomBy(1.5 / graph.cameraScale);
        graph.jumpToPosition(corner);
        final before = graph.viewportLocalToScene(safe.center);
        final visible = [
          for (final node in graph.renderSnapshot.topology.nodesById.keys)
            if (graph.getPositionOrNullForId(node) case final point?)
              if (viewport
                  .inflate(100)
                  .contains(graph.sceneToViewportLocal(point)))
                node,
        ];
        expect(
          visible,
          isEmpty,
          reason: 'the $kind pick starts in an empty corner',
        );

        await tester.tap(row, kind: PointerDeviceKind.mouse);
        await pumpBounded(tester, frames: 30);
        expect(cubit.state.selectedRequestId, id);
        for (final failure in fieldSearchCameraMismatches(
          cubit,
          id,
          insets,
          before,
          postAuthorId: kind == 'post' ? fixture.carolUserId : null,
        )) {
          failures.add('Picking the $kind from $corner: $failure');
        }
      }

      await pumpUntil(
        tester,
        () => finderHasMatch(fieldSearchMagnetMenuButton),
        label: 'the saved magnet menu button',
      );
      for (final (id, kind, query) in [requestResult, postResult]) {
        final row = await _search(tester, query, kind, id);
        await pumpBounded(tester, frames: 12);
        final point = await positionMagnetBehindSearchResult(
          tester,
          cubit,
          row,
        );
        await tester.tapAt(point, kind: PointerDeviceKind.mouse);
        await pumpBounded(tester, frames: 30);
        expect(cubit.state.selectedRequestId, id);
        expect(
          find.byType(PopupMenuItem<bool>),
          findsNothing,
          reason:
              'tapping a $kind result over the magnet button keeps its menu closed',
        );
      }
      expect(failures, isEmpty);
    },
  );
}
