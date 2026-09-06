import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_child_promotion_footer.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _FakeBeaconWritePort extends Mock implements BeaconWritePort {
  Beacon? beaconToReturn;
  Object? errorToThrow;
  var fetchCallCount = 0;

  @override
  Future<Beacon> fetchBeaconById(String id) async {
    fetchCallCount++;
    if (errorToThrow != null) throw errorToThrow!;
    return beaconToReturn!;
  }
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

Widget _harness(Widget child, {required StackRouter router}) =>
    StackRouterScope(
      controller: router,
      stateHash: 0,
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: child),
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
    final port = _FakeBeaconWritePort()
      ..beaconToReturn = Beacon.empty.copyWith(
        id: 'child-1',
        title: 'Fix the fence',
      );
    GetIt.I.registerSingleton<BeaconWritePort>(port);
    final router = _HarnessRouter();

    await tester.pumpWidget(
      _harness(
        const BeaconChildPromotionFooter(childBeaconId: 'child-1'),
        router: router,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fix the fence'), findsOneWidget);
    expect(port.fetchCallCount, 1);

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
    final port = _FakeBeaconWritePort()..errorToThrow = Exception('not found');
    GetIt.I.registerSingleton<BeaconWritePort>(port);
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
    expect(find.text('child-hidden'), findsNothing);

    await tester.tap(find.text(l10n.beaconChildFooterUnavailable));
    await tester.pump();
    expect(router.pushCount, 0);
  });

  testWidgets('deleted child (null row) renders the same safe state', (
    tester,
  ) async {
    final port = _FakeBeaconWritePort()..errorToThrow = Exception('deleted');
    GetIt.I.registerSingleton<BeaconWritePort>(port);
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

  testWidgets('rendering the footer never calls anything beyond fetchBeaconById', (
    tester,
  ) async {
    // BeaconWritePort has no seen/watermark surface at all — resolving the
    // child via fetchBeaconById alone is structurally incapable of marking
    // it seen. Assert the footer calls exactly that one method once.
    final port = _FakeBeaconWritePort()
      ..beaconToReturn = Beacon.empty.copyWith(id: 'child-1', title: 'X');
    GetIt.I.registerSingleton<BeaconWritePort>(port);

    await tester.pumpWidget(
      _harness(
        const BeaconChildPromotionFooter(childBeaconId: 'child-1'),
        router: _HarnessRouter(),
      ),
    );
    await tester.pumpAndSettle();

    expect(port.fetchCallCount, 1);
  });

  testWidgets('re-fetches when childBeaconId changes rather than caching', (
    tester,
  ) async {
    final port = _FakeBeaconWritePort()
      ..beaconToReturn = Beacon.empty.copyWith(id: 'child-1', title: 'First');
    GetIt.I.registerSingleton<BeaconWritePort>(port);

    await tester.pumpWidget(
      _harness(
        const BeaconChildPromotionFooter(childBeaconId: 'child-1'),
        router: _HarnessRouter(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);

    port.beaconToReturn = Beacon.empty.copyWith(id: 'child-2', title: 'Second');
    await tester.pumpWidget(
      _harness(
        const BeaconChildPromotionFooter(childBeaconId: 'child-2'),
        router: _HarnessRouter(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);
    expect(port.fetchCallCount, 2);
  });
}
