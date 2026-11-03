import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_camera_controls.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_visibility_bar.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/phone_surface.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _personId = 'am';

Finder get _personNode => find.byKey(TestIds.key(TestIds.graphNode(_personId)));

Future<ConstellationCubit> _pumpField(
  WidgetTester tester, {
  required Size size,
  Locale locale = const Locale('en'),
}) async {
  final cubit = await loadReferenceCubit();
  addTearDown(cubit.close);
  await pumpConstellationBody(tester, cubit, size: size, locale: locale);
  await tester.pumpAndSettle();
  return cubit;
}

FieldPersonNode? _selectedPersonNode(ConstellationCubit cubit) {
  for (final node
      in cubit.graphController.renderSnapshot.topology.nodesById.values) {
    final payload = node.payload;
    if (payload is FieldPersonNode && payload.person.id == _personId) {
      return payload;
    }
  }
  return null;
}

void main() {
  group('Field compact context sheet (#974)', () {
    testWidgets('375×667 hides map chrome and revealPanFor is non-null', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      final cubit = await _pumpField(tester, size: kPhoneSurface);
      await tester.tap(_personNode);
      await tester.pumpAndSettle();

      expect(find.byType(ConstellationVisibilityBar), findsNothing);
      expect(
        find.byKey(const Key('field.context_sheet.handle')),
        findsOneWidget,
      );
      expect(find.byType(GraphPersonContextPanel), findsOneWidget);

      final context = tester.element(find.byType(ConstellationBody));
      final tt = context.tt;
      final mapBodyHeight =
          kPhoneSurface.height - tt.appBarHeight - tt.bottomNavHeight;
      final peekSheet = mapBodyHeight * tt.fieldSheetPeekFraction;
      final node = _selectedPersonNode(cubit);
      expect(node, isNotNull);

      final pan = cubit.revealPanFor(
        node!,
        insets: ConstellationCameraControls.cameraViewportInsets(
          context,
          contextPanelVisible: true,
          compactSheetHeight: peekSheet,
        ),
        centreVertically: true,
      );
      expect(pan, isNotNull);
    });

    testWidgets('360×640 keeps request primary action visible at peek in RU', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpField(
        tester,
        size: const Size(360, 640),
        locale: const Locale('ru'),
      );
      final request = find.byKey(TestIds.key(TestIds.graphNode('req-in-2')));
      if (request.evaluate().isEmpty) {
        return;
      }
      await tester.tap(request);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('constellation.request_preview.primary')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
