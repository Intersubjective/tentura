import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/query/query_invite_genealogy.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/invite_genealogy_graph_entity.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/merit_score_lookup_port.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';
import 'package:tentura_server/domain/use_case/invite_genealogy_case.dart';
import 'package:tentura_server/env.dart';

class _FakeInviteGenealogyRepository implements InviteGenealogyRepositoryPort {
  @override
  Future<void> recordSignupEdge({
    required String ancestorUserId,
    required DateTime ancestorUserCreatedAt,
    required String descendantUserId,
    required DateTime descendantUserCreatedAt,
    required String invitationId,
  }) async {}

  @override
  Future<InviteGenealogyGraphEntity> fetchLineage({
    required String userId,
  }) async => const InviteGenealogyGraphEntity(
    viewerNodeKey: 'Gviewer',
    nodes: [],
    edges: [],
  );

  @override
  Future<InviteGenealogyGraphEntity> fetchLineageBetween({
    required String viewerId,
    required String targetId,
  }) async => const InviteGenealogyGraphEntity(
    viewerNodeKey: 'Gviewer',
    targetNodeKey: 'Gtarget',
    nodes: [],
    edges: [],
  );

  @override
  Future<InviteGenealogyChildrenPageEntity> fetchChildren({
    required String nodeKey,
    required int limit,
    DateTime? afterCreatedAt,
    String? afterNodeKey,
  }) async => const InviteGenealogyChildrenPageEntity(nodes: [], edges: []);

  @override
  Future<Map<String, int>> fetchChildCounts({
    required List<String> nodeKeys,
  }) async => {for (final nodeKey in nodeKeys) nodeKey: 0};
}

class _FakeMeritScoreLookup implements MeritScoreLookupPort {
  @override
  Future<Map<String, MutualScoreRecord>> reciprocalScoresForViewer({
    required String viewerId,
    required String context,
  }) async => {};
}

class _FakeVoteUserFriendshipLookup implements VoteUserFriendshipLookupPort {
  @override
  Future<Set<String>> reciprocalPositivePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
  }) async => {};

  @override
  Future<bool> isReciprocalSubscribe({
    required String viewerId,
    required String peerId,
  }) async => false;

  @override
  Future<bool> isSubscribedTo({
    required String viewerId,
    required String peerId,
  }) async => false;
}

void main() {
  late QueryInviteGenealogy query;

  setUp(() {
    query = QueryInviteGenealogy(
      inviteGenealogyCase: InviteGenealogyCase(
        _FakeInviteGenealogyRepository(),
        env: Env(environment: Environment.test),
        logger: Logger('QueryInviteGenealogyTest'),
      ),
      meritScoreLookup: _FakeMeritScoreLookup(),
      voteUserFriendshipLookup: _FakeVoteUserFriendshipLookup(),
    );
  });

  Future<Object?> resolveChildren(Map<String, dynamic> args) async {
    final field = query.all.singleWhere(
      (field) => field.name == 'inviteGenealogyChildren',
    );
    return field.resolve!(null, {
      kContextJwtKey: const JwtEntity(sub: 'Uviewer'),
      'node_key': 'G${'a' * 43}',
      ...args,
    });
  }

  Future<Object?> resolveChildCounts(List<String> nodeKeys) async {
    final field = query.all.singleWhere(
      (field) => field.name == 'inviteGenealogyChildCounts',
    );
    return field.resolve!(null, {
      kContextJwtKey: const JwtEntity(sub: 'Uviewer'),
      'node_keys': nodeKeys,
    });
  }

  test('inviteGenealogyChildren rejects a cursor with only created_at', () {
    expect(
      () => resolveChildren({
        'after_created_at': DateTime.utc(2026, 2).toIso8601String(),
      }),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('inviteGenealogyChildren rejects a cursor with only node key', () {
    expect(
      () => resolveChildren({'after_node_key': 'Gafter'}),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('inviteGenealogyChildren rejects malformed or empty cursor values', () {
    expect(
      () => resolveChildren({
        'after_created_at': 'not-a-date',
        'after_node_key': 'Gafter',
      }),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => resolveChildren({
        'after_created_at': DateTime.utc(2026, 2).toIso8601String(),
        'after_node_key': '',
      }),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('inviteGenealogyChildCounts validates every node key', () {
    expect(
      () => resolveChildCounts(['not-a-node-key']),
      throwsA(isA<ArgumentError>()),
    );
  });

  test(
    'inviteGenealogyChildCounts returns rows for requested node keys',
    () async {
      final result = await resolveChildCounts([
        'G${'a' * 43}',
        'G${'b' * 43}',
      ]);

      expect(result, [
        {'node_key': 'G${'a' * 43}', 'total_children': 0},
        {'node_key': 'G${'b' * 43}', 'total_children': 0},
      ]);
    },
  );
}
