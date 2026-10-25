// "Open tag view" on the tag lens panel is offered only while both the
// people-tags and the Field-arrange feature flags are on.

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';

import '../../support/constellation_tag_lens_body_harness.dart';

Future<void> _selectNeighbour(
  WidgetTester tester, {
  required bool peopleTags,
  required bool arrange,
}) async {
  final m = await mountTagLensBody(
    tester,
    bodyBuilder: () => ConstellationBody(
      legendExpanded: false,
      onToggleLegend: () {},
      arrangeV2Enabled: arrange,
      peopleTagsEnabled: peopleTags,
    ),
  );
  m.lens.toggleOwn(tagLensNeighbour.id);
  await settleTagLensBody(tester);
  expect(find.text('Forward a request…'), findsOneWidget, reason: 'control');
}

void main() {
  group('"Open tag view" entry', () {
    testWidgets('is offered with people tags and Field arrange on', (
      tester,
    ) async {
      await _selectNeighbour(tester, peopleTags: true, arrange: true);

      expect(find.text('Open tag view'), findsOneWidget);
    });

    testWidgets('is hidden with Field arrange off', (tester) async {
      await _selectNeighbour(tester, peopleTags: true, arrange: false);

      expect(find.text('Open tag view'), findsNothing);
    });

    testWidgets('is hidden with people tags off', (tester) async {
      await _selectNeighbour(tester, peopleTags: false, arrange: true);

      expect(find.text('Open tag view'), findsNothing);
    });

    testWidgets('follows the real feature flags when none is passed', (
      tester,
    ) async {
      final m = await mountTagLensBody(
        tester,
        bodyBuilder: () =>
            ConstellationBody(legendExpanded: false, onToggleLegend: () {}),
      );
      m.lens.toggleOwn(tagLensNeighbour.id);
      await settleTagLensBody(tester);

      expect(
        find.text('Open tag view'),
        kPeopleTagsEnabled && kFieldArrangeV2Enabled
            ? findsOneWidget
            : findsNothing,
      );
    });

    testWidgets('opens the tag view of the selected tags', (tester) async {
      final m = await mountTagLensBody(
        tester,
        bodyBuilder: () => ConstellationBody(
          legendExpanded: false,
          onToggleLegend: () {},
          arrangeV2Enabled: true,
          peopleTagsEnabled: true,
        ),
      );
      m.lens.toggleOwn(tagLensNeighbour.id);
      await settleTagLensBody(tester);

      await tester.tap(find.text('Open tag view'));
      await settleTagLensBody(tester);

      expect(m.field.state.tagView?.scope.memberIds, {'ann', 'bob'});
    });
  });
}
