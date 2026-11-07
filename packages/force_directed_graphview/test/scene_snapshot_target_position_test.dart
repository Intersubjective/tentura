import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/scene/graph_layout_ticket.dart'
    show mintGraphLayoutTicket;

GraphTopology<String, String> _topology({required List<String> ids}) {
  return GraphTopology.fromEntries(
    nodes: [
      for (final id in ids)
        GraphSceneNode(
          id: id,
          payload: id,
          size: SceneSize(width: 40, height: 40),
        ),
    ],
    edges: const [],
  );
}

void main() {
  final owner = Object();

  test('resolveTargetPosition skips transition tween', () {
    final layoutPoint = ScenePoint(x: 10, y: 20);
    final transitionPoint = ScenePoint(x: 50, y: 60);
    final snapshot = GraphSceneSnapshot<String, String>(
      topology: _topology(ids: ['a']),
      layout: SceneLayout(
        ticket: mintGraphLayoutTicket(
          owner: owner,
          generation: 1,
          topologyRevision: 1,
        ),
        revision: 1,
        positions: {'a': layoutPoint},
      ),
      transition: SceneTransition(positions: {'a': transitionPoint}),
    );
    expect(snapshot.resolvePosition('a'), transitionPoint);
    expect(snapshot.resolveTargetPosition('a'), layoutPoint);
  });

  test('resolveTargetPosition prefers presentation override', () {
    final layoutPoint = ScenePoint(x: 10, y: 20);
    final override = ScenePoint(x: 99, y: 88);
    final snapshot = GraphSceneSnapshot<String, String>(
      topology: _topology(ids: ['a']),
      layout: SceneLayout(
        ticket: mintGraphLayoutTicket(
          owner: owner,
          generation: 1,
          topologyRevision: 1,
        ),
        revision: 1,
        positions: {'a': layoutPoint},
      ),
      presentation: ScenePresentation(overrides: {'a': override}),
    );
    expect(snapshot.resolveTargetPosition('a'), override);
  });
}
