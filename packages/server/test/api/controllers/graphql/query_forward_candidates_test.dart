import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_forward_candidates.dart';
import 'package:tentura_server/domain/entity/forward_candidate_peer_row.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/forward_candidates_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/domain/use_case/forward_candidates_case.dart';
import 'package:tentura_server/env.dart';
import 'package:injectable/injectable.dart' show Environment;

void main() {
  const auth = {kGlobalInputQueryJwt: JwtEntity(sub: 'Uviewer')};

  late _FakePeers peers;
  late QueryForwardCandidates query;

  setUp(() {
    peers = _FakePeers();
    query = QueryForwardCandidates(
      forwardCandidatesCase: ForwardCandidatesCase(
        peers,
        _PassthroughProfiles(),
        env: Env(environment: Environment.test),
        logger: Logger('QueryForwardCandidatesTest'),
      ),
    );
  });

  test('exposes forwardCandidates on the query root', () {
    expect(query.all.map((field) => field.name), ['forwardCandidates']);
  });

  test('scopes the viewer to JWT sub only', () async {
    peers.rows = const [
      ForwardCandidatePeerRow(
        peerId: 'Upeer',
        forwardMr: 0,
        reverseMr: 0,
        viewerTrusts: true,
        trustsViewer: true,
      ),
    ];

    final field = query.forwardCandidates;
    final rows =
        await field.resolve!(null, {
              ...auth,
              'context': '',
              'viewerId': 'U-ATTACKER',
            })
            as List<Map<String, dynamic>>;

    expect(peers.lastViewerId, 'Uviewer');
    expect(rows, hasLength(1));
    expect(rows.single['id'], 'Upeer');
    expect(rows.single['my_vote'], 1);
  });

  test('rejects unauthenticated calls', () async {
    final field = query.forwardCandidates;
    await expectLater(
      field.resolve!(null, {'context': ''}),
      throwsA(isA<UnauthorizedException>()),
    );
  });
}

class _FakePeers implements ForwardCandidatesRepositoryPort {
  List<ForwardCandidatePeerRow> rows = const [];
  String? lastViewerId;

  @override
  Future<List<ForwardCandidatePeerRow>> fetchVisiblePeers({
    required String viewerId,
    required String context,
  }) async {
    lastViewerId = viewerId;
    return rows;
  }
}

class _PassthroughProfiles implements UserProfileBatchLookup {
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
