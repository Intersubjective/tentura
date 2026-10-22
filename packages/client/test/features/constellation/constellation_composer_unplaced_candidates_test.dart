// Forward candidates the viewer can address but who are not on the normal
// field have no graph position when the composer opens: the composing scene
// places them only afterwards (first at a seed point, then at ring slots). The
// circle is sized to the first people placed, so the composer opens with the
// three nearest selected, as for people already on the field (tentura-rcp1).

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura/features/constellation/domain/radius_recipient_selection.dart';

import '../../support/constellation_composer_screen_harness.dart';

const _candidates = ['b', 'c', 'd', 'e'];

/// The viewer alone on the field.
ConstellationField _emptyField() => ConstellationField(
  loadedAt: DateTime.utc(2026, 10, 9),
  context: '',
);

double _distance(LPoint a, LPoint b) =>
    (Offset(a.x, a.y) - Offset(b.x, b.y)).distance;

void main() {
  testWidgets(
    'candidates placed only after the composer opened are sized into the '
    'circle: the three nearest are selected',
    (tester) async {
      final repository = ComposerHarnessRepository(_emptyField);
      final cubit = await loadComposerHarnessCubit(
        repository,
        forward: ComposerHarnessForwardRepository(candidateIds: _candidates),
      );
      final composer = buildComposerHarnessComposer(
        peopleSnapshot: cubit.composerPeople,
        eligible: const {},
      );
      await pumpComposerHarnessScreen(tester, cubit: cubit, composer: composer);
      final controller = cubit.graphController;
      expect(
        controller.renderSnapshot.topology.nodesById.keys,
        isNot(contains('fp:b')),
        reason: 'the candidates are not on the normal field',
      );

      // Off the ego, so the candidates' ring slots are not equidistant.
      composer.start(
        BeaconKind.post,
        controller.viewportLocalToScene(
              controller.viewportSize!.center(Offset.zero),
            ) +
            const Offset(120, 40),
      );
      await tester.pumpAndSettle();

      expect(cubit.state.isComposing, isTrue);
      final selection = composer.selection;
      expect(selection.eligible, _candidates.toSet());
      expect(
        selection.positions.keys.toSet(),
        _candidates.toSet(),
        reason: 'the composing scene placed every candidate',
      );
      expect(selection.radius, greaterThan(kComposerMinRadius));
      expect(
        selection.radius,
        closeTo(
          RadiusRecipientSelection.startRadius(
            selection.center,
            selection.positions,
            selection.eligible,
          ),
          1e-9,
        ),
        reason: 'the circle covers the third-nearest placed candidate',
      );
      final nearest = selection.eligible.toList()
        ..sort(
          (x, y) => _distance(
            selection.positions[x]!,
            selection.center,
          ).compareTo(_distance(selection.positions[y]!, selection.center)),
        );
      expect(selection.selected, nearest.take(3).toSet());
    },
  );
}
