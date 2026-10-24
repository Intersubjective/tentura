import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_app_bar.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/optional_gate_call.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');

final class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

Future<ConstellationCubit> _loadCubit() async {
  final cubit = ConstellationCubit(
    case_: ConstellationStoreFixture(
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
      accountId: 'ego',
    ).store,
    viewer: _ego,
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

class _RecordingRouter extends Fake implements StackRouter {
  final pushed = <PageRouteInfo>[];

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => false;

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    pushed.add(route);
    return null;
  }
}

Future<void> _pumpAppBar(
  WidgetTester tester, {
  required ConstellationCubit cubit,
  required StackRouter router,
  required bool gate,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: RouterScope(
        controller: router,
        stateHash: 0,
        inheritableObserversBuilder: () => const [],
        child: StackRouterScope(
          controller: router,
          stateHash: 0,
          child: TenturaResponsiveScope(
            child: BlocProvider.value(
              value: cubit,
              child: Builder(
                builder: (context) => Scaffold(
                  appBar: TenturaTopBar.of(
                    context,
                    title: const SizedBox.shrink(),
                    row:
                        callWithPeopleTagsGate(
                              ConstellationAppBarRow.new,
                              gate: gate,
                              named: {
                                #legendExpanded: false,
                                #onToggleLegend: () {},
                              },
                            )
                            as Widget,
                  ),
                  body: const SizedBox.expand(),
                ),
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
  testWidgets('the Field menu opens the People tags screen', (tester) async {
    final cubit = await _loadCubit();
    addTearDown(cubit.close);
    final router = _RecordingRouter();

    await _pumpAppBar(tester, cubit: cubit, router: router, gate: true);
    await tester.tap(find.byKey(const Key('constellation.app_bar.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('constellation.app_bar.people_tags')));
    await tester.pumpAndSettle();

    expect(router.pushed.map((r) => r.routeName), [PeopleTagsRoute.name]);
  });

  testWidgets('the Field menu has no People tags entry while the feature is off', (
    tester,
  ) async {
    final cubit = await _loadCubit();
    addTearDown(cubit.close);

    await _pumpAppBar(
      tester,
      cubit: cubit,
      router: _RecordingRouter(),
      gate: false,
    );

    expect(find.byKey(const Key('constellation.app_bar.people_tags')), findsNothing);
  });
}
