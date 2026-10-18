// B028: while a Request wraps up, a member gets a way into the review
// (support colleagues) instead of an empty action rail.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_helper_hud_actions.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _author = Profile(id: 'uAuthor', displayName: 'Author');
const _helper = Profile(id: 'uHelper', displayName: 'Helper');

BeaconViewState _state({
  BeaconStatus status = BeaconStatus.reviewOpen,
  Profile me = _helper,
  bool withClosure = true,
}) => BeaconViewState(
  beacon: Beacon(
    id: 'b1',
    title: 'T',
    author: _author,
    createdAt: DateTime.utc(2026, 10),
    updatedAt: DateTime.utc(2026, 10),
    status: status,
  ),
  myProfile: me,
  beaconContextLoaded: true,
  closureState: withClosure
      ? ClosureState(
          epoch: 2,
          status: 0,
          role: me.id == _author.id ? ClosureRole.author : ClosureRole.voter,
          members: const [],
          closesAt: DateTime.utc(2026, 10, 8),
        )
      : null,
);

void main() {
  final l10n = lookupL10n(const Locale('en'));
  var opened = 0;
  void open() => opened++;

  test('member while wrapping up: one filled action opens the final check', () {
    final actions = buildBeaconHelperHudActions(
      l10n: l10n,
      state: _state(),
      onOpenClosureReview: open,
    );
    expect(actions.primary, hasLength(1));
    final a = actions.primary.single;
    expect(a.label, 'Open the final check');
    expect(a.filled, isTrue);
    a.onPressed!();
    expect(opened, 1);
  });

  test('no closure snapshot (not a member): nothing to open', () {
    expect(
      buildBeaconHelperHudActions(
        l10n: l10n,
        state: _state(withClosure: false),
        onOpenClosureReview: open,
      ).hasActions,
      isFalse,
    );
  });

  test('the author is not offered the member action', () {
    expect(
      buildBeaconHelperHudActions(
        l10n: l10n,
        state: _state(me: _author),
        onOpenClosureReview: open,
      ).hasActions,
      isFalse,
    );
  });

  test('not once the Request is closed', () {
    expect(
      buildBeaconHelperHudActions(
        l10n: l10n,
        state: _state(status: BeaconStatus.closed),
        onOpenClosureReview: open,
      ).hasActions,
      isFalse,
    );
  });
}
