import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/domain/beacon_status_menu.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/presenter/beacon_hud_author_action.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_author_confirm_sheets.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_app_bar_overflow.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_status_bottom_sheet.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/ui/l10n/l10n.dart';

final _l10n = lookupL10n(const Locale('en'));

BeaconViewState _state({BeaconStatus status = BeaconStatus.reviewOpen}) =>
    BeaconViewState(
  beacon: Beacon(
    id: 'b1',
    title: 'T',
    author: const Profile(id: 'uAuthor', displayName: 'Author'),
    createdAt: DateTime.utc(2026, 6, 20),
    updatedAt: DateTime.utc(2026, 6, 20),
    status: status,
  ),
  myProfile: const Profile(id: 'uAuthor', displayName: 'Author'),
  closureState: ClosureState(
    epoch: 1,
    status: BeaconStatus.reviewOpen.smallintValue,
    role: ClosureRole.author,
    members: const [],
    closesAt: DateTime.utc(2026, 6, 27),
    canCloseNow: true,
    canReopen: true,
  ),
  beaconContextLoaded: true,
);

class _MockBeaconViewCubit extends Mock implements BeaconViewCubit {
  _MockBeaconViewCubit(this._state);

  final BeaconViewState _state;
  int closeCalls = 0;
  int reopenCalls = 0;

  @override
  BeaconViewState get state => _state;

  @override
  Stream<BeaconViewState> get stream => Stream<BeaconViewState>.value(_state);

  @override
  Future<void> closeBeaconNow() async => closeCalls++;

  @override
  Future<void> reopenBeacon() async => reopenCalls++;
}

Future<BuildContext> _pumpHost(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    ),
  );
  return captured;
}

void main() {
  group('shared close confirm', () {
    testWidgets('close now asks for confirmation before it resolves', (
      tester,
    ) async {
      final context = await _pumpHost(tester);
      final cancelled = showBeaconCloseNowConfirmSheet(context: context);
      await tester.pumpAndSettle();
      expect(find.text(_l10n.beaconReviewCloseNowBody), findsOneWidget);
      await tester.tap(find.text(_l10n.buttonCancel));
      await tester.pumpAndSettle();
      expect(await cancelled, isFalse);

      final confirmed = showBeaconCloseNowConfirmSheet(context: context);
      await tester.pumpAndSettle();
      await tester.tap(find.text(_l10n.beaconHudConfirmCloseNowAction));
      await tester.pumpAndSettle();
      expect(await confirmed, isTrue);
    });
  });

  group('shared reopen confirm', () {
    testWidgets('the reopen confirm uses the short body', (tester) async {
      final context = await _pumpHost(tester);
      final result = showBeaconReopenConfirmSheet(context: context);
      await tester.pumpAndSettle();
      expect(find.text(_l10n.beaconReviewReopenBodyNoSent), findsOneWidget);
      await tester.tap(find.text(_l10n.buttonCancel));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });

    testWidgets('confirming returns true', (tester) async {
      final context = await _pumpHost(tester);
      final result = showBeaconReopenConfirmSheet(context: context);
      await tester.pumpAndSettle();
      await tester.tap(find.text(_l10n.beaconReviewReopenConfirm));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });
  });

  group('entry points confirm before mutating', () {
    testWidgets('HUD close shows the close confirm', (
      tester,
    ) async {
      final context = await _pumpHost(tester);
      final cubit = _MockBeaconViewCubit(_state());
      final done = beaconViewHandleAuthorHudAction(
        context: context,
        cubit: cubit,
        l10n: _l10n,
        action: BeaconHudAuthorAction.closeNow,
        onOpenPeopleTab: () {},
        onActivatePeopleAttention: () {},
        onFocusCoordinationItem: (_) {},
        onOpenItemsTab: () {},
        onOpenGeneralThread: () {},
      );
      await tester.pumpAndSettle();
      expect(find.text(_l10n.beaconReviewCloseNowBody), findsOneWidget);
      expect(cubit.closeCalls, 0);
      await tester.tap(find.text(_l10n.beaconHudConfirmCloseNowAction));
      await tester.pumpAndSettle();
      await done;
      expect(cubit.closeCalls, 1);
    });

    testWidgets('status sheet close shows the close confirm', (tester) async {
      final context = await _pumpHost(tester);
      final state = _state();
      final cubit = _MockBeaconViewCubit(state);
      final done = beaconViewDispatchStatusMenuAction(
        context,
        action: BeaconStatusMenuAction.closeNow,
        state: state,
        cubit: cubit,
        l10n: _l10n,
      );
      await tester.pumpAndSettle();
      expect(find.text(_l10n.beaconReviewCloseNowBody), findsOneWidget);
      expect(cubit.closeCalls, 0);
      await tester.tap(find.text(_l10n.buttonCancel));
      await tester.pumpAndSettle();
      await done;
      expect(cubit.closeCalls, 0);
    });

    testWidgets('status sheet reopen confirms before reopening', (
      tester,
    ) async {
      final context = await _pumpHost(tester);
      final state = _state(status: BeaconStatus.closed);
      final cubit = _MockBeaconViewCubit(state);
      final done = beaconViewDispatchStatusMenuAction(
        context,
        action: BeaconStatusMenuAction.reopen,
        state: state,
        cubit: cubit,
        l10n: _l10n,
      );
      await tester.pumpAndSettle();
      expect(find.text(_l10n.beaconReviewReopenBodyNoSent), findsOneWidget);
      expect(cubit.reopenCalls, 0);
      await tester.tap(find.text(_l10n.beaconReviewReopenConfirm));
      await tester.pumpAndSettle();
      await done;
      expect(cubit.reopenCalls, 1);
    });
  });
}
