import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_anchor_status.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';

final _t = DateTime.utc(2026, 6, 20);

BeaconViewState _state({
  required Beacon beacon,
  Profile myProfile = const Profile(id: 'auth', displayName: 'Author'),
  List<TimelineHelpOffer> helpOffers = const [],
  bool isHelpOffered = false,
}) {
  return BeaconViewState(
    beacon: beacon,
    myProfile: myProfile,
    helpOffers: helpOffers,
    isHelpOffered: isHelpOffered,
    status: const StateIsSuccess(),
  );
}

void main() {
  final l10n = lookupL10n(const Locale('en'));

  test('author open with more help needed uses localized slot1', () {
    final beacon = Beacon(
      id: 'b1',
      title: 'T',
      author: const Profile(id: 'auth', displayName: 'Author'),
      createdAt: _t,
      updatedAt: _t,
      lifecycle: BeaconLifecycle.open,
      coordinationStatus: BeaconCoordinationStatus.moreOrDifferentHelpNeeded,
    );
    final slots = beaconViewStatusSlots(
      l10n,
      _state(beacon: beacon, myProfile: beacon.author),
    );

    expect(slots.slot1, l10n.myWorkStatusNeedsMoreHelp);
    expect(slots.displayLine, isNot(contains('GAP')));
    expect(slots.tone, TenturaTone.warn);
  });

  test('helper with author response uses help-offered grammar', () {
    final beacon = Beacon(
      id: 'b2',
      title: 'T',
      author: const Profile(id: 'auth', displayName: 'Author'),
      createdAt: _t,
      updatedAt: _t,
      lifecycle: BeaconLifecycle.open,
      coordinationStatus: BeaconCoordinationStatus.neutral,
    );
    final slots = beaconViewStatusSlots(
      l10n,
      _state(
        beacon: beacon,
        myProfile: const Profile(id: 'helper', displayName: 'Helper'),
        isHelpOffered: true,
        helpOffers: [
          TimelineHelpOffer(
            user: const Profile(id: 'helper', displayName: 'Helper'),
            message: 'I can help',
            createdAt: _t,
            updatedAt: _t,
            coordinationResponse: CoordinationResponseType.useful,
          ),
        ],
      ),
    );

    expect(slots.displayLine, contains(l10n.myWorkStatusHelpOfferedPersonal.toLowerCase()));
    expect(slots.displayLine, isNot(contains('GAP')));
    expect(slots.displayLine, isNot(contains('OK')));
    expect(slots.displayLine, isNot(contains('IDLE')));
    expect(slots.tone, TenturaTone.good);
  });

  test('deleted beacon shows unavailable slot', () {
    final beacon = Beacon(
      id: 'b3',
      title: 'T',
      author: const Profile(id: 'auth', displayName: 'Author'),
      createdAt: _t,
      updatedAt: _t,
      lifecycle: BeaconLifecycle.deleted,
    );
    final slots = beaconViewStatusSlots(l10n, _state(beacon: beacon));

    expect(slots.slot1, l10n.beaconHudBeaconUnavailable);
    expect(slots.displayLine, isNot(contains('GAP')));
  });
}
