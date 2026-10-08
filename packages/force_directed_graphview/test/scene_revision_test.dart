import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'support/int_graph_controller.dart';

// Use a runtime lookup so the missing public getter is an assertion failure,
// rather than preventing the test file from loading.
int _sceneRevision(Object controller) {
  try {
    // ignore: avoid_dynamic_calls -- Exercise the not-yet-present public getter.
    final Object? revision = (controller as dynamic).sceneRevision;
    expect(revision, isA<int>(), reason: 'sceneRevision is an integer');
    return revision! as int;
  } on NoSuchMethodError {
    fail('GraphController must expose sceneRevision for geometry consumers');
  }
}

void main() {
  group('Coherent scene geometry revision', () {
    test('snapshot reads preserve revision and geometry changes advance it',
        () {
      final controller = testIntIntGraphController();
      addTearDown(controller.dispose);

      final emptyRevision = _sceneRevision(controller);
      const node = Node<int>(data: 1, size: 40);
      controller.reconcileTopology({node}, const {});
      final topologyRevision = _sceneRevision(controller);
      expect(topologyRevision, greaterThan(emptyRevision));

      controller.scene.beginPresentation('1', ScenePoint(x: 100, y: 100));
      final displayedRevision = _sceneRevision(controller);
      expect(displayedRevision, greaterThan(topologyRevision));

      final painted = controller.renderSnapshot;
      final hitTested = controller.renderSnapshot;
      expect(painted.resolvePosition('1'), hitTested.resolvePosition('1'));
      expect(_sceneRevision(controller), displayedRevision);
      expect(_sceneRevision(controller), displayedRevision);

      controller.scene.beginPresentation('1', ScenePoint(x: 140, y: 100));
      expect(_sceneRevision(controller), greaterThan(displayedRevision));
      expect(
        controller.renderSnapshot.resolvePosition('1'),
        ScenePoint(x: 140, y: 100),
      );
    });
  });
}
