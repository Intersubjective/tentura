import 'package:test/test.dart';

import 'package:tentura_server/consts/commitment_consts.dart';
import 'package:tentura_server/domain/commitment/commitment_event.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/commitment/commitment_state.dart';

void main() {
  final baseTime = DateTime.utc(2026, 1, 1, 12);

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

  group('everAcknowledged', () {
    test('1. empty list', () {
      expect(everAcknowledged([]), isFalse);
      expect(currentStakeState([]), CommitmentStakeState.none);
    });

    test('2. offered only', () {
      final events = [event(seq: 1, kind: CommitmentEventKind.offered)];
      expect(everAcknowledged(events), isFalse);
      expect(currentStakeState(events), CommitmentStakeState.offered);
    });

    test('3. offered then acknowledged', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
      ];
      expect(everAcknowledged(events), isTrue);
      expect(currentStakeState(events), CommitmentStakeState.acknowledged);
    });

    test('4. acknowledged then withdrawn within grace', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(
          seq: 3,
          kind: CommitmentEventKind.withdrawnByHelper,
          offset: const Duration(hours: 1),
        ),
      ];
      expect(everAcknowledged(events), isFalse);
      expect(currentStakeState(events), CommitmentStakeState.exited);
    });

    test('5. acknowledged then withdrawn after grace', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(
          seq: 3,
          kind: CommitmentEventKind.withdrawnByHelper,
          offset: const Duration(hours: 25),
        ),
      ];
      expect(everAcknowledged(events), isTrue);
      expect(currentStakeState(events), CommitmentStakeState.exited);
    });

    test('6. acknowledged then softened', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(seq: 3, kind: CommitmentEventKind.acknowledgementSoftened),
      ];
      expect(everAcknowledged(events), isTrue);
      expect(currentStakeState(events), CommitmentStakeState.softened);
    });

    test('7. acknowledged then removedFromChat keeps stake', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(seq: 3, kind: CommitmentEventKind.removedFromChat),
      ];
      expect(everAcknowledged(events), isTrue);
      expect(currentStakeState(events), CommitmentStakeState.acknowledged);
    });

    test('8. acknowledged then releasedByAuthor', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(seq: 3, kind: CommitmentEventKind.releasedByAuthor),
      ];
      expect(everAcknowledged(events), isTrue);
      expect(currentStakeState(events), CommitmentStakeState.released);
    });

    test('9. acknowledged then blockedCleanup', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(seq: 3, kind: CommitmentEventKind.blockedCleanup),
      ];
      expect(everAcknowledged(events), isTrue);
      expect(currentStakeState(events), CommitmentStakeState.exited);
    });

    test('10. grace withdraw then re-ack then late withdraw', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.acknowledged),
        event(
          seq: 2,
          kind: CommitmentEventKind.withdrawnByHelper,
          offset: const Duration(hours: 1),
        ),
        event(seq: 3, kind: CommitmentEventKind.acknowledged, offset: const Duration(hours: 2)),
        event(
          seq: 4,
          kind: CommitmentEventKind.withdrawnByHelper,
          offset: const Duration(hours: 32),
        ),
      ];
      expect(everAcknowledged(events), isTrue);
    });

    test('11. unsorted input matches sorted result', () {
      final sorted = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(
          seq: 3,
          kind: CommitmentEventKind.withdrawnByHelper,
          offset: const Duration(hours: 25),
        ),
      ];
      final scrambled = [sorted[2], sorted[0], sorted[1]];
      expect(everAcknowledged(scrambled), everAcknowledged(sorted));
      expect(currentStakeState(scrambled), currentStakeState(sorted));
    });

    test('12. grace closed by softened before withdraw', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.acknowledged),
        event(seq: 2, kind: CommitmentEventKind.acknowledgementSoftened),
        event(
          seq: 3,
          kind: CommitmentEventKind.withdrawnByHelper,
          offset: const Duration(hours: 1),
        ),
      ];
      expect(everAcknowledged(events), isTrue);
    });

    test('13. grace closed by removedFromChat before withdraw', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.acknowledged),
        event(seq: 2, kind: CommitmentEventKind.removedFromChat),
        event(
          seq: 3,
          kind: CommitmentEventKind.withdrawnByHelper,
          offset: const Duration(hours: 1),
        ),
      ];
      expect(everAcknowledged(events), isTrue);
    });
  });

  group('stake_state projection index (§2.5)', () {
    final scenarios = <List<CommitmentEvent>, int>{
      []: 0,
      [event(seq: 1, kind: CommitmentEventKind.offered)]: 1,
      [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
      ]: 2,
      [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(
          seq: 3,
          kind: CommitmentEventKind.withdrawnByHelper,
          offset: const Duration(hours: 1),
        ),
      ]: 4,
      [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(
          seq: 3,
          kind: CommitmentEventKind.withdrawnByHelper,
          offset: const Duration(hours: 25),
        ),
      ]: 4,
      [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(seq: 3, kind: CommitmentEventKind.acknowledgementSoftened),
      ]: 3,
      [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(seq: 3, kind: CommitmentEventKind.removedFromChat),
      ]: 2,
      [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(seq: 3, kind: CommitmentEventKind.releasedByAuthor),
      ]: 5,
      [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
        event(seq: 3, kind: CommitmentEventKind.blockedCleanup),
      ]: 4,
      [
        event(seq: 1, kind: CommitmentEventKind.acknowledged),
        event(
          seq: 2,
          kind: CommitmentEventKind.withdrawnByHelper,
          offset: const Duration(hours: 1),
        ),
        event(seq: 3, kind: CommitmentEventKind.acknowledged, offset: const Duration(hours: 2)),
        event(
          seq: 4,
          kind: CommitmentEventKind.withdrawnByHelper,
          offset: const Duration(hours: 32),
        ),
      ]: 4,
      [
        event(seq: 1, kind: CommitmentEventKind.acknowledged),
        event(seq: 2, kind: CommitmentEventKind.acknowledgementSoftened),
        event(
          seq: 3,
          kind: CommitmentEventKind.withdrawnByHelper,
          offset: const Duration(hours: 1),
        ),
      ]: 4,
      [
        event(seq: 1, kind: CommitmentEventKind.acknowledged),
        event(seq: 2, kind: CommitmentEventKind.removedFromChat),
        event(
          seq: 3,
          kind: CommitmentEventKind.withdrawnByHelper,
          offset: const Duration(hours: 1),
        ),
      ]: 4,
    };

    test('14. projection index matches §2.5 table for scenarios 1–13', () {
      for (final entry in scenarios.entries) {
        expect(
          currentStakeState(entry.key).index,
          entry.value,
          reason: 'events: ${entry.key.map((e) => e.kind.name).join(', ')}',
        );
      }
    });
  });

  group('hasCurrentStake', () {
    test('requires acknowledged state and active offer', () {
      final events = [
        event(seq: 1, kind: CommitmentEventKind.offered),
        event(seq: 2, kind: CommitmentEventKind.acknowledged),
      ];
      expect(hasCurrentStake(events, hasActiveOffer: true), isTrue);
      expect(hasCurrentStake(events, hasActiveOffer: false), isFalse);
    });
  });

  test('kCommitmentGracePeriod is 24 hours', () {
    expect(kCommitmentGracePeriod, const Duration(hours: 24));
  });
}
