// #751: accepting an author invitation admits the viewer at once. Offer help
// and Follow must be gone in the first state after that success, even while
// the refresh that follows still returns the pre-accept slice.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_helper_hud_actions.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

void main() {
  const me = Profile(id: 'Ubob', displayName: 'Bob');
  const beaconId = 'Binvite751';
  final l10n = lookupL10n(const Locale('en'));

  Beacon outsider() => Beacon(
    id: beaconId,
    title: 'QA664 bud',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    accessLevel: BeaconAccessLevel.observer,
    viewerCanForward: true,
    author: const Profile(id: 'Ualice', displayName: 'Alice'),
  );

  test(
    'an accepted invitee is a helper at once, without Offer help or Follow',
    () async {
      final gate = Completer<void>();
      var holdRefresh = false;
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async {
          if (holdRefresh) await gate.future;
          return outsider();
        };
      final offers = _EmptyOffers(() async {
        if (holdRefresh) await gate.future;
        return const [];
      });
      final cubit = BeaconViewCubit(
        id: beaconId,
        myProfile: me,
        beaconViewCase: buildTestBeaconViewCase(
          beaconRepo: beaconRepo,
          coordinationRepo: offers,
          inboxRepo: FakeBeaconViewInboxRepository(
            status: InboxItemStatus.needsMe,
          ),
        ),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      await pumpUntil(
        cubit.stream,
        () =>
            cubit.state.beaconContextLoaded &&
            cubit.state.inboxStatus == InboxItemStatus.needsMe,
      );
      expect(cubit.state.isHelpOffered, isFalse);
      expect(_labels(l10n, cubit.state), contains(l10n.labelOfferHelp));
      expect(_labels(l10n, cubit.state), contains(l10n.beaconHeaderWatch));

      holdRefresh = true;
      final pending = cubit.refreshAfterInviteAnswer(accepted: true);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.isHelpOffered, isTrue);
      expect(cubit.state.isInsideRequest, isTrue);
      final atOnce = _labels(l10n, cubit.state);
      expect(atOnce, isNot(contains(l10n.labelOfferHelp)));
      expect(atOnce, isNot(contains(l10n.beaconHeaderWatch)));

      gate.complete();
      await pending;
      // The lagging read still has no offer and the outsider beacon.
      expect(cubit.state.isHelpOffered, isTrue);
      expect(cubit.state.isInsideRequest, isTrue);
      final afterLag = _labels(l10n, cubit.state);
      expect(afterLag, isNot(contains(l10n.labelOfferHelp)));
      expect(afterLag, isNot(contains(l10n.beaconHeaderWatch)));
    },
  );
}

List<String> _labels(L10n l10n, BeaconViewState state) =>
    buildBeaconHelperHudActions(
      l10n: l10n,
      state: state,
      onOfferHelp: () {},
      onWatch: () {},
      onEditHelpOffer: () {},
    ).primary.map((action) => action.label).toList();

class _EmptyOffers extends FakeBeaconViewCoordinationRepository {
  _EmptyOffers(this.next);

  final Future<List<FakeHelpOfferCoordinationRow>> Function() next;

  @override
  Future<List<FakeHelpOfferCoordinationRow>> fetchHelpOffersWithCoordination({
    required String beaconId,
  }) => next();
}
