// Issue #178 part 2: keep the initial-query authorSeenAt watermark on its
// own help offer so the offerer-facing status can use the per-offer cutoff.

import 'package:test/test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/timeline_help_offer_mapping.dart';

const _firstOfferer = Profile(id: 'Uofferer00001', displayName: 'First');
const _secondOfferer = Profile(id: 'Uofferer00002', displayName: 'Second');
final _createdAt = DateTime.utc(2026, 6, 15, 12);
final _seenAt = _createdAt.add(const Duration(minutes: 5));

HelpOfferWithCoordinationRow _row({
  required Profile offerer,
  DateTime? authorSeenAt,
}) => (
  beaconId: 'Bauthorseen01',
  userId: offerer.id,
  user: offerer,
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

// Keep the test compilable while TimelineHelpOffer has no authorSeenAt field.
DateTime? _authorSeenAt(Object offer) =>
    (offer as dynamic).authorSeenAt as DateTime?;

void main() {
  test('initial query maps authorSeenAt onto only its matching offer', () {
    final offers = timelineHelpOffersFromRemote([
      _row(offerer: _firstOfferer, authorSeenAt: _seenAt),
      _row(offerer: _secondOfferer),
    ]);

    expect(offers, hasLength(2));
    expect(offers[0].user.id, _firstOfferer.id);
    expect(offers[1].user.id, _secondOfferer.id);
    expect(_authorSeenAt(offers[0]), _seenAt);
    expect(_authorSeenAt(offers[1]), isNull);
  });

  test('updating an offer preserves its authorSeenAt watermark', () {
    final offer = timelineHelpOffersFromRemote([
      _row(offerer: _firstOfferer, authorSeenAt: _seenAt),
    ]).single;

    final updated = offer.copyWith(message: 'I can help after lunch');

    expect(updated.message, 'I can help after lunch');
    expect(_authorSeenAt(updated), _seenAt);
  });
}
