import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/commitment/commitment_event.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/deadline_reminder_sweep_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/test_attention_harness.dart';

final _epoch = DateTime.utc(2026, 11, 2);

/// Candidates and the lock answer per beacon; records the windows asked.
final class _FakeBeacons extends Fake implements BeaconRepositoryPort {
  List<String> candidates = const [];

  /// Beacon id -> what the lock returns (absent = null: no longer due).
  final locked = <String, BeaconEntity>{};

  final candidateWindows = <(DateTime, DateTime)>[];
  final lockCalls = <(String, DateTime, DateTime)>[];

  @override
  Future<List<String>> deadlineReminderCandidateIds({
    required DateTime nextUtcDayStart,
    required DateTime followingUtcDayStart,
  }) async {
    candidateWindows.add((nextUtcDayStart, followingUtcDayStart));
    return candidates;
  }

  @override
  Future<BeaconEntity?> lockOpenBeaconForDeadlineReminder({
    required String beaconId,
    required DateTime nextUtcDayStart,
    required DateTime followingUtcDayStart,
  }) async {
    lockCalls.add((beaconId, nextUtcDayStart, followingUtcDayStart));
    return locked[beaconId];
  }
}

/// Beacon id -> user id -> commitment event kinds, in order.
final class _FakeCommitments extends Fake implements CommitmentRepositoryPort {
  final kinds = <String, Map<String, List<CommitmentEventKind>>>{};

  @override
  Future<Map<String, List<CommitmentEvent>>> eventsByUser(
    String beaconId,
  ) async => {
    for (final MapEntry(key: userId, value: userKinds)
        in (kinds[beaconId] ?? const {}).entries)
      userId: [
        for (final (seq, kind) in userKinds.indexed)
          CommitmentEvent(
            id: 'CE$beaconId$userId$seq',
            seq: seq,
            beaconId: beaconId,
            userId: userId,
            actorUserId: userId,
            kind: kind,
            createdAt: _epoch,
          ),
      ],
  };
}

/// Beacon id -> users with an active help offer.
final class _FakeHelpOffers extends Fake implements HelpOfferRepositoryPort {
  final active = <String, Set<String>>{};

  @override
  Future<List<HelpOfferEntity>> fetchAllByBeaconId(String beaconId) async => [
    for (final userId in active[beaconId] ?? const <String>{})
      HelpOfferEntity(
        beaconId: beaconId,
        userId: userId,
        createdAt: _epoch,
        updatedAt: _epoch,
      ),
  ];
}

BeaconEntity _beacon(String id, {DateTime? endAt}) => BeaconEntity(
  id: id,
  title: id,
  author: const UserEntity(id: 'Uauthor'),
  createdAt: _epoch,
  updatedAt: _epoch,
  endAt: endAt,
);

void main() {
  // 15:00 UTC on Nov 7: "tomorrow" is the UTC day starting Nov 8.
  final now = DateTime.utc(2026, 11, 7, 15);
  final tomorrow = DateTime.utc(2026, 11, 8);
  final following = DateTime.utc(2026, 11, 9);
  final deadline = DateTime.utc(2026, 11, 8, 18);

  late _FakeBeacons beacons;
  late _FakeCommitments commitments;
  late _FakeHelpOffers offers;
  late TestAttentionHarness attention;
  late DeadlineReminderSweepCase sweep;

  setUp(() {
    beacons = _FakeBeacons();
    commitments = _FakeCommitments();
    offers = _FakeHelpOffers();
    attention = TestAttentionHarness();
    sweep = DeadlineReminderSweepCase(
      beacons,
      CommitmentQueryCase(
        commitments,
        offers,
        env: Env(environment: Environment.test),
        logger: Logger('DeadlineReminderSweepCaseTest'),
      ),
      attention.intents,
      attention.transactional,
    );
  });

  /// [userId] holds a current commitment on [beaconId].
  void commit(String beaconId, String userId) {
    (commitments.kinds[beaconId] ??= {})[userId] = [
      CommitmentEventKind.offered,
      CommitmentEventKind.acknowledged,
    ];
    (offers.active[beaconId] ??= {}).add(userId);
  }

  test('asks for the next UTC day window, whatever the local offset', () async {
    await sweep.runDue(now: DateTime.parse('2026-11-07T23:30:00-05:00'));
    // 04:30 UTC on Nov 8 -> the window is Nov 9..Nov 10.
    expect(beacons.candidateWindows, [
      (DateTime.utc(2026, 11, 9), DateTime.utc(2026, 11, 10)),
    ]);
  });

  test('no candidates: records nothing and locks nothing', () async {
    expect(await sweep.runDue(now: now), 0);
    expect(beacons.lockCalls, isEmpty);
    expect(attention.recorded, isEmpty);
  });

  test('one reminder per due beacon, to its current committers only', () async {
    beacons
      ..candidates = ['B1', 'B2']
      ..locked['B1'] = _beacon('B1', endAt: deadline)
      ..locked['B2'] = _beacon('B2', endAt: deadline);
    commit('B1', 'Uhelper1');
    commit('B1', 'Uhelper2');
    commit('B2', 'Uhelper3');
    // Acknowledged once, then withdrew: not a current committer.
    commitments.kinds['B1']!['Ugone'] = [
      CommitmentEventKind.offered,
      CommitmentEventKind.acknowledged,
      CommitmentEventKind.withdrawnByHelper,
    ];

    expect(await sweep.runDue(now: now), 2);

    expect(beacons.lockCalls, [
      ('B1', tomorrow, following),
      ('B2', tomorrow, following),
    ]);
    final byBeacon = {for (final i in attention.recorded) i.beaconId: i};
    expect(byBeacon.keys, unorderedEquals(['B1', 'B2']));
    final b1 = byBeacon['B1']!;
    expect(b1.eventType, AttentionEventType.deadlineReminder);
    expect(
      b1.sourceEventKey,
      'deadline_reminder:B1:${tomorrow.toIso8601String()}',
    );
    expect(
      b1.recipients.map((r) => r.recipientId),
      unorderedEquals(['Uhelper1', 'Uhelper2']),
    );
    expect(
      byBeacon['B2']!.recipients.map((r) => r.recipientId),
      ['Uhelper3'],
    );
  });

  test('skips beacons the lock no longer returns, without a deadline, '
      'or without current committers, and keeps going', () async {
    beacons
      ..candidates = ['Bgone', 'Bnoend', 'Bnobody', 'Bdue']
      ..locked['Bnoend'] = _beacon('Bnoend')
      ..locked['Bnobody'] = _beacon('Bnobody', endAt: deadline)
      ..locked['Bdue'] = _beacon('Bdue', endAt: deadline);
    commit('Bnoend', 'Uhelper');
    commit('Bdue', 'Uhelper');
    // Offered but never acknowledged: no stake yet.
    commitments.kinds['Bnobody'] = {
      'Uoffered': [CommitmentEventKind.offered],
    };
    offers.active['Bnobody'] = {'Uoffered'};

    expect(await sweep.runDue(now: now), 1);

    expect(beacons.lockCalls.map((c) => c.$1), [
      'Bgone',
      'Bnoend',
      'Bnobody',
      'Bdue',
    ]);
    expect(attention.recorded.single.beaconId, 'Bdue');
  });
}
