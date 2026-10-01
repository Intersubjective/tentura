import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/forward_candidate_peer_row.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/forward_candidates_repository_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/domain/use_case/forward_candidates_case.dart';
import 'package:tentura_server/env.dart';

/// B3 "I pinged them" display factor:
/// displayed score × (1 − min(0.8, Σ 2^(−age_days))) over the viewer's own
/// forwards to the candidate in the last 7 days. Display only.
void main() {
  final now = DateTime.utc(2026, 10, 1, 12);
  const viewer = 'Uviewer';
  const peer = 'Upeer';
  const baseScore = 0.5;

  late _FakePeers peers;
  late ForwardCandidatesCase case_;

  setUp(() {
    peers = _FakePeers()
      ..rows = const [
        ForwardCandidatePeerRow(
          peerId: peer,
          forwardMr: baseScore,
          reverseMr: 0.3,
          viewerTrusts: true,
          trustsViewer: true,
        ),
      ];
    case_ = ForwardCandidatesCase(
      peers,
      _Profiles(),
      _Bonds(),
      env: Env(environment: Environment.test),
      logger: Logger('ForwardCandidatesPingFactorTest'),
    );
  });

  Future<double> displayedScore({String id = peer}) async {
    final result = await case_.fetch(
      viewerId: viewer,
      context: '',
      now: now,
    );
    return result.singleWhere((u) => u.id == id).scores.single.dstScore!;
  }

  DateTime ago(Duration d) => now.subtract(d);

  test('zero forwards ⇒ factor 1.0', () async {
    expect(await displayedScore(), closeTo(baseScore, 1e-9));
  });

  test('one forward right now ⇒ factor 0.2', () async {
    peers.forwardTimes = {
      peer: [now],
    };

    expect(await displayedScore(), closeTo(baseScore * 0.2, 1e-9));
  });

  test('two forwards now ⇒ still 0.2 (clamped)', () async {
    peers.forwardTimes = {
      peer: [now, now],
    };

    expect(await displayedScore(), closeTo(baseScore * 0.2, 1e-9));
  });

  test('sum above the clamp keeps factor at 0.2', () async {
    peers.forwardTimes = {
      peer: [now, ago(const Duration(days: 1)), ago(const Duration(days: 1))],
    };

    expect(await displayedScore(), closeTo(baseScore * 0.2, 1e-9));
  });

  test('one forward 1 day old ⇒ Σ = 0.5 ⇒ factor 0.5', () async {
    peers.forwardTimes = {
      peer: [ago(const Duration(days: 1))],
    };

    expect(await displayedScore(), closeTo(baseScore * 0.5, 1e-9));
  });

  test('forwards decay and add below the clamp: 2^-1 + 2^-2 ⇒ 0.25', () async {
    peers.forwardTimes = {
      peer: [
        ago(const Duration(days: 1)),
        ago(const Duration(days: 2)),
      ],
    };

    expect(await displayedScore(), closeTo(baseScore * 0.25, 1e-9));
  });

  test('fractional age: 12 hours old ⇒ Σ = 2^-0.5', () async {
    peers.forwardTimes = {
      peer: [ago(const Duration(hours: 12))],
    };

    // 2^-0.5 ≈ 0.7071 ⇒ factor ≈ 0.2929 (above the 0.2 floor).
    expect(await displayedScore(), closeTo(baseScore * 0.29289, 1e-4));
  });

  test('one forward exactly 7 days old ⇒ Σ = 2^-7 ⇒ factor ≈ 0.992', () async {
    peers.forwardTimes = {
      peer: [ago(const Duration(days: 7))],
    };

    // 1 − 2^-7 = 0.9921875: the 7-day boundary is inclusive.
    expect(await displayedScore(), closeTo(baseScore * 0.9921875, 1e-6));
  });

  test('one forward just under 7 days old is counted', () async {
    peers.forwardTimes = {
      peer: [ago(const Duration(days: 7) - const Duration(minutes: 1))],
    };

    expect(await displayedScore(), closeTo(baseScore * 0.9921875, 1e-4));
  });

  test('a forward just over 7 days old is ignored', () async {
    peers.forwardTimes = {
      peer: [ago(const Duration(days: 7, minutes: 1))],
    };

    expect(await displayedScore(), closeTo(baseScore, 1e-9));
  });

  test('a forward older than 7 days is ignored', () async {
    peers.forwardTimes = {
      peer: [ago(const Duration(days: 8))],
    };

    expect(await displayedScore(), closeTo(baseScore, 1e-9));
  });

  test('an old forward does not add to a fresh one', () async {
    peers.forwardTimes = {
      peer: [now, ago(const Duration(days: 30))],
    };

    expect(await displayedScore(), closeTo(baseScore * 0.2, 1e-9));
  });

  test('forwards to other users do not affect this candidate', () async {
    peers.forwardTimes = {
      'Uother': [now, now],
    };

    expect(await displayedScore(), closeTo(baseScore, 1e-9));
  });

  test('factor applies per candidate', () async {
    peers.rows = const [
      ForwardCandidatePeerRow(
        peerId: 'Upinged',
        forwardMr: 0.8,
        reverseMr: 0.1,
        viewerTrusts: true,
        trustsViewer: false,
      ),
      ForwardCandidatePeerRow(
        peerId: 'Ufresh',
        forwardMr: 0.4,
        reverseMr: 0.1,
        viewerTrusts: true,
        trustsViewer: false,
      ),
    ];
    peers.forwardTimes = {
      'Upinged': [now],
    };

    expect(await displayedScore(id: 'Upinged'), closeTo(0.8 * 0.2, 1e-9));
    expect(await displayedScore(id: 'Ufresh'), closeTo(0.4, 1e-9));
  });

  test('only the viewer-owned forward window is requested', () async {
    await displayedScore();

    expect(peers.forwardTimesViewerId, viewer);
    final since = peers.forwardTimesSince!;
    // The query window must reach back at least 7 days and no further than
    // needed to be useful (never into the future).
    expect(since.isAfter(ago(const Duration(days: 7))), isFalse);
    expect(since.isBefore(now), isTrue);
  });

  test('display only: reads peers and forwards, performs no writes', () async {
    peers.forwardTimes = {
      peer: [now],
    };

    await displayedScore();

    // The case's only collaborators are the peers port, the bond port (whose
    // fake throws on anything but `bondPeerIds`) and a read-only profile
    // lookup. The factor must be computed from reads alone.
    expect(
      peers.calls.toSet(),
      {'fetchVisiblePeers', 'fetchRecentOwnForwardTimes'},
    );
    expect(peers.calls, hasLength(2));
  });

  test('empty viewer skips the forward lookup', () async {
    final result = await case_.fetch(viewerId: '  ', context: '', now: now);

    expect(result, isEmpty);
    expect(peers.forwardTimesCalls, 0);
  });
}

