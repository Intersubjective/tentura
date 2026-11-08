// #938: arranging toolbar lives in top chrome; bottom map stays unobstructed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/phone_surface.dart' show kPhoneSurface, usePhoneSurface;
import 'fixtures/constellation_field_test_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

void main() {
  testWidgets(
    'Arranging map drag is not clamped to a bottom toolbar (375 RU)',
    (tester) async {
      await usePhoneSurface(tester);
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      final holder = ConstellationPresentationFrameHolder();

      await pumpConstellationBody(
        tester,
        cubit,
        size: kPhoneSurface,
        presentationFrameHolder: holder,
        arrangeV2Enabled: true,
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final selection = tester.constellationSelectionUnderTest();
      enableConstellationTouchNodeDragsForTests(selection);
      selection.enterArranging();
      await tester.pumpAndSettle();

      cubit.graphController.zoomBy(3);
      await tester.pumpAndSettle();

      cubit.beginDragExisting(target: ConstellationAnchorTarget.person('ego'));
      await tester.pumpAndSettle();

      final egoPayload =
          cubit.graphController.nodePayloadForId('fp:ego')! as FieldPersonNode;
      final graphId = egoPayload.graphNodeId;
      final deep = cubit.clampClusterDragPosition(
        egoPayload,
        const Offset(0, 9000),
      );

      cubit.updateDragPresentation(nodeId: graphId, sceneCentre: deep);
      await tester.pump();

      final toolbar = find.byKey(const Key('constellation.arranging.toolbar'));
      final graph = find.byType(GraphView<NodeDetails, EdgeDetails>);
      expect(
        find.descendant(of: graph, matching: toolbar),
        findsNothing,
        reason: 'toolbar is not a bottom overlay on the map',
      );

      final hint = find.byKey(const Key('constellation.arranging.hint'));
      expect(hint, findsOneWidget);
      expect(
        tester.widget<Text>(hint).data,
        L10nRu().constellationArrangingHintTouch,
      );
    },
  );
}
