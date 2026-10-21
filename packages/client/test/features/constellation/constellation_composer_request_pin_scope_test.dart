// A Request the viewer has already pinned keeps its pin data while the
// composer is open: it stays anchored, so the viewer can still unpin it, but
// it is not drawn in the people-only composing scene.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/constellation/constellation_geometry.dart';

import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';

import '../../support/constellation_composer_screen_harness.dart';

const _pinnedRequestId = 'req-a';
final _pinnedTarget = ConstellationAnchorTarget.beacon(_pinnedRequestId);

ConstellationField _fieldWithPinnedRequest() {
  final base = composerHarnessField(peers: const ['a', 'b']);
  return ConstellationField(
    loadedAt: base.loadedAt,
    context: base.context,
    peers: base.peers,
    edges: base.edges,
    requests: base.requests,
    anchorProjection: ConstellationAnchorProjection(
      revision: ConstellationAnchorRevision(BigInt.one),
      anchors: [
        ConstellationAnchor(
          target: _pinnedTarget,
          position: const ConstellationAnchorPosition(
            xUnits: 40,
            yUnits: -30,
            coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
          ),
          revision: ConstellationAnchorRevision(BigInt.one),
          placedAt: DateTime.utc(2026, 10, 9),
        ),
      ],
      pinnedPeers: const [],
      pinnedRequests: base.requests,
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

Future<ConstellationCubit> _openComposerOverPinnedRequest(
  WidgetTester tester,
) async {
  final cubit = await loadComposerHarnessCubit(
    ComposerHarnessRepository(_fieldWithPinnedRequest),
  );
  final composer = buildComposerHarnessComposer();
  await pumpComposerHarnessScreen(tester, cubit: cubit, composer: composer);
  final controller = cubit.graphController;
  composer.start(
    BeaconKind.request,
    controller.viewportLocalToScene(
      controller.viewportSize!.center(Offset.zero),
    ),
  );
  await tester.pumpAndSettle();
  expect(cubit.state.isComposing, isTrue);
  return cubit;
}

void main() {
  group('pinned Request while the composer is open', () {
    testWidgets(
      'is still reported as anchored before the composer starts',
      (tester) async {
        final cubit = await loadComposerHarnessCubit(
          ComposerHarnessRepository(_fieldWithPinnedRequest),
        );
        final composer = buildComposerHarnessComposer();
        await pumpComposerHarnessScreen(
          tester,
          cubit: cubit,
          composer: composer,
        );

        expect(cubit.isAnchored(_pinnedTarget), isTrue);
        expect(cubit.canPinTarget(_pinnedTarget), isTrue);
      },
    );

    testWidgets(
      'stays anchored and keeps its Unpin action while composing',
      (tester) async {
        final cubit = await _openComposerOverPinnedRequest(tester);

        expect(
          cubit.isAnchored(_pinnedTarget),
          isTrue,
          reason: 'the composing scene must not erase the Request pin data',
        );
        expect(
          cubit.canPinTarget(_pinnedTarget),
          isTrue,
          reason: 'an anchored target keeps its Unpin action while composing',
        );
      },
    );

    testWidgets(
      'is not drawn in the people-only composing scene',
      (tester) async {
        final cubit = await _openComposerOverPinnedRequest(tester);

        final beaconNodes = cubit.graphController.nodes
            .whereType<FieldBeaconNode>()
            .toList();
        expect(
          beaconNodes,
          isEmpty,
          reason: 'keeping pin data must not re-add Requests to the scene',
        );
      },
    );
  });
}
