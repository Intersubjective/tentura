import 'package:flutter_test/flutter_test.dart';

import 'fixtures/constellation_reference_fixture.dart';

void main() {
  testWidgets('reference fixture loads and graph nodes receive layout positions',
      (tester) async {
    final cubit = await loadReferenceCubit();
    await pumpConstellationBody(tester, cubit);

    // Bounded settle: force-directed layout may keep animating.
    var settled = false;
    try {
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      settled = true;
    } on Object {
      settled = false;
    }
    if (!settled) {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    expect(cubit.graphController.canLayout, isTrue);

    final topologyIds = cubit.graphController.renderSnapshot.topology.nodesById.keys;
    expect(topologyIds, isNotEmpty);

    for (final graphId in topologyIds) {
      final position = cubit.graphController.getPositionOrNullForId(graphId);
      expect(
        position,
        isNotNull,
        reason: 'missing layout position for graph node $graphId',
      );
    }

    // Sanity: scene includes ego person and at least one reference request.
    expect(
      topologyIds.any((id) => id.contains('ego') && !id.startsWith('req-')),
      isTrue,
    );
    expect(
      topologyIds.any((id) => id.contains('req-ego')),
      isTrue,
    );
  });
}
