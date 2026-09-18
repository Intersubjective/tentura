import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/components/tentura_text_action.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_child_promotion_footer.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../features/beacon_create/fake_beacon_ports.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'viewer', displayName: 'Me'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _HarnessRouter extends Mock implements StackRouter {
  int pushCount = 0;
  PageRouteInfo? lastPush;

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    pushCount++;
    lastPush = route;
    return null;
  }
}

BeaconHierarchySummary _summary({
  required String id,
  required String title,
  bool tombstone = false,
}) => BeaconHierarchySummary(
  beaconId: id,
  title: tombstone ? null : title,
  owner: tombstone
      ? null
      : const BeaconHierarchyOwnerSummary(
          id: 'author-1',
          displayName: 'Alice',
        ),
  status: BeaconStatus.open,
  publishedAt: DateTime.utc(2026, 1, 1),
  isTombstone: tombstone,
);

({FakeBeaconHierarchyRepositoryPort port, BeaconHierarchyCase case_})
_registerHierarchy({
  Map<String, BeaconHierarchySummary?>? previews,
  Object? error,
}) {
  final port = FakeBeaconHierarchyRepositoryPort()
    ..childPreviewError = error;
  if (previews != null) {
    port.childPreviews.addAll(previews);
  }
  final case_ = buildBeaconHierarchyCaseForTest(
    port,
    createCase: BeaconCreateCase(FakeBeaconWritePort(), FakeBeaconImagePort()),
    beacons: FakeBeaconWritePort(),
    commandStore: InMemoryBeaconChildCommandStore(),
  );
  GetIt.I.registerSingleton<BeaconHierarchyCase>(case_);
  return (port: port, case_: case_);
}

Widget _harness(Widget child, {required StackRouter router}) =>
    StackRouterScope(
      controller: router,
      stateHash: 0,
      child: BlocProvider<ProfileCubit>.value(
        value: _MockProfileCubit(),
        child: MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(body: child),
        ),
      ),
    );

void main() {
  setUp(() async {
    await GetIt.I.reset();
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('accessible child shows title and navigates on tap', (
    tester,
  ) async {
    final registered = _registerHierarchy(
      previews: {
        'child-1': _summary(id: 'child-1', title: 'Fix the fence'),
      },
    );
    final router = _HarnessRouter();

    await tester.pumpWidget(
      _harness(
        const BeaconChildPromotionFooter(childBeaconId: 'child-1'),
        router: router,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fix the fence'), findsOneWidget);
    expect(find.byType(TenturaTextAction), findsOneWidget);
    expect(find.byType(BeaconCardShell), findsNothing);
    expect(registered.port.fetchChildPreviewCallCount, 1);

    await tester.tap(find.text('Fix the fence'));
    await tester.pump();

    expect(router.pushCount, 1);
    final push = router.lastPush;
    expect(push, isA<BeaconViewRoute>());
    expect((push! as BeaconViewRoute).args!.id, 'child-1');
  });

  testWidgets('inaccessible child renders a safe state with no leaked title', (
    tester,
  ) async {
    _registerHierarchy(error: Exception('not found'));
    final router = _HarnessRouter();

    await tester.pumpWidget(
      _harness(
        const BeaconChildPromotionFooter(childBeaconId: 'child-hidden'),
        router: router,
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.beaconChildFooterUnavailable), findsOneWidget);
    expect(find.byType(BeaconCardShell), findsNothing);
    expect(find.text('child-hidden'), findsNothing);

    await tester.tap(find.text(l10n.beaconChildFooterUnavailable));
    await tester.pump();
    expect(router.pushCount, 0);
  });

  testWidgets('deleted child (null row) renders the same safe state', (
    tester,
  ) async {
    _registerHierarchy(
      previews: {'child-deleted': null},
    );
    final router = _HarnessRouter();

    await tester.pumpWidget(
      _harness(
        const BeaconChildPromotionFooter(childBeaconId: 'child-deleted'),
        router: router,
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.beaconChildFooterUnavailable), findsOneWidget);
  });

  testWidgets('tombstone child renders unavailable without leaking title', (
    tester,
  ) async {
    _registerHierarchy(
      previews: {
        'child-tomb': _summary(
          id: 'child-tomb',
          title: 'Secret',
          tombstone: true,
        ),
      },
    );
    final router = _HarnessRouter();

    await tester.pumpWidget(
      _harness(
        const BeaconChildPromotionFooter(childBeaconId: 'child-tomb'),
        router: router,
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.beaconChildFooterUnavailable), findsOneWidget);
    expect(find.text('Secret'), findsNothing);
  });

  testWidgets('rendering the footer only calls fetchChildPreview', (
    tester,
  ) async {
    final registered = _registerHierarchy(
      previews: {
        'child-1': _summary(id: 'child-1', title: 'X'),
      },
    );

    await tester.pumpWidget(
      _harness(
        const BeaconChildPromotionFooter(childBeaconId: 'child-1'),
        router: _HarnessRouter(),
      ),
    );
    await tester.pumpAndSettle();

    expect(registered.port.fetchChildPreviewCallCount, 1);
  });

  testWidgets('re-fetches when childBeaconId changes rather than caching', (
    tester,
  ) async {
    final registered = _registerHierarchy(
      previews: {
        'child-1': _summary(id: 'child-1', title: 'First'),
        'child-2': _summary(id: 'child-2', title: 'Second'),
      },
    );

    await tester.pumpWidget(
      _harness(
        const BeaconChildPromotionFooter(childBeaconId: 'child-1'),
        router: _HarnessRouter(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);

    await tester.pumpWidget(
      _harness(
        const BeaconChildPromotionFooter(childBeaconId: 'child-2'),
        router: _HarnessRouter(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);
    expect(registered.port.fetchChildPreviewCallCount, 2);
  });
}
