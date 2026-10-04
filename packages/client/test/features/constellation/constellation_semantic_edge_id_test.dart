import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_edge_style.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_graph_scene.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';

FieldPersonNode _person(String id, {int ring = 1}) => FieldPersonNode(
  person: Profile(id: id, displayName: id),
  ring: ring,
  isKept: true,
  size: 40,
);

String _pairKey(NodeDetails src, NodeDetails dst) =>
    '${tenturaGraphNodeId(src)}->${tenturaGraphNodeId(dst)}';

String _semanticId(
  NodeDetails src,
  NodeDetails dst,
  ConstellationEdgeKind kind,
) => '${_pairKey(src, dst)}#${kind.name}';

EdgeDetails _edge(
  NodeDetails src,
  NodeDetails dst,
  ConstellationEdgeKind kind,
) => EdgeDetails(
  source: src,
  destination: dst,
  color: Colors.transparent,
  strokeWidth: 2,
  semanticId: _semanticId(src, dst, kind),
);

const _ego = Profile(id: 'ego', displayName: 'Ego');

final class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

Future<ConstellationCubit> _loadCubit(ConstellationField field) async {
  final cubit = ConstellationCubit(
    case_: ConstellationFieldCase(
      _StubRepository(field),
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationSemanticEdgeIdTest'),
    ),
    viewer: _ego,
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

/// Loads a field, then forces path resolution in which peer `a` is both a
/// kept tier-1 child of the viewer and a ring peer, so the graph build has to
/// emit two edges of different kinds between the same pair of nodes.
Future<ConstellationCubit> _loadCubitWithOverlappingPeerKinds() async {
  final cubit = await _loadCubit(
    ConstellationField(
      loadedAt: DateTime.utc(2026, 9, 9),
      context: '',
      peers: [const ConstellationPerson(id: 'a')],
      edges: [
        const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
      ],
      requests: const [],
    ),
  );
  cubit.emit(
    cubit.state.copyWith(
      keptPeerIds: {'a'},
      selectedPersonId: 'a',
      paths: (
        depth: {'a': 1},
        derived: <String, int>{},
        parent: {'a': 'ego'},
        parentTier: {'a': 1},
        attributed: <String>{},
        keep: {'a'},
        ring: {'a'},
      ),
      graphLayoutFailureMessage: 'forced rebuild',
    ),
  );
  cubit.retryGraphLayoutAfterFailure();
  return cubit;
}

class _RecordedLine {
  _RecordedLine(this.from, this.to, this.color, this.width);

  final Offset from;
  final Offset to;
  final Color color;
  final double width;
}

class _RecordingCanvas extends Fake implements Canvas {
  final lines = <_RecordedLine>[];

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    lines.add(_RecordedLine(p1, p2, paint.color, paint.strokeWidth));
  }
}

class _NeverListenable implements Listenable {
  const _NeverListenable();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

void main() {
  final src = _person('a', ring: 0);
  final dst = _person('b');

  group('EdgeDetails semantic identity', () {
    test('default semantic id is the endpoint pair of the scene node ids', () {
      final edge = EdgeDetails(
        source: src,
        destination: dst,
        color: Colors.transparent,
      );

      expect(edge.semanticId, _pairKey(src, dst));
    });

    test('edges with the same endpoints and visuals but different semantic '
        'ids are distinct set members', () {
      final tier1 = _edge(src, dst, ConstellationEdgeKind.tier1Path);
      final attachment = _edge(src, dst, ConstellationEdgeKind.attachment);

      expect(tier1.strokeWidth, attachment.strokeWidth);
      expect(tier1.color, attachment.color);
      expect(tier1, isNot(equals(attachment)));
      expect({tier1, attachment}, hasLength(2));
    });

    test('edges with the same semantic id are equal and hash alike', () {
      final first = _edge(src, dst, ConstellationEdgeKind.tier1Path);
      final second = _edge(src, dst, ConstellationEdgeKind.tier1Path);

      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);
      expect({first, second}, hasLength(1));
    });

    test('copyWith keeps the semantic id', () {
      final edge = _edge(src, dst, ConstellationEdgeKind.tier2Path);

      expect(edge.copyWith(strokeWidth: 5).semanticId, edge.semanticId);
    });
  });

  group('constellation cubit graph with parallel edges', () {
    test('kept peer that is also a ring peer keeps both its path edge and '
        'its ring stub', () async {
      final cubit = await _loadCubitWithOverlappingPeerKinds();
      addTearDown(cubit.close);

      final egoToPeer = cubit.graphController.edges
          .where((e) => e.source.id == 'ego' && e.destination.id == 'a')
          .toList();
      final ego = egoToPeer.first.source;
      final peer = egoToPeer.first.destination;

      expect(egoToPeer, hasLength(2));
      expect(
        egoToPeer.map((e) => e.semanticId).toSet(),
        {
          _semanticId(ego, peer, ConstellationEdgeKind.tier1Path),
          _semanticId(ego, peer, ConstellationEdgeKind.ringStub),
        },
      );
    });

    test('scene registers one edge id per kind and maps it to that kind', () async {
      final cubit = await _loadCubitWithOverlappingPeerKinds();
      addTearDown(cubit.close);

      final sceneEdges = cubit.graphController.renderSnapshot.topology.edgesById;

      expect(sceneEdges, hasLength(2));
      expect(cubit.edgeKinds.keys.toSet(), sceneEdges.keys.toSet());
      for (final entry in sceneEdges.entries) {
        final edge = entry.value.payload;
        final kind = ConstellationEdgeKind.values.byName(
          edge.semanticId.split('#').last,
        );
        expect(cubit.edgeKinds[entry.key], kind);
        expect(
          entry.key,
          constellationSceneEdgeId(
            kindName: kind.name,
            source: edge.source,
            destination: edge.destination,
          ),
        );
        expect(cubit.edgeKindByPair[edge.semanticId], kind);
      }
      expect(
        cubit.edgeKinds.values.toSet(),
        {ConstellationEdgeKind.tier1Path, ConstellationEdgeKind.ringStub},
      );
    });

    test('resolving each emitted edge against the registered ids gives its '
        'own scene id', () async {
      final cubit = await _loadCubitWithOverlappingPeerKinds();
      addTearDown(cubit.close);

      final sceneIds = cubit.graphController.renderSnapshot.topology.edgesById
          .keys
          .toList();
      for (final edge in cubit.graphController.edges) {
        final kind = ConstellationEdgeKind.values.byName(
          edge.semanticId.split('#').last,
        );
        final expected = constellationSceneEdgeId(
          kindName: kind.name,
          source: edge.source,
          destination: edge.destination,
        );
        expect(constellationEdgeIdForEdge(edge, sceneIds), expected);
        expect(
          constellationEdgeIdForEdge(edge, sceneIds.reversed),
          expected,
        );
      }
    });

    test('ordinary edges keep their scene ids and carry a kind-qualified '
        'semantic id', () async {
      final cubit = await _loadCubit(
        ConstellationField(
          loadedAt: DateTime.utc(2026, 9, 9),
          context: '',
          peers: [const ConstellationPerson(id: 'a')],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
          requests: [
            const ConstellationRequest(
              id: 'req-a',
              authorId: 'a',
              title: 'Need tools',
              status: 0,
            ),
          ],
        ),
      );
      addTearDown(cubit.close);
      cubit.selectPerson('a');

      final sceneEdges = cubit.graphController.renderSnapshot.topology.edgesById;
      expect(sceneEdges.keys.toSet(), {
        'c:tier1Path:fp:ego->fp:a',
        'c:attachment:fp:a->fr:req-a',
      });
      expect(
        sceneEdges['c:tier1Path:fp:ego->fp:a']!.payload.semanticId,
        'fp:ego->fp:a#tier1Path',
      );
      expect(
        sceneEdges['c:attachment:fp:a->fr:req-a']!.payload.semanticId,
        'fp:a->fr:req-a#attachment',
      );
    });
  });

  group('constellation scene edge id resolution', () {
    test('parallel edges resolve to the scene id of their own kind', () {
      final tier1 = _edge(src, dst, ConstellationEdgeKind.tier1Path);
      final attachment = _edge(src, dst, ConstellationEdgeKind.attachment);
      final tier1Id = constellationSceneEdgeId(
        kindName: ConstellationEdgeKind.tier1Path.name,
        source: src,
        destination: dst,
      );
      final attachmentId = constellationSceneEdgeId(
        kindName: ConstellationEdgeKind.attachment.name,
        source: src,
        destination: dst,
      );
      final known = [tier1Id, attachmentId];

      expect(constellationEdgeIdForEdge(tier1, known), tier1Id);
      expect(constellationEdgeIdForEdge(attachment, known), attachmentId);
    });

    test('resolution does not depend on the order of known ids', () {
      final attachment = _edge(src, dst, ConstellationEdgeKind.attachment);
      final tier1Id = constellationSceneEdgeId(
        kindName: ConstellationEdgeKind.tier1Path.name,
        source: src,
        destination: dst,
      );
      final attachmentId = constellationSceneEdgeId(
        kindName: ConstellationEdgeKind.attachment.name,
        source: src,
        destination: dst,
      );

      expect(
        constellationEdgeIdForEdge(attachment, [tier1Id, attachmentId]),
        attachmentId,
      );
      expect(
        constellationEdgeIdForEdge(attachment, [attachmentId, tier1Id]),
        attachmentId,
      );
    });
  });

  group('constellation edge painter with parallel edges', () {
    ConstellationEdgePainter painterFor(
      Map<String, ConstellationEdgeKind> kindsBySemanticId,
    ) => ConstellationEdgePainter(
      edgeKindByPair: kindsBySemanticId,
      tt: TenturaTokens.light,
      scheme: const ColorScheme.light(),
      repaint: const _NeverListenable(),
      cameraScale: () => 1,
    );

    test('each parallel edge is painted with the style of its own kind', () {
      final solid = _edge(src, dst, ConstellationEdgeKind.tier1Path);
      final dashed = _edge(src, dst, ConstellationEdgeKind.tier2Path);
      final painter = painterFor({
        solid.semanticId: ConstellationEdgeKind.tier1Path,
        dashed.semanticId: ConstellationEdgeKind.tier2Path,
      });

      final solidCanvas = _RecordingCanvas();
      painter.paint(solidCanvas, solid, Offset.zero, const Offset(200, 0));
      final dashedCanvas = _RecordingCanvas();
      painter.paint(dashedCanvas, dashed, Offset.zero, const Offset(200, 0));

      expect(solidCanvas.lines, hasLength(1), reason: 'solid is one segment');
      expect(
        dashedCanvas.lines.length,
        greaterThan(1),
        reason: 'dashed is several segments',
      );
      final solidStyle = constellationEdgeStyle(
        ConstellationEdgeKind.tier1Path,
        TenturaTokens.light,
        const ColorScheme.light(),
      );
      final dashedStyle = constellationEdgeStyle(
        ConstellationEdgeKind.tier2Path,
        TenturaTokens.light,
        const ColorScheme.light(),
      );
      expect(
        solidCanvas.lines.single.color.toARGB32(),
        solidStyle.color.toARGB32(),
      );
      expect(solidCanvas.lines.single.width, solidStyle.width);
      for (final line in dashedCanvas.lines) {
        expect(line.color.toARGB32(), dashedStyle.color.toARGB32());
        expect(line.width, dashedStyle.width);
      }
      expect(
        (dashedCanvas.lines.first.to - dashedCanvas.lines.first.from).distance,
        closeTo(dashedStyle.dash, 0.001),
        reason: 'each dash segment has the dash length of its own kind',
      );
    });

    test('parallel edges of kinds with different color and width are painted '
        'with their own color and width', () {
      final path = _edge(src, dst, ConstellationEdgeKind.tier1Path);
      final attachment = _edge(src, dst, ConstellationEdgeKind.attachment);
      final painter = painterFor({
        path.semanticId: ConstellationEdgeKind.tier1Path,
        attachment.semanticId: ConstellationEdgeKind.attachment,
      });
      final pathStyle = constellationEdgeStyle(
        ConstellationEdgeKind.tier1Path,
        TenturaTokens.light,
        const ColorScheme.light(),
      );
      final attachmentStyle = constellationEdgeStyle(
        ConstellationEdgeKind.attachment,
        TenturaTokens.light,
        const ColorScheme.light(),
      );
      expect(pathStyle.color, isNot(attachmentStyle.color));
      expect(pathStyle.width, isNot(attachmentStyle.width));

      final pathCanvas = _RecordingCanvas();
      painter.paint(pathCanvas, path, Offset.zero, const Offset(200, 0));
      final attachmentCanvas = _RecordingCanvas();
      painter.paint(
        attachmentCanvas,
        attachment,
        Offset.zero,
        const Offset(200, 0),
      );

      expect(pathCanvas.lines, hasLength(1));
      expect(
        pathCanvas.lines.single.color.toARGB32(),
        pathStyle.color.toARGB32(),
      );
      expect(pathCanvas.lines.single.width, pathStyle.width);
      expect(attachmentCanvas.lines, hasLength(1));
      expect(
        attachmentCanvas.lines.single.color.toARGB32(),
        attachmentStyle.color.toARGB32(),
      );
      expect(attachmentCanvas.lines.single.width, attachmentStyle.width);
    });

    test('an edge whose semantic id is not registered is not painted', () {
      final registered = _edge(src, dst, ConstellationEdgeKind.tier1Path);
      final other = _edge(src, dst, ConstellationEdgeKind.attachment);
      final painter = painterFor({
        registered.semanticId: ConstellationEdgeKind.tier1Path,
      });

      final canvas = _RecordingCanvas();
      painter.paint(canvas, other, Offset.zero, const Offset(200, 0));

      expect(canvas.lines, isEmpty);
    });

    test('an edge with a default semantic id keeps its endpoint-pair key', () {
      final edge = EdgeDetails(
        source: src,
        destination: dst,
        color: Colors.transparent,
      );
      final painter = painterFor({
        _pairKey(src, dst): ConstellationEdgeKind.tier1Path,
      });

      final canvas = _RecordingCanvas();
      painter.paint(canvas, edge, Offset.zero, const Offset(200, 0));

      expect(canvas.lines, hasLength(1));
    });
  });
}
