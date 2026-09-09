import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_app_bar.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');

final class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch() async => field;
}

Future<ConstellationCubit> _loadCubit() async {
  final cubit = ConstellationCubit(
    case_: ConstellationFieldCase(
      _StubRepository(
        ConstellationField(
          loadedAt: DateTime.utc(2026, 9, 9),
          context: '',
          peers: const [ConstellationPerson(id: 'a', displayName: 'Ann')],
          edges: const [
            ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
          requests: const [
            ConstellationRequest(
              id: 'req-a',
              authorId: 'a',
              title: 'Need tools',
              status: 0,
              needs: ['tools'],
            ),
          ],
        ),
      ),
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationAppBarTest'),
    ),
    viewer: _ego,
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

Future<void> _pumpAppBar(
  WidgetTester tester, {
  required ConstellationCubit cubit,
  required Size size,
  bool legendExpanded = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: BlocProvider.value(
            value: cubit,
            child: Builder(
              builder: (context) => Scaffold(
                appBar: TenturaTopBar.of(
                  context,
                  title: const SizedBox.shrink(),
                  row: ConstellationAppBarRow(
                    legendExpanded: legendExpanded,
                    onToggleLegend: () {},
                  ),
                ),
                body: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ConstellationAppBarRow', () {
    testWidgets('filters button opens sheet with filter bar', (tester) async {
      final cubit = await _loadCubit();
      await _pumpAppBar(tester, cubit: cubit, size: const Size(400, 800));

      await tester.tap(find.byKey(const Key('constellation.app_bar.filters')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('constellation.filter_bar')), findsOneWidget);
      await cubit.close();
    });

    testWidgets('legend stays slotted so view-mode toggle does not shift', (
      tester,
    ) async {
      final cubit = await _loadCubit();
      await _pumpAppBar(tester, cubit: cubit, size: const Size(400, 800));

      final legend = find.byKey(const Key('constellation.app_bar.legend'));
      final toggle = find.byKey(const Key('constellation.app_bar.view_mode'));
      expect(legend, findsOneWidget);
      expect(
        tester
            .widget<Visibility>(
              find.ancestor(of: legend, matching: find.byType(Visibility)),
            )
            .visible,
        isTrue,
      );
      final mapToggleOrigin = tester.getTopLeft(toggle);

      cubit.setViewMode(ConstellationViewMode.text);
      await tester.pumpAndSettle();
      expect(legend, findsOneWidget);
      expect(
        tester
            .widget<Visibility>(
              find.ancestor(of: legend, matching: find.byType(Visibility)),
            )
            .visible,
        isFalse,
      );
      expect(tester.getTopLeft(toggle), mapToggleOrigin);

      cubit.setViewMode(ConstellationViewMode.map);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Visibility>(
              find.ancestor(of: legend, matching: find.byType(Visibility)),
            )
            .visible,
        isTrue,
      );
      expect(tester.getTopLeft(toggle), mapToggleOrigin);
      await cubit.close();
    });

    testWidgets('narrow width drops map/text labels but keeps icons', (
      tester,
    ) async {
      final cubit = await _loadCubit();
      await _pumpAppBar(tester, cubit: cubit, size: const Size(280, 800));

      expect(find.text('Map'), findsNothing);
      expect(find.text('Text'), findsNothing);
      expect(find.byIcon(Icons.map_outlined), findsWidgets);
      expect(find.byIcon(Icons.view_list_outlined), findsOneWidget);
      await cubit.close();
    });

    testWidgets('wide width keeps map/text labels', (tester) async {
      final cubit = await _loadCubit();
      await _pumpAppBar(tester, cubit: cubit, size: const Size(900, 800));

      expect(find.text('Map'), findsOneWidget);
      expect(find.text('Text'), findsOneWidget);
      await cubit.close();
    });
  });
}
