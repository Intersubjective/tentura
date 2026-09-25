// tentura-id8.11: the offers wire carries authorSeenAt as an ISO string; the
// mapping layer parses it tolerantly (null / unparsable -> null, never throws).

import 'package:test/test.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/bloc/timeline_help_offer_mapping.dart';

const _offerer = Profile(id: 'Uofferer00001', displayName: 'First');
final _createdAt = DateTime.utc(2026, 6, 15, 12);

HelpOfferWithCoordinationRow _row({String? authorSeenAt}) => (
  beaconId: 'Bauthorseen01',
  userId: _offerer.id,
  user: _offerer,
  message: 'I can help',
  helpType: null,
  roleLabel: null,
  status: 0,
  withdrawReason: null,
  createdAt: _createdAt,
  updatedAt: _createdAt,
  responseType: null,
  responseUpdatedAt: null,
  responseAuthorUserId: null,
  roomAccess: null,
  admissionAction: null,
  lastDeclineReason: null,
  lastRemoveReason: null,
  stakeState: 0,
  offerKind: 0,
  isDirectAuthorForward: false,
  authorSeenAt: authorSeenAt,
);

void main() {
  test('ISO authorSeenAt maps to the same UTC instant', () {
    final offer = timelineHelpOffersFromRemote([
      _row(authorSeenAt: '2026-09-21T14:02:00Z'),
    ]).single;

    final seen = offer.authorSeenAt;
    expect(seen, isNotNull);
    expect(seen!.isUtc, isTrue);
    expect(seen, DateTime.utc(2026, 9, 21, 14, 2));
  });

  test('null authorSeenAt maps to null', () {
    final offer = timelineHelpOffersFromRemote([_row()]).single;
    expect(offer.authorSeenAt, isNull);
  });

  test('unparsable authorSeenAt maps to null without throwing', () {
    final row = _row(authorSeenAt: 'not-a-date');
    expect(() => timelineHelpOffersFromRemote([row]), returnsNormally);
    expect(timelineHelpOffersFromRemote([row]).single.authorSeenAt, isNull);
  });

  test('copyWith(authorSeenAt) sets it and keeps every other field', () {
    final source = TimelineHelpOffer(
      user: _offerer,
      message: 'I can help',
      createdAt: _createdAt,
      updatedAt: _createdAt.add(const Duration(hours: 1)),
      isWithdrawn: true,
      helpType: 'skill',
      roleLabel: 'Driver',
      coordinationResponse: CoordinationResponseType.values.first,
      withdrawReason: 'busy',
      roomAccess: 2,
      admissionAction: HelpOfferAdmissionAction.values.first,
      lastDeclineReason: 'declined',
      lastRemoveReason: 'removed',
      stakeState: CommitmentStakeState.values.last,
      offerKind: 3,
      isDirectAuthorForward: true,
    );
    final seen = DateTime.utc(2026, 9, 21, 14, 2);

    final u = source.copyWith(authorSeenAt: seen);

    expect(u.authorSeenAt, seen);
    expect(source.authorSeenAt, isNull);
    expect(u.user, source.user);
    expect(u.message, source.message);
    expect(u.createdAt, source.createdAt);
    expect(u.updatedAt, source.updatedAt);
    expect(u.isWithdrawn, source.isWithdrawn);
    expect(u.helpType, source.helpType);
    expect(u.roleLabel, source.roleLabel);
    expect(u.coordinationResponse, source.coordinationResponse);
    expect(u.withdrawReason, source.withdrawReason);
    expect(u.roomAccess, source.roomAccess);
    expect(u.admissionAction, source.admissionAction);
    expect(u.lastDeclineReason, source.lastDeclineReason);
    expect(u.lastRemoveReason, source.lastRemoveReason);
    expect(u.stakeState, source.stakeState);
    expect(u.offerKind, source.offerKind);
    expect(u.isDirectAuthorForward, source.isDirectAuthorForward);
  });
}
