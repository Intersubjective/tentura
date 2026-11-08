// d33586ade (#1173 split): help-offer status ints decode through
// HelpOfferStatus. The wire ints and what an unknown int means are pinned
// here, so the switch from `status == 0 / == 1` changed nothing.

import 'package:test/test.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/help_offer_status.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/timeline_help_offer_mapping.dart';

const _offerer = Profile(id: 'Uofferer00001', displayName: 'First');
final _createdAt = DateTime.utc(2026, 6, 15, 12);
final _updatedAt = DateTime.utc(2026, 6, 16, 12);

HelpOfferWithCoordinationRow _row(int status) => (
  beaconId: 'Bstatus000001',
  userId: _offerer.id,
  user: _offerer,
  message: 'I can help',
  helpType: null,
  roleLabel: null,
  status: status,
  withdrawReason: null,
  createdAt: _createdAt,
  updatedAt: _updatedAt,
  editedAt: null,
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
  authorSeenAt: null,
);

void main() {
  group('HelpOfferStatus wire ints', () {
    test('active is 0 and inactive is 1, both ways', () {
      expect(HelpOfferStatus.active.smallintValue, 0);
      expect(HelpOfferStatus.inactive.smallintValue, 1);
      expect(HelpOfferStatus.tryFromInt(0), HelpOfferStatus.active);
      expect(HelpOfferStatus.tryFromInt(1), HelpOfferStatus.inactive);
      for (final s in HelpOfferStatus.values) {
        expect(HelpOfferStatus.tryFromInt(s.smallintValue), s);
      }
    });

    test('an unknown int or null decodes to null', () {
      expect(HelpOfferStatus.tryFromInt(null), isNull);
      expect(HelpOfferStatus.tryFromInt(2), isNull);
      expect(HelpOfferStatus.tryFromInt(-1), isNull);
    });
  });

  group('decode sites read the same as `status == 1` did', () {
    test('timeline offers: only status 1 is withdrawn; 0 and an unknown int '
        'are not', () {
      final offers = timelineHelpOffersFromRemote([_row(0), _row(1), _row(7)]);
      expect([for (final o in offers) o.isWithdrawn], [false, true, false]);
    });

    test('timeline entries: status 1 adds the withdrawn entry; 0 and an '
        'unknown int do not', () {
      final beacon = Beacon.empty.copyWith(id: 'Bstatus000001');
      bool hasWithdrawn(int status) => helpOfferRowsToTimelineEntries(
        beacon: beacon,
        row: _row(status),
      ).any((e) => e is TimelineHelpOfferWithdrawn);

      expect(hasWithdrawn(0), isFalse);
      expect(hasWithdrawn(1), isTrue);
      expect(hasWithdrawn(7), isFalse);
    });
  });
}
