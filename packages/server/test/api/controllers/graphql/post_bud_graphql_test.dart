import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_post_bud.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_post_bud.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/post_bud.dart';
import 'package:tentura_server/domain/entity/post_bud_invite_candidate.dart';
import 'package:tentura_server/domain/use_case/post_bud_case.dart';

/// Plan C3: the `beaconBudFromPost` mutation and the
/// `postBudInviteCandidates` query map their input and output faithfully.
void main() {
  const auth = {kGlobalInputQueryJwt: JwtEntity(sub: 'Ubudder')};

  late _FakePostBudCase budCase;
  late GraphQL graphQL;

  setUp(() {
    budCase = _FakePostBudCase();
    graphQL = GraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', 'Query root')
          ..fields.addAll(QueryPostBud(postBudCase: budCase).all),
        mutationType: GraphQLObjectType('Mutation', 'Mutation root')
          ..fields.addAll(MutationPostBud(postBudCase: budCase).all),
      ),
      customTypes: customTypes,
    );
  });

  test(
    'beaconBudFromPost passes the bud input and returns the result',
    () async {
      final result =
          await graphQL.parseAndExecute(
                r'''
mutation Bud($invitees: [PostBudInviteeInput!]) {
  beaconBudFromPost(
    postId: "Bpost"
    sourceMessageId: "Rmsg"
    clientCommandId: "cmd-1"
    title: "Move the piano"
    description: "Saturday"
    isDiscoverable: true
    closePost: true
    invitees: $invitees
  ) {
    outcome
    childBeaconId
    invitees { userId outcome }
  }
}
''',
                variableValues: {
                  'invitees': [
                    {'userId': 'Uwarm', 'note': 'You have a van'},
                    {'userId': 'Upaused'},
                  ],
                },
                globalVariables: auth,
              )
              as Map<String, dynamic>;

      expect(result['beaconBudFromPost'], {
        'outcome': 'created',
        'childBeaconId': 'Bchild',
        'invitees': [
          {'userId': 'Uwarm', 'outcome': 'invited'},
          {'userId': 'Upaused', 'outcome': 'recipientPaused'},
        ],
      });
      final call = budCase.budCall!;
      expect(call.actorUserId, 'Ubudder');
      expect(call.postId, 'Bpost');
      expect(call.sourceMessageId, 'Rmsg');
      expect(call.clientCommandId, 'cmd-1');
      expect(call.title, 'Move the piano');
      expect(call.description, 'Saturday');
      expect(call.isDiscoverable, isTrue);
      expect(call.closePost, isTrue);
      expect(
        [for (final i in call.invitees) (i.userId, i.note)],
        [('Uwarm', 'You have a van'), ('Upaused', null)],
      );
    },
  );

  test('beaconBudFromPost defaults: not discoverable, no invites, Post stays '
      'open', () async {
    await graphQL.parseAndExecute(
      '''
mutation {
  beaconBudFromPost(
    postId: "Bpost"
    sourceMessageId: "Rmsg"
    clientCommandId: "cmd-1"
    title: "Move the piano"
  ) { outcome }
}
''',
      globalVariables: auth,
    );
    final call = budCase.budCall!;
    expect(call.isDiscoverable, isFalse);
    expect(call.closePost, isFalse);
    expect(call.invitees, isEmpty);
  });

  test('postBudInviteCandidates maps reasons to the outcome enum', () async {
    final result =
        await graphQL.parseAndExecute(
              '''
query {
  postBudInviteCandidates(postId: "Bpost") {
    userId warm outcome pretick viaUserId hasWritten
  }
}
''',
              globalVariables: auth,
            )
            as Map<String, dynamic>;

    expect(budCase.candidatesCall, ('Ubudder', 'Bpost'));
    expect(result['postBudInviteCandidates'], [
      {
        'userId': 'Uwarm',
        'warm': true,
        'outcome': 'invited',
        'pretick': true,
        'viaUserId': 'Uauthor',
        'hasWritten': true,
      },
      {
        'userId': 'Uhidden',
        'warm': false,
        'outcome': 'notEligible',
        'pretick': false,
        'viaUserId': null,
        'hasWritten': false,
      },
    ]);
  });
}

typedef _BudCall = ({
  String actorUserId,
  String postId,
  String? sourceMessageId,
  String clientCommandId,
  String title,
  String? description,
  bool isDiscoverable,
  List<PostBudInvitee> invitees,
  bool closePost,
});

final class _FakePostBudCase extends Fake implements PostBudCase {
  _BudCall? budCall;
  (String, String)? candidatesCall;

  @override
  Future<PostBudResult> budFromPost({
    required String actorUserId,
    required String postId,
    String? sourceMessageId,
    required String clientCommandId,
    required String title,
    String? description,
    String? context,
    String? tags,
    String? needs,
    String? primaryNeedSlug,
    bool primaryNeedSlugProvided = false,
    DateTime? endAt,
    DateTime? startAt,
    Coordinates? coordinates,
    String? addressLabel,
    bool isDiscoverable = false,
    List<PostBudInvitee> invitees = const [],
    bool closePost = false,
  }) async {
    budCall = (
      actorUserId: actorUserId,
      postId: postId,
      sourceMessageId: sourceMessageId,
      clientCommandId: clientCommandId,
      title: title,
      description: description,
      isDiscoverable: isDiscoverable,
      invitees: invitees,
      closePost: closePost,
    );
    return const PostBudResult(
      outcome: 'created',
      childBeaconId: 'Bchild',
      invitees: [
        PostBudInviteeResult(
          userId: 'Uwarm',
          outcome: PostBudInviteOutcome.invited,
        ),
        PostBudInviteeResult(
          userId: 'Upaused',
          outcome: PostBudInviteOutcome.recipientPaused,
        ),
      ],
    );
  }

  @override
  Future<List<PostBudInviteCandidate>> inviteCandidates({
    required String actorUserId,
    required String postId,
  }) async {
    candidatesCall = (actorUserId, postId);
    return const [
      PostBudInviteCandidate(
        userId: 'Uwarm',
        warm: true,
        reason: PostBudInviteReason.eligible,
        hasWritten: true,
        pretick: true,
        viaUserId: 'Uauthor',
      ),
      PostBudInviteCandidate(
        userId: 'Uhidden',
        warm: false,
        reason: PostBudInviteReason.notVisible,
        hasWritten: false,
        pretick: false,
      ),
    ];
  }
}
