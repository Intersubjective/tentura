import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';

void main() {
  testWidgets('genealogy user nodes pass rating chrome to TenturaAvatar', (
    tester,
  ) async {
    const profile = Profile(
      id: 'Uviewer',
      displayName: 'Viewer',
      score: 3,
      rScore: 3,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: const GraphNodeWidget(
          nodeDetails: GenealogyUserNode(nodeKey: 'Gviewer', user: profile),
          withRating: true,
        ),
      ),
    );

    final avatar = tester.widget<TenturaAvatar>(find.byType(TenturaAvatar));
    expect(avatar.profile.id, profile.id);
    expect(avatar.withRating, isTrue);
  });
}
