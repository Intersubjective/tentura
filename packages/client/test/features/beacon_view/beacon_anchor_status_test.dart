import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_anchor_status.dart';
import 'package:tentura/ui/l10n/l10n.dart';

final _t = DateTime.utc(2026, 6, 20);

BeaconViewState _state({
  required Beacon beacon,
  Profile myProfile = const Profile(id: 'auth', displayName: 'Author'),
}) {
  return BeaconViewState(
    beacon: beacon,
    myProfile: myProfile,
  );
}

void main() {
  final l10n = lookupL10n(const Locale('en'));

  test('author open with more help needed uses phase status', () {
    final beacon = Beacon(
      id: 'b1',
      title: 'T',
      author: const Profile(id: 'auth', displayName: 'Author'),
      createdAt: _t,
      updatedAt: _t,
      status: BeaconStatus.needsMoreHelp,
    );
    final slots = beaconViewStatusSlots(
      l10n,
      _state(beacon: beacon, myProfile: beacon.author),
    );

    expect(slots.slot1, contains(l10n.beaconPhaseNeedsMoreHelp));
    expect(slots.displayLine, isNotEmpty);
    expect(slots.tone, TenturaTone.warn);
  });

  test('open neutral zero offers uses looking for helpers phase', () {
    final beacon = Beacon(
      id: 'b2',
      title: 'T',
      author: const Profile(id: 'auth', displayName: 'Author'),
      createdAt: _t,
      updatedAt: _t,
    );
    final slots = beaconViewStatusSlots(
      l10n,
      _state(
        beacon: beacon,
        myProfile: const Profile(id: 'helper', displayName: 'Helper'),
      ),
    );

    expect(slots.displayLine, contains(l10n.beaconPhaseLookingForHelpers));
    expect(slots.displayLine, isNotEmpty);
  });

  test('deleted beacon shows unavailable slot', () {
    final beacon = Beacon(
      id: 'b3',
      title: 'T',
      author: const Profile(id: 'auth', displayName: 'Author'),
      createdAt: _t,
      updatedAt: _t,
      status: BeaconStatus.deleted,
    );
    final slots = beaconViewStatusSlots(l10n, _state(beacon: beacon));

    expect(slots.slot1, l10n.beaconHudBeaconUnavailable);
    expect(slots.displayLine, isNotEmpty);
  });

  test('status line is never empty for open beacon', () {
    final beacon = Beacon(
      id: 'b4',
      title: 'T',
      author: const Profile(id: 'auth', displayName: 'Author'),
      createdAt: _t,
      updatedAt: _t,
    );
    final slots = beaconViewStatusSlots(l10n, _state(beacon: beacon));
    expect(slots.displayLine.trim(), isNotEmpty);
  });
}
