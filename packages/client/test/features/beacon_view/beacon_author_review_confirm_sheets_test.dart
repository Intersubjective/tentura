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
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';

final _l10n = lookupL10n(const Locale('en'));

BeaconViewState _state({
  BeaconStatus status = BeaconStatus.reviewOpen,
  int sentReviewerCount = 0,
  int unsentStartedPackages = 0,
}) => BeaconViewState(
  beacon: Beacon(
    id: 'b1',
    title: 'T',
    author: const Profile(id: 'uAuthor', displayName: 'Author'),
    createdAt: DateTime.utc(2026, 6, 20),
    updatedAt: DateTime.utc(2026, 6, 20),
    status: status,
  ),
  myProfile: const Profile(id: 'uAuthor', displayName: 'Author'),
  reviewWindowInfo: ReviewWindowInfo(
    beaconId: 'b1',
    hasWindow: true,
    userReviewStatus: 2,
    totalCount: 2,
    canCloseNow: true,
    canReopen: true,
    sentReviewerCount: sentReviewerCount,
    unsentStartedPackages: unsentStartedPackages,
  ),
  beaconContextLoaded: true,
  status: const StateIsSuccess(),
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
    testWidgets(
      'the discard note appears only when a package was started and not sent',
      (tester) async {
        final context = await _pumpHost(tester);
        final withNote = showBeaconCloseNowConfirmSheet(
          context: context,
          unsentStartedPackages: 2,
        );
        await tester.pumpAndSettle();
        expect(find.text(_l10n.beaconReviewCloseNowBody), findsOneWidget);
        expect(
          find.text(_l10n.beaconReviewCloseNowDiscardNote(2)),
          findsOneWidget,
        );
        await tester.tap(find.text(_l10n.buttonCancel));
        await tester.pumpAndSettle();
        expect(await withNote, isFalse);

        final withoutNote = showBeaconCloseNowConfirmSheet(
          context: context,
          unsentStartedPackages: 0,
        );
        await tester.pumpAndSettle();
        expect(find.text(_l10n.beaconReviewCloseNowBody), findsOneWidget);
        expect(
          find.textContaining('did not send it'),
          findsNothing,
        );
        await tester.tap(find.text(_l10n.beaconHudConfirmCloseNowAction));
        await tester.pumpAndSettle();
        expect(await withoutNote, isTrue);
      },
    );
  });

  group('shared reopen confirm', () {
    testWidgets('the reopen confirm names the number of people who already '
        'sent', (tester) async {
      final context = await _pumpHost(tester);
      final result = showBeaconReopenConfirmSheet(
        context: context,
        sentReviewerCount: 3,
      );
      await tester.pumpAndSettle();
      expect(find.text(_l10n.beaconReviewReopenBody(3)), findsOneWidget);
      expect(find.text(_l10n.beaconReviewReopenBodyNoSent), findsNothing);
      await tester.tap(find.text(_l10n.beaconReviewReopenConfirm));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });

    testWidgets('the reopen confirm without senders uses the short body', (
      tester,
    ) async {
      final context = await _pumpHost(tester);
      final result = showBeaconReopenConfirmSheet(
        context: context,
        sentReviewerCount: 0,
      );
      await tester.pumpAndSettle();
      expect(find.text(_l10n.beaconReviewReopenBodyNoSent), findsOneWidget);
      await tester.tap(find.text(_l10n.buttonCancel));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });
  });

  group('entry points confirm before mutating', () {
    testWidgets('HUD close shows the close confirm with the discard note', (
      tester,
    ) async {
      final context = await _pumpHost(tester);
      final cubit = _MockBeaconViewCubit(_state(unsentStartedPackages: 1));
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
      expect(
        find.text(_l10n.beaconReviewCloseNowDiscardNote(1)),
        findsOneWidget,
      );
      expect(cubit.closeCalls, 0);
      await tester.tap(find.text(_l10n.beaconHudConfirmCloseNowAction));
      await tester.pumpAndSettle();
      await done;
      expect(cubit.closeCalls, 1);
    });

    testWidgets('status sheet close shows the close confirm', (tester) async {
      final context = await _pumpHost(tester);
      final state = _state(unsentStartedPackages: 2);
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
      expect(
        find.text(_l10n.beaconReviewCloseNowDiscardNote(2)),
        findsOneWidget,
      );
      expect(cubit.closeCalls, 0);
      await tester.tap(find.text(_l10n.buttonCancel));
      await tester.pumpAndSettle();
      await done;
      expect(cubit.closeCalls, 0);
    });

    testWidgets('status sheet reopen names senders before reopening', (
      tester,
    ) async {
      final context = await _pumpHost(tester);
      final state = _state(status: BeaconStatus.closed, sentReviewerCount: 4);
      final cubit = _MockBeaconViewCubit(state);
      final done = beaconViewDispatchStatusMenuAction(
        context,
        action: BeaconStatusMenuAction.reopen,
        state: state,
        cubit: cubit,
        l10n: _l10n,
      );
      await tester.pumpAndSettle();
      expect(find.text(_l10n.beaconReviewReopenBody(4)), findsOneWidget);
      expect(cubit.reopenCalls, 0);
      await tester.tap(find.text(_l10n.beaconReviewReopenConfirm));
      await tester.pumpAndSettle();
      await done;
      expect(cubit.reopenCalls, 1);
    });
  });
}
