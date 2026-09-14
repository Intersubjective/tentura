import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';

import 'fixtures/constellation_reference_fixture.dart';

void main() {
  group('label budget context (reference fixture)', () {
    test('default budget after load then phone budget updates overflow', () async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      expect(cubit.overflowHiddenCountByAuthor['ego'], 3);

      cubit.updateLabelBudgetContext(
        viewport: const Size(375, 547),
        textScaleFactor: 1.0,
      );
      expect(cubit.overflowHiddenCountByAuthor['ego'], 5);
      expect(cubit.overflowHiddenCountByAuthor['in'], 1);
    });

    test('repeated identical update does not reconcile layout again', () async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      cubit.updateLabelBudgetContext(
        viewport: const Size(375, 547),
        textScaleFactor: 1.0,
      );
      final reconciliations = cubit.layoutReconciliationCount;

      cubit.updateLabelBudgetContext(
        viewport: const Size(375, 547),
        textScaleFactor: 1.0,
      );
      expect(cubit.layoutReconciliationCount, reconciliations);
    });

    test('toggle satellite overflow twice keeps ego hidden count (UI-10)', () async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      cubit.updateLabelBudgetContext(
        viewport: const Size(375, 547),
        textScaleFactor: 1.0,
      );
      expect(cubit.overflowHiddenCountByAuthor['ego'], 5);

      cubit.toggleSatelliteOverflow('in');
      cubit.toggleSatelliteOverflow('in');
      expect(cubit.overflowHiddenCountByAuthor['ego'], 5);
    });

    test('budget update deferred during drag then applied on cancelPlacement', () async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      expect(cubit.overflowHiddenCountByAuthor['ego'], 3);

      cubit.beginDragExisting(
        target: ConstellationAnchorTarget.person('am'),
      );
      cubit.updateLabelBudgetContext(
        viewport: const Size(375, 547),
        textScaleFactor: 1.0,
      );
      expect(cubit.overflowHiddenCountByAuthor['ego'], 3);

      cubit.cancelPlacement();
      expect(cubit.overflowHiddenCountByAuthor['ego'], 5);
    });
  });
}
