import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/forward_candidate_peer_row.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/forward_candidates_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/domain/use_case/forward_candidates_case.dart';
import 'package:tentura_server/env.dart';

void main() {
  late _FakePeers peers;
  late _RecordingProfiles profiles;
  late ForwardCandidatesCase case_;

  setUp(() {
    peers = _FakePeers();
    profiles = _RecordingProfiles();
    case_ = ForwardCandidatesCase(
      peers,
      profiles,
      env: Env(environment: Environment.test),
      logger: Logger('ForwardCandidatesCaseTest'),
    );
  });

  test('empty viewer returns no rows and skips IO', () async {
    peers.rows = [
      const ForwardCandidatePeerRow(
        peerId: 'Upeer',
        forwardMr: 1,
        reverseMr: 1,
        viewerTrusts: true,
        trustsViewer: true,
      ),
    ];

    final result = await case_.fetch(viewerId: '  ', context: '');

    expect(result, isEmpty);
    expect(peers.fetchCalls, 0);
    expect(profiles.lookupCalls, 0);
  });

  test('overlays my_vote and scores from the peers row', () async {
    peers.rows = const [
      ForwardCandidatePeerRow(
        peerId: 'Utrust',
        forwardMr: 0,
        reverseMr: 0,
        viewerTrusts: true,
        trustsViewer: true,
      ),
      ForwardCandidatePeerRow(
        peerId: 'Umixed',
        forwardMr: 0.4,
        reverseMr: 0,
        viewerTrusts: false,
        trustsViewer: true,
      ),
    ];

    final result = await case_.fetch(viewerId: 'Uviewer', context: 'abc');

    expect(peers.lastViewerId, 'Uviewer');
    expect(peers.lastContext, 'abc');
    expect(profiles.lastViewerTrusts, {'Utrust'});
    expect(profiles.lastTrustsViewer, {'Utrust', 'Umixed'});
    expect(profiles.lastReciprocal, {'Utrust'});
    expect(result, hasLength(2));
    expect(result[0].id, 'Utrust');
    expect(result[0].myVote, 1);
    expect(result[0].scores.single.dstScore, 0);
    expect(result[0].scores.single.srcScore, 0);
    expect(result[1].id, 'Umixed');
    expect(result[1].myVote, 0);
    expect(result[1].scores.single.dstScore, 0.4);
    expect(result[1].subjectExplicitlyTrustsViewer, isTrue);
  });

  test('preserves peer order and skips missing profiles', () async {
    peers.rows = const [
      ForwardCandidatePeerRow(
        peerId: 'U2',
        forwardMr: 0.2,
        reverseMr: 0.1,
        viewerTrusts: true,
        trustsViewer: true,
      ),
      ForwardCandidatePeerRow(
        peerId: 'Umissing',
        forwardMr: 0.9,
        reverseMr: 0.9,
        viewerTrusts: true,
        trustsViewer: true,
      ),
      ForwardCandidatePeerRow(
        peerId: 'U1',
        forwardMr: 0.1,
        reverseMr: 0.1,
        viewerTrusts: true,
        trustsViewer: true,
      ),
    ];
    profiles.omitIds = {'Umissing'};

    final result = await case_.fetch(viewerId: 'Uviewer', context: '');

    expect(result.map((row) => row.id), ['U2', 'U1']);
  });
}

class _FakePeers implements ForwardCandidatesRepositoryPort {
  List<ForwardCandidatePeerRow> rows = const [];
  int fetchCalls = 0;
  String? lastViewerId;
  String? lastContext;

  @override
  Future<List<ForwardCandidatePeerRow>> fetchVisiblePeers({
    required String viewerId,
    required String context,
  }) async {
    fetchCalls++;
    lastViewerId = viewerId;
    lastContext = context;
    return rows;
  }
}

class _RecordingProfiles implements UserProfileBatchLookup {
  int lookupCalls = 0;
  Set<String> omitIds = const {};
  Set<String>? lastViewerTrusts;
  Set<String>? lastTrustsViewer;
  Set<String>? lastReciprocal;

  @override
  Future<Map<String, UserEntity>> userEntitiesByIds(Iterable<String> ids) async =>
      {
        for (final id in ids) id: UserEntity(id: id, displayName: id),
      };

  @override
  Future<Map<String, UserPublicRecord>> userPublicRecordsByIds({
    required Iterable<String> ids,
    required Set<String> reciprocalPeerIds,
    Set<String> trustsViewerPeerIds = const {},
    Set<String> viewerTrustsPeerIds = const {},
    Map<String, MutualScoreRecord> scoresByPeerId = const {},
  }) async {
    lookupCalls++;
    lastViewerTrusts = viewerTrustsPeerIds;
    lastTrustsViewer = trustsViewerPeerIds;
    lastReciprocal = reciprocalPeerIds;
    return {
      for (final id in ids)
        if (!omitIds.contains(id))
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
}
