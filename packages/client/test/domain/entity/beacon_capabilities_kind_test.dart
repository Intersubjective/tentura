import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

Beacon _beacon({
  required BeaconKind kind,
  bool canRead = true,
  BeaconStatus status = BeaconStatus.open,
}) => Beacon(
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  id: 'B1',
  kind: kind,
  canReadContent: canRead,
  status: status,
);

void main() {
  group('Beacon kind capability truth table', () {
    test('a Request is a request and a Post is not', () {
      expect(_beacon(kind: BeaconKind.request).isRequest, isTrue);
      expect(_beacon(kind: BeaconKind.post).isRequest, isFalse);
    });

    test('kind defaults to a Request', () {
      expect(Beacon.empty.kind, BeaconKind.request);
      expect(Beacon.empty.isRequest, isTrue);
    });

    test('open readable Request keeps every Request capability', () {
      final b = _beacon(kind: BeaconKind.request);
      expect(b.status, BeaconStatus.open);
      expect(b.canCommitAsViewer, isTrue);
      expect(b.allowsNewHelpOfferAsNonAuthor, isTrue);
      expect(b.allowsWithdrawWhileHelpOffered, isTrue);
      expect(b.allowsCoordination, BeaconStatus.open.allowsCoordination);
      expect(b.allowsForward, BeaconStatus.open.allowsForward);
    });

    test('open readable Post has no Request capability', () {
      final b = _beacon(kind: BeaconKind.post);
      expect(b.status, BeaconStatus.open);
      expect(b.canCommitAsViewer, isFalse);
      expect(b.allowsNewHelpOfferAsNonAuthor, isFalse);
      expect(b.allowsWithdrawWhileHelpOffered, isFalse);
      expect(b.allowsCoordination, isFalse);
      expect(b.allowsForward, isFalse);
    });

    test('unreadable Request cannot be committed to', () {
      final b = _beacon(kind: BeaconKind.request, canRead: false);
      expect(b.canOpenAsViewer, isFalse);
      expect(b.canCommitAsViewer, isFalse);
    });

    test('unreadable Post has no capability and cannot be opened', () {
      final b = _beacon(kind: BeaconKind.post, canRead: false);
      expect(b.canOpenAsViewer, isFalse);
      expect(b.canCommitAsViewer, isFalse);
      expect(b.allowsNewHelpOfferAsNonAuthor, isFalse);
      expect(b.allowsWithdrawWhileHelpOffered, isFalse);
      expect(b.allowsCoordination, isFalse);
      expect(b.allowsForward, isFalse);
    });

    test('Post in every status has no Request capability', () {
      for (final status in BeaconStatus.values) {
        final b = _beacon(kind: BeaconKind.post, status: status);
        expect(b.canCommitAsViewer, isFalse, reason: '$status');
        expect(b.allowsNewHelpOfferAsNonAuthor, isFalse, reason: '$status');
        expect(b.allowsWithdrawWhileHelpOffered, isFalse, reason: '$status');
        expect(b.allowsCoordination, isFalse, reason: '$status');
        expect(b.allowsForward, isFalse, reason: '$status');
      }
    });

    test('Request in every status keeps the status-derived capabilities', () {
      for (final status in BeaconStatus.values) {
        final b = _beacon(kind: BeaconKind.request, status: status);
        expect(b.canCommitAsViewer, status.isOpenFamily, reason: '$status');
        expect(
          b.allowsNewHelpOfferAsNonAuthor,
          status.isOpenFamily,
          reason: '$status',
        );
        expect(
          b.allowsWithdrawWhileHelpOffered,
          status.isOpenFamily,
          reason: '$status',
        );
        expect(b.allowsCoordination, status.allowsCoordination);
        expect(b.allowsForward, status.allowsForward);
        expect(b.isFinished, status.isFinished);
      }
    });

    test('Post still opens for a viewer who can read it', () {
      expect(_beacon(kind: BeaconKind.post).canOpenAsViewer, isTrue);
    });
  });

  group('BeaconKind wire values', () {
    test('request is 0 and post is 1', () {
      expect(BeaconKind.request.value, 0);
      expect(BeaconKind.post.value, 1);
      expect(BeaconKind.fromValue(1), BeaconKind.post);
    });
  });
}
