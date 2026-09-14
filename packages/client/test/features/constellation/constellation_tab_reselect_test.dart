import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/screen/constellation_screen.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');

final class _CountingRepository implements ConstellationRepositoryPort {
  _CountingRepository(this.field);

  final ConstellationField field;
  int fetchCount = 0;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    fetchCount++;
    return field;
  }
}

class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit() : super(const GraphPersonContextState());

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {}

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  void clearSelection() {}
}

void main() {
  testWidgets(
    'reselecting the constellation tab reloads the field',
    (tester) async {
      final repository = _CountingRepository(
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
      );
      final cubit = ConstellationCubit(
        case_: ConstellationFieldCase(
          repository,
          env: const Env.fromEnvironment(),
          logger: Logger('ConstellationTabReselectTest'),
        ),
        viewer: _ego,
      );
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
      expect(repository.fetchCount, 1);

      final reselect = HomeTabReselectCubit();
      addTearDown(reselect.close);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ConstellationCubit>.value(value: cubit),
                BlocProvider<HomeTabReselectCubit>.value(value: reselect),
                BlocProvider<GraphPersonContextCubit>(
                  create: (_) => _StubContextCubit(),
                ),
                BlocProvider<ScreenCubit>(
                  create: (_) => ScreenCubit(FakeUiEffectPort()),
                ),
              ],
              child: const ConstellationScreen(),
            ),
          ),
        ),
      );
      await tester.pump();

      reselect.bump(HomeTab.constellation);
      await tester.pump();
      for (var i = 0; i < 20 && repository.fetchCount < 2; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(repository.fetchCount, 2);
    },
  );

  testWidgets(
    'reselect reload keeps overflow counts after phone label budget sync',
    (tester) async {
      final field = constellationReferenceField();
      final repository = _CountingRepository(field);
      final cubit = ConstellationCubit(
        case_: ConstellationFieldCase(
          repository,
          env: const Env.fromEnvironment(),
          logger: Logger('ConstellationTabReselectOverflowTest'),
        ),
        viewer: kRefEgo,
      );
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);

      final reselect = HomeTabReselectCubit();
      addTearDown(reselect.close);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(375, 547),
              textScaler: TextScaler.linear(1.0),
            ),
            child: TenturaResponsiveScope(
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<ConstellationCubit>.value(value: cubit),
                  BlocProvider<HomeTabReselectCubit>.value(value: reselect),
                  BlocProvider<GraphPersonContextCubit>(
                    create: (_) => _StubContextCubit(),
                  ),
                  BlocProvider<ScreenCubit>(
                    create: (_) => ScreenCubit(FakeUiEffectPort()),
                  ),
                ],
                child: const ConstellationScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final before = Map<String, int>.from(cubit.overflowHiddenCountByAuthor);
      expect(before, isNotEmpty);

      reselect.bump(HomeTab.constellation);
      await tester.pump();
      for (var i = 0; i < 40 && repository.fetchCount < 2; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(repository.fetchCount, 2);
      expect(cubit.overflowHiddenCountByAuthor, before);
    },
  );
}
