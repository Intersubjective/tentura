import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';
import 'package:tentura/domain/scheduling/adaptive_slice_controller.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_scene_controller.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/ui/utils/frame_slice_scheduler.dart';

import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../graph/scene_layout_test_support.dart';

const _ego = FieldPersonNode(
  person: Profile(id: 'a', displayName: 'A'),
  ring: 0,
  isKept: true,
);
const _peer = FieldPersonNode(
  person: Profile(id: 'b', displayName: 'B'),
  ring: 1,
  isKept: false,
);

void main() {
  group('ConstellationSceneController sliced layout', () {
    late ConstellationSceneController scene;
    late SceneLayoutAlgorithm algorithm;

    setUp(() {
      scene = ConstellationSceneController(
        slicer: FrameSliceScheduler(
          clock: FakeClockPort(),
          wakeUpPort: FakeWakeUpPort(),
          controller: AdaptiveSliceController(
            initialUnitCost: const Duration(microseconds: 100),
          ),
        ),
      )
        ..layoutEgoId = 'a'
        ..layoutKeptPeerIds = const {'b'}
        ..layoutPaths = resolveConstellationPaths(
          egoId: 'a',
          visiblePeerIds: const {'b'},
          holderIds: const {'a', 'b'},
          edges: const [],
        );
      addTearDown(scene.graphController.dispose);
      algorithm = scene.layoutAlgorithm(
        graphRevision: 1,
        viewerId: 'a',
        statePaths: null,
        stateKeptPeerIds: const {'b'},
        forgetPriorHintNodeIds: const {},
      );
    });

    GraphLayoutRequest request() =>
        sceneLayoutRequest(nodes: {_ego, _peer}, edges: const {});

    testWidgets('completion publishes the layout result', (tester) async {
      final frames = <GraphLayoutFrame>[];
      var done = false;
      algorithm
          .layout(request())
          .listen(frames.add, onDone: () => done = true);

      for (var i = 0; i < 20 && !done; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(done, isTrue);
      expect(frames, hasLength(1));
      expect(frames.single.isTerminal, isTrue);
      expect(
        frames.single.positions.keys,
        containsAll([_ego.graphNodeId, _peer.graphNodeId]),
      );
      addTearDown(scene.dispose);
    });

    testWidgets('a newer layout request cancels the older job', (tester) async {
      var firstFrames = 0;
      var secondFrames = 0;
      var secondDone = false;
      algorithm.layout(request()).listen((_) => firstFrames++);
      algorithm
          .layout(request())
          .listen((_) => secondFrames++, onDone: () => secondDone = true);

      for (var i = 0; i < 20 && !secondDone; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(secondDone, isTrue);
      expect(secondFrames, 1);
      expect(firstFrames, 0);
      addTearDown(scene.dispose);
    });
  });
}
