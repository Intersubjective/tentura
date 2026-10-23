// #682: choosing «Enough help» in the Request status sheet must still offer
// «Decline remaining offers» (D10, #268) when a help offer is waiting. The
// sheet closes before the status call returns, so the follow-up has to run
// on the page's context, not the sheet's.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/domain/beacon_status_menu.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_status_bottom_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'help_offer_author_seen_test_support.dart';

const _helper = Profile(id: 'Uhelper000001', displayName: 'Helper');

/// The status call waits for [gate], so the sheet is gone before it returns.
class _GatedStatusRepository extends CountingCoordinationRepository {
  _GatedStatusRepository({super.rows});

  final gate = Completer<void>();
  BeaconStatus status = BeaconStatus.open;

  @override
  Future<({BeaconStatus status, DateTime? updatedAt})> setBeaconStatus({
    required String beaconId,
    required int status,
  }) async {
    setBeaconStatusCalls.add((beaconId: beaconId, status: status));
    await gate.future;
    this.status = BeaconStatus.values.firstWhere(
      (s) => s.smallintValue == status,
    );
    return (status: this.status, updatedAt: DateTime.utc(2026));
  }
}

FakeHelpOfferCoordinationRow _acceptedHelperRow() {
  final r = offerRow(offerer: _helper);
  return (
    beaconId: r.beaconId,
    userId: r.userId,
    user: r.user,
    message: r.message,
    helpType: r.helpType,
    roleLabel: r.roleLabel,
    status: r.status,
    withdrawReason: r.withdrawReason,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
    editedAt: r.editedAt,
    responseType: r.responseType,
    responseUpdatedAt: r.responseUpdatedAt,
    responseAuthorUserId: r.responseAuthorUserId,
    roomAccess: r.roomAccess,
    admissionAction: r.admissionAction,
    lastDeclineReason: r.lastDeclineReason,
    lastRemoveReason: r.lastRemoveReason,
    // CommitmentStakeState.acknowledged: someone is committed, so the
    // «Enough help» row is enabled (#384).
    stakeState: 2,
    offerKind: r.offerKind,
    isDirectAuthorForward: r.isDirectAuthorForward,
    authorSeenAt: r.authorSeenAt,
  );
}

void main() {
  testWidgets(
    '«Enough help» from the status sheet offers «Decline remaining offers»',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final coordination = _GatedStatusRepository(
        rows: [_acceptedHelperRow(), pendingOfferRow()],
      );
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async =>
            authorSeenBeacon().copyWith(status: coordination.status);
      final cubit = (await tester.runAsync(() async {
        final cubit = BeaconViewCubit(
          id: kAuthorSeenBeaconId,
          myProfile: kAuthor,
          beaconViewCase: buildTestBeaconViewCase(
            beaconRepo: beaconRepo,
            coordinationRepo: coordination,
          ),
          effects: FakeUiEffectPort(),
        );
        await waitFor(
          () =>
              cubit.state.beaconContextLoaded &&
              cubit.state.helpOffers.length == 2,
        );
        return cubit;
      }))!;
      addTearDown(cubit.close);
      final l10n = lookupL10n(const Locale('en'));

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 1200)),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: Builder(
                  builder: (ctx) => TextButton(
                    onPressed: () => showBeaconViewUpdateStatusSheet(
                      ctx,
                      cubit.state,
                      cubit,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          TestIds.key(
            TestIds.beaconStatusRow(BeaconStatusMenuRowId.enoughHelp.name),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.beaconStatusSheetTitle),
        findsNothing,
        reason: 'the sheet closes before the status call returns',
      );
      expect(coordination.setBeaconStatusCalls, hasLength(1));

      await tester.runAsync(() async {
        coordination.gate.complete();
        await waitFor(
          () =>
              cubit.state.beacon.status == BeaconStatus.enoughHelp &&
              !cubit.state.isLoading,
        );
      });
      await tester.pumpAndSettle();

      expect(find.text(l10n.declineRemainingOffersTitle(1)), findsOneWidget);
    },
  );
}
