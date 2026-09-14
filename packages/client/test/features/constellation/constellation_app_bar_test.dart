import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
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
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async =>
      field;
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
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: textScaler),
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
      expect(find.byIcon(TenturaIcons.graph), findsOneWidget);
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

    testWidgets('text scale 1.3 at wide width keeps map/text labels', (
      tester,
    ) async {
      final cubit = await _loadCubit();
      await _pumpAppBar(
        tester,
        cubit: cubit,
        size: const Size(900, 800),
        textScaler: TextScaler.linear(1.3),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Map'), findsOneWidget);
      expect(find.text('Text'), findsOneWidget);
      await cubit.close();
    });

    testWidgets('375px width at text scale 1.0 and 1.3 has no layout exception', (
      tester,
    ) async {
      for (final locale in [const Locale('en'), const Locale('ru')]) {
        for (final scale in [1.0, 1.3]) {
          final cubit = await _loadCubit();
          await _pumpAppBar(
            tester,
            cubit: cubit,
            size: const Size(375, 800),
            textScaler: TextScaler.linear(scale),
            locale: locale,
          );
          expect(tester.takeException(), isNull);
          final toggle = tester.widget<SegmentedButton<ConstellationViewMode>>(
            find.byKey(const Key('constellation.app_bar.view_mode')),
          );
          for (final segment in toggle.segments) {
            expect(segment.tooltip, isNotNull);
          }
          await cubit.close();
        }
      }
    });

    testWidgets('text scale 2.0 has no overflow and segment tooltips remain', (
      tester,
    ) async {
      final cubit = await _loadCubit();
      await tester.binding.setSurfaceSize(const Size(375, 800));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(375, 800),
              textScaler: TextScaler.linear(2.0),
            ),
            child: TenturaResponsiveScope(
              child: BlocProvider.value(
                value: cubit,
                child: Builder(
                  builder: (context) => Scaffold(
                    appBar: TenturaTopBar.of(
                      context,
                      title: const SizedBox.shrink(),
                      row: ConstellationAppBarRow(
                        legendExpanded: false,
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
      expect(tester.takeException(), isNull);
      final toggle = tester.widget<SegmentedButton<ConstellationViewMode>>(
        find.byKey(const Key('constellation.app_bar.view_mode')),
      );
      expect(toggle.segments.length, 2);
      for (final segment in toggle.segments) {
        expect(segment.tooltip, isNotNull);
        expect(segment.tooltip!.isNotEmpty, isTrue);
      }
      await cubit.close();
    });
  });
}
