// SPDX-License-Identifier: AGPL-3.0-only
// Issue #611 (V8a): the Report form opens as an in-shell page. On regular and
// expanded windows Home's rail stays beside it; compact windows are unchanged.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/complaint/ui/bloc/complaint_cubit.dart';
import 'package:tentura/features/complaint/ui/screen/complaint_screen.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/home/ui/widget/home_rail_account_footer.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'recording_complaint_case.dart';

final _at = DateTime.utc(2026, 10, 19);

final _beacon = Beacon(
  id: 'B1',
  title: 'Fix my bike before Sunday',
  createdAt: _at,
  updatedAt: _at,
  author: const Profile(id: 'Ualice', displayName: 'Alice Moreau'),
);

final class _FakeAuthCubit extends Fake implements AuthCubit {
  @override
  AuthState get state => AuthState(
    updatedAt: DateTime(2026),
    currentAccountId: 'U1',
  );

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

final class _FakeSettingsCubit extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

AutoRoute? _findRoute(List<AutoRoute> routes, String name) {
  for (final route in routes) {
    if (route.page.name == name) return route;
    if (route.children case final children?) {
      final found = _findRoute(children, name);
      if (found != null) return found;
    }
  }
  return null;
}

void main() {
  Future<L10n> pumpComplaint(
    WidgetTester tester, {
    required double width,
    String id = 'B1',
    ComplaintType? fixedType,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final complaintCase = RecordingComplaintCase(beacon: _beacon);
    final cubit = ComplaintCubit(
      id: id,
      fixedType: fixedType,
      complaintCase: complaintCase.useCase,
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    final router = RootStackRouter.build(routes: []);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: BlocProvider<ComplaintCubit>.value(
            value: cubit,
            child: RouterScope(
              controller: router,
              stateHash: 0,
              inheritableObserversBuilder: () => const [],
              child: StackRouterScope(
                controller: router,
                stateHash: 0,
                child: ComplaintScreen(
                  id: id,
                  fixedType: fixedType?.name ?? '',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return lookupL10n(const Locale('en'));
  }

  testWidgets('at 1200px the Report form keeps the nav rail beside it', (
    tester,
  ) async {
    final l10n = await pumpComplaint(tester, width: 1200);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text(l10n.submitComplaint), findsWidgets);
    expect(tester.takeException(), isNull);
    // The form sits to the right of the rail, not under it.
    final rail = tester.getRect(find.byType(NavigationRail));
    final form = tester.getRect(find.byType(DropdownButton<ComplaintType>));
    expect(form.left, greaterThanOrEqualTo(rail.right));
  });

  testWidgets('at 760px (regular) the rail is shown too', (tester) async {
    await pumpComplaint(tester, width: 760);

    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets('an account deletion request highlights the account avatar', (
    tester,
  ) async {
    await pumpComplaint(
      tester,
      width: 1200,
      id: 'U1',
      fixedType: ComplaintType.accountDeletionRequest,
    );

    expect(
      tester
          .widget<HomeRailAccountFooter>(find.byType(HomeRailAccountFooter))
          .selected,
      isTrue,
    );
  });

  // A compact (phone) width the form already fits in the test font: at 400px
  // the category dropdown (not expanded) overflows with test glyphs, before
  // and after #611 — the compact tree is unchanged by HomeRailFrame.
  testWidgets('at a compact width the form is unchanged: no rail', (
    tester,
  ) async {
    final l10n = await pumpComplaint(tester, width: 560);

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text(l10n.submitComplaint), findsWidgets);
    expect(find.byType(DropdownButton<ComplaintType>), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('the complaint route is a page, not a fullscreen dialog', () {
    final router = RootRouter(
      Logger('Issue611ComplaintRouteTest'),
      _FakeAuthCubit(),
      _FakeSettingsCubit(),
      PostJoinNavigationCubit(),
    );
    addTearDown(router.dispose);

    final route = _findRoute(router.routes, ComplaintRoute.name);
    expect(route, isNotNull);
    expect(route!.fullscreenDialog, isFalse);
  });
}