class _Bonds implements PersonVisibilityRepositoryPort {
  @override
  Future<Set<String>> bondPeerIds({required String viewerId}) async =>
      const {};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakePeers implements ForwardCandidatesRepositoryPort {
  List<ForwardCandidatePeerRow> rows = const [];

  /// Returned verbatim (including entries older than the requested window) so
  /// the case itself must ignore forwards older than 7 days.
  Map<String, List<DateTime>> forwardTimes = const {};
  final calls = <String>[];
  int forwardTimesCalls = 0;
  String? forwardTimesViewerId;
  DateTime? forwardTimesSince;

  @override
  Future<List<ForwardCandidatePeerRow>> fetchVisiblePeers({
    required String viewerId,
    required String context,
  }) async {
    calls.add('fetchVisiblePeers');
    return rows;
  }

  @override
  Future<Map<String, List<DateTime>>> fetchRecentOwnForwardTimes({
    required String viewerId,
    required DateTime since,
  }) async {
    calls.add('fetchRecentOwnForwardTimes');
    forwardTimesCalls++;
    forwardTimesViewerId = viewerId;
    forwardTimesSince = since;
    return forwardTimes;
  }
}

class _Profiles implements UserProfileBatchLookup {
  @override
  Future<Map<String, UserEntity>> userEntitiesByIds(
    Iterable<String> ids,
  ) async => {
    for (final id in ids) id: UserEntity(id: id, displayName: id),
  };

  @override
  Future<Map<String, UserPublicRecord>> userPublicRecordsByIds({
    required Iterable<String> ids,
    required Set<String> reciprocalPeerIds,
    Set<String> trustsViewerPeerIds = const {},
    Set<String> viewerTrustsPeerIds = const {},
    Map<String, MutualScoreRecord> scoresByPeerId = const {},
  }) async => {
    for (final id in ids)
      id: UserPublicRecord(
        id: id,
        displayName: id,
        description: '',
        myVote: viewerTrustsPeerIds.contains(id) ? 1 : 0,
        isMutualFriend: reciprocalPeerIds.contains(id),
        subjectExplicitlyTrustsViewer: trustsViewerPeerIds.contains(id),
        scores: [
          ?scoresByPeerId[id],
        ],
        userAvailability: null,
      ),
  };
}
