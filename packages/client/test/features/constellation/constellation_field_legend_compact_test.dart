// #1042: compact Field legend height cap; map stays interactive (375×667 RU).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_legend_panel.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_field_test_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

Future<void> _pumpCompactFieldLegend(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required bool legendExpanded,
  TextScaler textScaler = const TextScaler.linear(1.34),
}) async {
  await usePhoneSurface(tester);
  final fx = FakeUiEffectPort();
  await tester.pumpPeopleTagsWidget(
    MaterialApp(
      locale: const Locale('ru'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(
            size: kPhoneSurface,
            textScaler: textScaler,
          ),
          child: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ConstellationCubit>.value(value: cubit),
                BlocProvider(
                  create: (_) => constellationSelectionForFieldBodyTests(),
                ),
                BlocProvider<GraphPersonContextCubit>(
                  create: (_) => FieldBodyTestGraphPersonContextCubit(),
                ),
                BlocProvider<ScreenCubit>(create: (_) => ScreenCubit(fx)),
              ],
              child: Material(
                child: ConstellationBody(
                  legendExpanded: legendExpanded,
                  onToggleLegend: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets(
    '375×667 RU long text: expanded legend ≤ compact cap; graph stays hit-testable',
    (tester) async {
      final cubit = await loadReferenceCubit();
      await _pumpCompactFieldLegend(tester, cubit, legendExpanded: true);

      final bodyContext = tester.element(find.byType(ConstellationBody));
      final tt = bodyContext.tt;
      final media = MediaQuery.sizeOf(bodyContext);
      final cap = media.height * tt.graphLegendMaxHeightFractionCompact;

      final legendFinder = find.byType(GraphLegendPanel);
      expect(legendFinder, findsOneWidget);
      expect(tester.getSize(legendFinder).height, lessThanOrEqualTo(cap + 1));

      final l10n = L10n.of(bodyContext)!;
      expect(find.text(l10n.graphLegendEdgesTitle), findsWidgets);

      final graphFinder = find.byType(GraphView<NodeDetails, EdgeDetails>);
      expect(graphFinder, findsOneWidget);
      final graphRect = tester.getRect(graphFinder);
      // Legend sits bottom-start on phones; use upper map band, clear of the card.
      final probeGlobal = Offset(
        graphRect.left + graphRect.width / 2,
        graphRect.top + graphRect.height * 0.2,
      );
      final legendRect = tester.getRect(legendFinder);
      expect(
        legendRect.contains(probeGlobal),
        isFalse,
        reason: 'Probe on the map must sit outside the legend card',
      );

      final graphBox = tester.renderObject(graphFinder) as RenderBox;
      final local = graphBox.globalToLocal(probeGlobal);
      final hit = BoxHitTestResult();
      expect(
        graphBox.hitTest(hit, position: local),
        isTrue,
        reason: 'Map GraphView should stay pointer-reachable with legend open',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
