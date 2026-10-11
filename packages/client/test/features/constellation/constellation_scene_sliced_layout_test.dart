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

    testWidgets('a kept person on no trust path is placed', (tester) async {
      const loose = FieldPersonNode(
        person: Profile(id: 'c', displayName: 'C'),
        ring: 3,
        isKept: false,
      );
      scene
        ..layoutKeptPeerIds = const {'b', 'c'}
        ..layoutPaths = resolveConstellationPaths(
          egoId: 'a',
          visiblePeerIds: const {'b', 'c'},
          holderIds: const {'a', 'b'},
          edges: const [],
        );
      final looseAlgorithm = scene.layoutAlgorithm(
        graphRevision: 2,
        viewerId: 'a',
        statePaths: null,
        stateKeptPeerIds: const {'b', 'c'},
        forgetPriorHintNodeIds: const {},
      );
      final frames = <GraphLayoutFrame>[];
      Object? error;
      var done = false;
      looseAlgorithm
          .layout(
            sceneLayoutRequest(nodes: {_ego, _peer, loose}, edges: const {}),
          )
          .listen(
            frames.add,
            onError: (Object e) => error = e,
            onDone: () => done = true,
          );

      for (var i = 0; i < 20 && !done; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(error, isNull);
      expect(done, isTrue);
      expect(frames.single.positions.keys, contains(loose.graphNodeId));
      addTearDown(scene.dispose);
    });

    testWidgets(
      'a throw on completion ends the stream with an error, not a hang',
      (tester) async {
        // A person node the domain layout was never given has no seat; in
        // debug the missing-position assert throws inside onComplete.
        const stray = FieldPersonNode(
          person: Profile(id: 'stray', displayName: 'Stray'),
          ring: 3,
          isKept: false,
        );
        final frames = <GraphLayoutFrame>[];
        Object? error;
        var done = false;
        algorithm
            .layout(
              sceneLayoutRequest(nodes: {_ego, _peer, stray}, edges: const {}),
            )
            .listen(
              frames.add,
              onError: (Object e) => error = e,
              onDone: () => done = true,
            );

        for (var i = 0; i < 20 && !done; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(tester.takeException(), isNull);
        expect(done, isTrue, reason: 'the stream must close');
        expect(frames, isEmpty);
        expect(error, isA<AssertionError>());
        addTearDown(scene.dispose);
      },
    );

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
