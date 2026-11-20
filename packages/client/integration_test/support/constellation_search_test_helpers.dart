import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_magnet_control.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_magnet_layer.dart';

EdgeInsets fieldSearchPickInsets(
  ConstellationCubit cubit,
  BuildContext resultContext,
) => cubit.fieldCameraViewportInsets(resultContext, contextPanelVisible: true);

/// Collect errors so that a missing node cannot prevent testing the next pick.
List<String> fieldSearchCameraMismatches(
  ConstellationCubit cubit,
  String id,
  EdgeInsets insets,
  Offset start, {
  String? postAuthorId,
}) {
  final graph = cubit.graphController;
  final safe = insets.deflateRect(Offset.zero & graph.viewportSize!);
  final centre = graph.viewportLocalToScene(safe.center);
  final nodeId = 'fr:$id';
  final position = graph.getPositionOrNullForId(nodeId);
  final failures = <String>[];
  if ((centre - start).distance <= 1) {
    failures.add('$id: the camera stayed at $start');
  }
  if (position == null) {
    failures.add('$id has no laid-out map position; camera centre is $centre');
  } else {
    if ((position - centre).distance > 1) {
      failures.add('$id is at $position, but the camera centres on $centre');
    }
    final size = graph.renderSnapshot.topology.nodesById[nodeId]!.size;
    final bounds = Rect.fromCenter(
      center: graph.sceneToViewportLocal(position),
      width: size.width * graph.cameraScale,
      height: size.height * graph.cameraScale,
    );
    if (bounds.intersect(safe) != bounds) {
      failures.add('$id at $bounds is outside the inset viewport $safe');
    }
  }
  if (postAuthorId != null) {
    final author = graph.getPositionOrNullForId('fp:$postAuthorId');
    expect(author, isNotNull, reason: 'the Post author has a laid-out node');
    if ((centre - author!).distance <= 1) {
      failures.add('$id: the camera centres on the author at $author');
    }
    if (position != null && (position - author).distance <= 1) {
      failures.add('$id and its author overlap at $author');
    }
  }
  return failures;
}

final fieldSearchMagnetMenuButton = find.descendant(
  of: find.descendant(
    of: find.byType(ConstellationTagMagnetLayer, skipOffstage: false),
    matching: find.byType(ConstellationTagMagnetControl, skipOffstage: false),
    skipOffstage: false,
  ),
  matching: find.widgetWithIcon(
    IconButton,
    Icons.more_vert,
    skipOffstage: false,
  ),
  skipOffstage: false,
);

Future<Offset> positionMagnetBehindSearchResult(
  WidgetTester tester,
  ConstellationCubit cubit,
  Finder result,
) async {
  expect(fieldSearchMagnetMenuButton, findsOneWidget);
  final map = find.descendant(
    of: find.byType(ConstellationBody, skipOffstage: false),
    matching: find.byType(InteractiveViewer, skipOffstage: false),
    skipOffstage: false,
  );
  final resultOverMap = tester.getRect(result).intersect(tester.getRect(map));
  expect(resultOverMap.isEmpty, isFalse);
  Rect overlap() =>
      resultOverMap.intersect(tester.getRect(fieldSearchMagnetMenuButton));
  final graph = cubit.graphController;
  // Position the live button beneath the result. Its label can shift clear of
  // a node after the camera moves, so remeasure the overlap after each frame.
  for (var attempt = 0; attempt < 4 && overlap().isEmpty; attempt++) {
    final centre = graph.viewportLocalToScene(
      graph.viewportSize!.center(Offset.zero),
    );
    final correction =
        (tester.getCenter(fieldSearchMagnetMenuButton) - resultOverMap.center) /
        graph.cameraScale;
    graph.jumpToPosition(centre + correction);
    await tester.pump();
  }
  expect(
    overlap().isEmpty,
    isFalse,
    reason:
        'result $resultOverMap must cover the magnet button at '
        '${tester.getRect(fieldSearchMagnetMenuButton)}',
  );
  return overlap().center;
}
