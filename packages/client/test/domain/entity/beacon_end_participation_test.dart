import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

Beacon _beacon(BeaconStatus status) => Beacon(
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  id: 'B1',
  status: status,
);

void main() {
  group('#489 Beacon end-participation gate', () {
    test('status gate follows allowsCoordination in every status', () {
      for (final status in BeaconStatus.values) {
        expect(
          _beacon(status).allowsEndParticipation,
          status.allowsCoordination,
          reason: '$status',
        );
      }
    });

    test('the gate is the entity coordination gate, Posts included', () {
      for (final status in BeaconStatus.values) {
        for (final kind in BeaconKind.values) {
          final b = _beacon(status).copyWith(kind: kind);
          expect(
            b.allowsEndParticipation,
            b.allowsCoordination,
            reason: '$kind $status',
          );
        }
      }
    });

    test('open-family and Wrapping up allow ending participation', () {
      expect(_beacon(BeaconStatus.open).allowsEndParticipation, isTrue);
      expect(_beacon(BeaconStatus.reviewOpen).allowsEndParticipation, isTrue);
    });

    test('final statuses and draft do not allow ending participation', () {
      for (final status in [
        BeaconStatus.closed,
        BeaconStatus.cancelled,
        BeaconStatus.deleted,
        BeaconStatus.draft,
      ]) {
        expect(
          _beacon(status).allowsEndParticipation,
          isFalse,
          reason: '$status',
        );
      }
    });

    test('author or steward may end another helper in every status', () {
      for (final status in BeaconStatus.values) {
        expect(
          _beacon(status).canEndParticipationOf(
            targetIsAuthor: false,
            targetIsViewer: false,
            viewerIsAuthorOrSteward: true,
          ),
          status.allowsCoordination,
          reason: '$status',
        );
      }
    });

    test('nobody ends the author, themselves, or as a plain viewer', () {
      for (final status in BeaconStatus.values) {
        final b = _beacon(status);
        expect(
          b.canEndParticipationOf(
            targetIsAuthor: true,
            targetIsViewer: false,
            viewerIsAuthorOrSteward: true,
          ),
          isFalse,
          reason: 'author target, $status',
        );
        expect(
          b.canEndParticipationOf(
            targetIsAuthor: false,
            targetIsViewer: true,
            viewerIsAuthorOrSteward: true,
          ),
          isFalse,
          reason: 'self target, $status',
        );
        expect(
          b.canEndParticipationOf(
            targetIsAuthor: false,
            targetIsViewer: false,
            viewerIsAuthorOrSteward: false,
          ),
          isFalse,
          reason: 'plain viewer, $status',
        );
      }
    });
  });
}
