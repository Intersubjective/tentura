import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/utils/animated_highlighted_edge_painter.dart';
import 'package:tentura/features/graph/ui/utils/ease_in_out_reynolds.dart';

class _ReciprocalEdgeGoldenPainter extends CustomPainter {
  _ReciprocalEdgeGoldenPainter({
    required this.painter,
    required this.edge,
    required this.src,
    required this.dst,
  });

  final AnimatedHighlightedEdgePainter painter;
  final EdgeDetails<NodeDetails> edge;
  final Offset src;
  final Offset dst;

  @override
  void paint(Canvas canvas, Size size) {
    painter.paint(canvas, edge, src, dst);
  }

  @override
  bool shouldRepaint(covariant _ReciprocalEdgeGoldenPainter oldDelegate) =>
      false;
}

void main() {
  const logicalSize = Size(240, 120);

  testWidgets(
    'reciprocal trust renders one straight edge with bidirectional highlights',
    (tester) async {
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(seconds: 2),
      );
      addTearDown(controller.dispose);

      final painter = AnimatedHighlightedEdgePainter(
        animation: CurvedAnimation(
          parent: controller,
          curve: const EaseInOutReynolds(),
        ),
        highlightRadius: 0.15,
        isAnimated: true,
      );

      const srcNode = UserNode(
        user: Profile(id: 'a', displayName: 'A'),
        size: 24,
      );
      const dstNode = UserNode(
        user: Profile(id: 'b', displayName: 'B'),
        size: 24,
      );
      const edgeColor = Color(0xFF1565C0);
      const edge = EdgeDetails(
        source: srcNode,
        destination: dstNode,
        color: edgeColor,
        isReciprocal: true,
      );

      const src = Offset(40, 60);
      const dst = Offset(200, 60);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: TenturaTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(size: logicalSize),
            child: Scaffold(
              body: Align(
                alignment: Alignment.center,
                child: RepaintBoundary(
                  key: const Key('golden'),
                  child: SizedBox(
                    width: logicalSize.width,
                    height: logicalSize.height,
                    child: CustomPaint(
                      painter: _ReciprocalEdgeGoldenPainter(
                        painter: painter,
                        edge: edge,
                        src: src,
                        dst: dst,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      controller.value = 0.5;
      await tester.pump();

      await expectLater(
        find.byKey(const Key('golden')),
        matchesGoldenFile('goldens/reciprocal_edge_bidirectional.png'),
      );
    },
  );
}
