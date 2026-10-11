import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_author_invite.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_author_invite.dart';
import 'package:tentura_server/domain/entity/author_invite.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/post_bud.dart';
import 'package:tentura_server/domain/use_case/author_invite_case.dart';

/// Plans C4 and C6: the author-invite mutations and read queries map their
/// input and output faithfully and act as the authenticated user.
void main() {
  const auth = {kGlobalInputQueryJwt: JwtEntity(sub: 'Uactor')};

  late _FakeAuthorInviteCase inviteCase;
  late GraphQL graphQL;

  setUp(() {
    inviteCase = _FakeAuthorInviteCase();
    graphQL = GraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', 'Query root')
          ..fields.add(
            GraphQLObjectField(
              'ping',
              graphQLString,
              resolve: (_, _) => 'pong',
            ),
          )
          ..fields.addAll(QueryAuthorInvite(authorInviteCase: inviteCase).all),
        mutationType: GraphQLObjectType('Mutation', 'Mutation root')
          ..fields.addAll(
            MutationAuthorInvite(authorInviteCase: inviteCase).all,
          ),
      ),
      customTypes: customTypes,
    );
  });

  Future<Map<String, dynamic>> run(String query) async =>
      await graphQL.parseAndExecute(query, globalVariables: auth)
          as Map<String, dynamic>;

  test('beaconAuthorInviteCreate passes the invite and returns the '
      'outcome', () async {
    final result = await run('''
mutation {
  beaconAuthorInviteCreate(beaconId: "Bchild", userId: "Uwarm", note: "van") {
    outcome
    inviteId
  }
}
''');

    expect(result['beaconAuthorInviteCreate'], {
      'outcome': 'invited',
      'inviteId': 'BIinvite',
    });
    expect(inviteCase.calls, [
      ('create', 'Uactor', 'Bchild', 'Uwarm', 'van'),
    ]);
  });

  test('beaconAuthorInviteCreate returns an outcome without an id', () async {
    inviteCase.createOutcome = PostBudInviteOutcome.recipientPaused;
    final result = await run('''
mutation {
  beaconAuthorInviteCreate(beaconId: "Bchild", userId: "Upaused") {
    outcome
    inviteId
  }
}
''');

    expect(result['beaconAuthorInviteCreate'], {
      'outcome': 'recipientPaused',
      'inviteId': null,
    });
    expect(inviteCase.calls.single.$5, isNull);
  });

  for (final (name, method, status) in [
    ('beaconAuthorInviteAccept', 'accept', 'accepted'),
    ('beaconAuthorInviteDecline', 'decline', 'declined'),
    ('beaconAuthorInviteWithdraw', 'withdraw', 'withdrawn'),
  ]) {
    test('$name acts as the caller and returns the invite', () async {
      final result = await run('''
mutation {
  $name(inviteId: "BIinvite") { inviteId beaconId status }
}
''');

      expect(result[name], {
        'inviteId': 'BIinvite',
        'beaconId': 'Bchild',
        'status': status,
      });
      expect(inviteCase.calls, [(method, 'Uactor', 'BIinvite', null, null)]);
    });
  }

  test('myPendingAuthorInvites reads as the caller', () async {
    final result = await run('''
query {
  myPendingAuthorInvites {
    inviteId beaconId beaconTitle inviterId sourcePostId note createdAt
  }
}
''');

    expect(result['myPendingAuthorInvites'], [
      {
        'inviteId': 'BIinvite',
        'beaconId': 'Bchild',
        'beaconTitle': 'Move the piano',
        'inviterId': 'Uauthor',
        'sourcePostId': 'Bpost',
        'note': 'van',
        'createdAt': '2026-10-11T10:00:00.000Z',
      },
    ]);
    expect(inviteCase.calls, [('myPending', 'Uactor', '', null, null)]);
  });

  test('beaconAuthorInvites reads the invites of a Request', () async {
    final result = await run('''
query {
  beaconAuthorInvites(beaconId: "Bchild") {
    inviteId inviteeId status note createdAt
  }
}
''');

    expect(result['beaconAuthorInvites'], [
      {
        'inviteId': 'BIinvite',
        'inviteeId': 'Uactor',
        'status': 'declined',
        'note': 'van',
        'createdAt': '2026-10-11T10:00:00.000Z',
      },
    ]);
    expect(inviteCase.calls, [
      ('beaconInvites', 'Uactor', 'Bchild', null, null),
    ]);
  });
}

final class _FakeAuthorInviteCase extends Fake implements AuthorInviteCase {
  final calls = <(String, String, String, String?, String?)>[];

  PostBudInviteOutcome createOutcome = PostBudInviteOutcome.invited;

  @override
  Future<AuthorInviteCreateResult> create({
    required String actorUserId,
    required String beaconId,
    required String inviteeId,
    String? note,
  }) async {
    calls.add(('create', actorUserId, beaconId, inviteeId, note));
    return AuthorInviteCreateResult(
      outcome: createOutcome,
      inviteId: createOutcome == PostBudInviteOutcome.invited
          ? 'BIinvite'
          : null,
    );
  }

  AuthorInvite _invite(String id, AuthorInviteStatus status) => AuthorInvite(
    id: id,
    beaconId: 'Bchild',
    inviterId: 'Uauthor',
    inviteeId: 'Uactor',
    sourcePostId: 'Bpost',
    forwardEdgeId: 'Fedge',
    warm: true,
    status: status,
  );

  static final _createdAt = DateTime.utc(2026, 10, 11, 10);

  @override
  Future<List<PendingAuthorInvite>> myPendingInvites({
    required String actorUserId,
  }) async {
    calls.add(('myPending', actorUserId, '', null, null));
    return [
      PendingAuthorInvite(
        inviteId: 'BIinvite',
        beaconId: 'Bchild',
        beaconTitle: 'Move the piano',
        inviterId: 'Uauthor',
        sourcePostId: 'Bpost',
        note: 'van',
        createdAt: _createdAt,
      ),
    ];
  }

  @override
  Future<List<AuthorInvite>> beaconInvites({
    required String actorUserId,
    required String beaconId,
  }) async {
    calls.add(('beaconInvites', actorUserId, beaconId, null, null));
    return [
      AuthorInvite(
        id: 'BIinvite',
        beaconId: beaconId,
        inviterId: 'Uauthor',
        inviteeId: 'Uactor',
        sourcePostId: 'Bpost',
        forwardEdgeId: 'Fedge',
        warm: true,
        status: AuthorInviteStatus.declined,
        note: 'van',
        createdAt: _createdAt,
      ),
    ];
  }

  @override
  Future<AuthorInvite> accept({
    required String actorUserId,
    required String inviteId,
  }) async {
    calls.add(('accept', actorUserId, inviteId, null, null));
    return _invite(inviteId, AuthorInviteStatus.accepted);
  }

  @override
  Future<AuthorInvite> decline({
    required String actorUserId,
    required String inviteId,
  }) async {
    calls.add(('decline', actorUserId, inviteId, null, null));
    return _invite(inviteId, AuthorInviteStatus.declined);
  }

  @override
  Future<AuthorInvite> withdraw({
    required String actorUserId,
    required String inviteId,
  }) async {
    calls.add(('withdraw', actorUserId, inviteId, null, null));
    return _invite(inviteId, AuthorInviteStatus.withdrawn);
  }
}
