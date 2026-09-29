import 'package:test/test.dart';

import 'package:tentura_server/domain/commitment/commitment_event.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/closure/membership_reducer.dart';

void main() {
  final baseTime = DateTime.utc(2026, 1, 1, 12);
  final now = baseTime.add(const Duration(days: 30));

  CommitmentEvent event({
    required int seq,
    required CommitmentEventKind kind,
    Duration offset = Duration.zero,
  }) => CommitmentEvent(
    id: 'CE$seq',
    seq: seq,
    beaconId: 'B1',
    userId: 'U1',
    actorUserId: 'A1',
    kind: kind,
    createdAt: baseTime.add(offset),
  );

  void expectState(
    MemberState actual, {
    required bool member,
    required bool active,
    Departure? departure,
  }) {
    expect(actual.member, member, reason: 'member');
    expect(actual.active, active, reason: 'active');
    expect(actual.departure, departure, reason: 'departure');
  }

  MemberState fold(List<CommitmentEvent> events) =>
      reduce(events, now: now);

  group('MembershipReducer §5.3 event table', () {
    test('acknowledged sets member and active, departure none', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
      ];
      expectState(
        fold(events),
        member: true,
        active: true,
        departure: null,
      );
    });

    test('acknowledged voided within grace does not set member', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(
          seq: 3,
          kind: CommitmentEventKind.withdrawnByHelper,
          offset: const Duration(hours: 1),
        ),
      ];
      expectState(
        fold(events),
        member: false,
        active: false,
        departure: Departure.voluntary,
      );
    });

    test('acknowledgementSoftened does not change membership or activity', () {
      final before = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
      ];
      final after = [
        ...before,
        event(seq: 3, kind: CommitmentEventKind.acknowledgementSoftened),
      ];
      expectState(fold(before), member: true, active: true, departure: null);
      expectState(fold(after), member: true, active: true, departure: null);
    });

    test('withdrawnByHelper sets inactive and voluntary departure', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(
          seq: 3,
          kind: CommitmentEventKind.withdrawnByHelper,
          offset: const Duration(hours: 25),
        ),
      ];
      expectState(
        fold(events),
        member: true,
        active: false,
        departure: Departure.voluntary,
      );
    });

    test('releasedByAuthor sets inactive and removed departure', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(seq: 3, kind: CommitmentEventKind.releasedByAuthor),
      ];
      expectState(
        fold(events),
        member: true,
        active: false,
        departure: Departure.removed,
      );
    });

    test('removedFromChat sets inactive and removed departure', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(seq: 3, kind: CommitmentEventKind.removedFromChat),
      ];
      expectState(
        fold(events),
        member: true,
        active: false,
        departure: Departure.removed,
      );
    });

    test('blockedCleanup sets inactive and removed departure', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(seq: 3, kind: CommitmentEventKind.blockedCleanup),
      ];
      expectState(
        fold(events),
        member: true,
        active: false,
        departure: Departure.removed,
      );
    });

    test('readmittedToChat clears departure and sets active', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(seq: 3, kind: CommitmentEventKind.removedFromChat),
        event(seq: 4, kind: CommitmentEventKind.readmittedToChat),
      ];
      expectState(
        fold(events),
        member: true,
        active: true,
        departure: null,
      );
    });

    test('later acknowledged clears departure and sets active', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(
          seq: 3,
          kind: CommitmentEventKind.withdrawnByHelper,
          offset: const Duration(hours: 25),
        ),
        event(seq: 4, kind: CommitmentEventKind.acknowledged, offset: const Duration(hours: 26)),
      ];
      expectState(
        fold(events),
        member: true,
        active: true,
        departure: null,
      );
    });

    test('offered has no membership effect', () {
      final events = [event(seq: 1, kind: CommitmentEventKind.offered)];
      expectState(
        fold(events),
        member: false,
        active: false,
        departure: null,
      );
    });

    test('unansweredAtClose has no membership effect', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.unansweredAtClose),
      ];
      expectState(
        fold(events),
        member: false,
        active: false,
        departure: null,
      );
    });
  });

  group('MembershipReducer acceptance combos', () {
    test('acknowledged then withdrawn then acknowledged is active, departure null', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(
          seq: 3,
          kind: CommitmentEventKind.withdrawnByHelper,
          offset: const Duration(hours: 25),
        ),
        event(seq: 4, kind: CommitmentEventKind.acknowledged, offset: const Duration(hours: 26)),
      ];
      expectState(
        fold(events),
        member: true,
        active: true,
        departure: null,
      );
    });

    test('acknowledged then removedFromChat then readmittedToChat is active', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(seq: 3, kind: CommitmentEventKind.removedFromChat),
        event(seq: 4, kind: CommitmentEventKind.readmittedToChat),
      ];
      expectState(
        fold(events),
        member: true,
        active: true,
        departure: null,
      );
    });

    test('offered only is not a member', () {
      expectState(
        fold([event(seq: 1, kind: CommitmentEventKind.offered)]),
        member: false,
        active: false,
        departure: null,
      );
    });

    test('blockedCleanup after acknowledge yields removed departure', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(seq: 3, kind: CommitmentEventKind.blockedCleanup),
      ];
      expectState(
        fold(events),
        member: true,
        active: false,
        departure: Departure.removed,
      );
    });
  });

  group('MembershipReducer ordering', () {
    test('unsorted input matches sorted result by seq', () {
      final sorted = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(seq: 3, kind: CommitmentEventKind.removedFromChat),
        event(seq: 4, kind: CommitmentEventKind.readmittedToChat),
      ];
      final scrambled = [sorted[2], sorted[0], sorted[3], sorted[1]];
      expect(fold(scrambled), fold(sorted));
    });
  });
}
