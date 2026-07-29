import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

void main() {
  final a = Node<String>(data: 'a', size: 10);
  final b = Node<String>(data: 'b', size: 10);

  GraphLayout build(Map<NodeBase, Offset> positions) {
    final builder = GraphLayoutBuilder(nodes: positions.keys.toSet());
    positions.forEach(builder.setNodePosition);
    return builder.build();
  }

  test('lerp moves shared nodes and keeps the target key set', () {
    final from = build({a: Offset.zero, b: const Offset(100, 0)});
    final to = build({a: const Offset(100, 100)});

    final mid = GraphLayout.lerp(from, to, 0.5);

    expect(mid.getPosition(a), const Offset(50, 50));
    expect(mid.hasPosition(b), isFalse);
  });

  test('a node missing from the source starts at the spawn position', () {
    final from = build({a: Offset.zero});
    final to = build({a: Offset.zero, b: const Offset(100, 0)});

    final mid = GraphLayout.lerp(from, to, 0.5, spawn: (_) => Offset.zero);

    expect(mid.getPosition(b), const Offset(50, 0));
  });
}
