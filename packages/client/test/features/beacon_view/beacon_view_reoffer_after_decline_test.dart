// #744: after the author declines an offer, offering again must replace the
// "Your offer was declined" notice at once, even when the refetch that
// follows the write still returns the withdrawn row.

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

void main() {
  const me = Profile(id: 'Ueve', displayName: 'Eve');
  const beaconId = 'Breoffer1';

  Beacon beacon({BeaconStatus status = BeaconStatus.open}) => Beacon(
    id: beaconId,
    title: 'QA standby',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    status: status,
    author: const Profile(id: 'Ualice', displayName: 'Alice'),
  );

  final declined = _row(
    beaconId: beaconId,
    user: me,
    message: 'I can take Saturday',
    status: 1,
    admissionAction: HelpOfferAdmissionAction.decline.smallintValue,
    lastDeclineReason: 'We are full',
  );
  final fresh = _row(
    beaconId: beaconId,
    user: me,
    message: 'From the server',
    status: 0,
  );

  group('re-offer after a decline', () {
    test(
      'clears the decline notice at once when the refetch is still the '
      'withdrawn offer',
      () async {
        final offers = _ScriptedOffers(() => [declined]);
        final cubit = _cubit(
          beaconId: beaconId,
          me: me,
          beacon: beacon(),
          offers: offers,
        );
        addTearDown(cubit.close);
        await pumpUntil(
          cubit.stream,
          () => cubit.state.myDeclinedHelpOffer != null,
        );

        await cubit.offerHelp(message: 'I can help again');

        expect(cubit.state.myDeclinedHelpOffer, isNull);
        expect(cubit.state.myActiveHelpOffer, isNotNull);
        expect(cubit.state.myActiveHelpOffer!.isWithdrawn, isFalse);
        expect(cubit.state.myActiveHelpOffer!.admissionAction, isNull);
        expect(cubit.state.isHelpOffered, isTrue);

        // The server's row wins once the read is no longer the pre-offer slice.
        offers.next = () => [fresh];
        await cubit.refreshAfterClosureReview();
        expect(cubit.state.myDeclinedHelpOffer, isNull);
        expect(cubit.state.myActiveHelpOffer?.message, 'From the server');
      },
    );

    test(
      'an Enough help re-offer is a backup, not the declined notice',
      () async {
        final offers = _ScriptedOffers(() => [declined]);
        final cubit = _cubit(
          beaconId: beaconId,
          me: me,
          beacon: beacon(status: BeaconStatus.enoughHelp),
          offers: offers,
        );
        addTearDown(cubit.close);
        await pumpUntil(
          cubit.stream,
          () => cubit.state.myDeclinedHelpOffer != null,
        );

        await cubit.offerHelp(message: 'I can step in');

        expect(cubit.state.myDeclinedHelpOffer, isNull);
        expect(cubit.state.myActiveHelpOffer, isNotNull);
        expect(cubit.state.myActiveHelpOffer!.isBackup, isTrue);
      },
    );
  });
}

BeaconViewCubit _cubit({
  required String beaconId,
  required Profile me,
  required Beacon beacon,
  required _ScriptedOffers offers,
}) {
  final beaconRepo = TrackingBeaconRepository()
    ..fetchByIdHandler = (_) async => beacon;
  return BeaconViewCubit(
    id: beaconId,
    myProfile: me,
    beaconViewCase: buildTestBeaconViewCase(
      forward: _QuietOfferForward(),
      beaconRepo: beaconRepo,
      coordinationRepo: offers,
    ),
    effects: FakeUiEffectPort(),
  );
}

class _QuietOfferForward extends FakeBeaconViewForwardRepository {
  @override
  Future<bool> offerHelp({
    required String beaconId,
    String? message,
    List<String>? helpTypes,
    int? expectedOfferKind,
    bool notifyHelpOfferListeners = true,
  }) async => true;
}

class _ScriptedOffers extends FakeBeaconViewCoordinationRepository {
  _ScriptedOffers(this.next);

  List<FakeHelpOfferCoordinationRow> Function() next;

  @override
  Future<List<FakeHelpOfferCoordinationRow>> fetchHelpOffersWithCoordination({
    required String beaconId,
  }) async => next();
}

FakeHelpOfferCoordinationRow _row({
  required String beaconId,
  required Profile user,
  required String message,
  required int status,
  int offerKind = 0,
  int? admissionAction,
  String? lastDeclineReason,
}) {
  final at = DateTime.utc(2026, 3);
  return (
    beaconId: beaconId,
    userId: user.id,
    user: user,
    message: message,
    helpType: null,
    roleLabel: null,
    status: status,
    withdrawReason: null,
    createdAt: at,
    updatedAt: at,
    editedAt: null,
    responseType: null,
    responseUpdatedAt: null,
    responseAuthorUserId: null,
    roomAccess: null,
    admissionAction: admissionAction,
    lastDeclineReason: lastDeclineReason,
    lastRemoveReason: null,
    stakeState: 0,
    offerKind: offerKind,
    isDirectAuthorForward: false,
    authorSeenAt: null,
  );
}
