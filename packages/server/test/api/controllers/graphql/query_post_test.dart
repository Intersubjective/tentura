import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_post.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/post_summary.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';

final class _Posts extends Fake implements PostCase {
  final viewers = <String>[];
  final summaryCalls = <({String viewerId, String beaconId})>[];
  List<PostSummary> result = [];

  @override
  Future<List<PostSummary>> myPosts(String viewerId) async {
    viewers.add(viewerId);
    return result;
  }

  @override
  Future<PostSummary?> postSummary({
    required String viewerId,
    required String beaconId,
  }) async {
    summaryCalls.add((viewerId: viewerId, beaconId: beaconId));
    return result.where((p) => p.id == beaconId).firstOrNull;
  }
}

PostSummary _summary(String id, {bool mutedForever = false}) => PostSummary(
  id: id,
  authorId: 'Uauthor',
  authorName: 'Author',
  authorAvatar: 'https://images.example/avatar.webp',
  rootExcerpt: 'Root',
  lastMessageExcerpt: null,
  lastMessageAt: null,
  lastActivityAt: null,
  pinnedAt: null,
  mutedUntil: null,
  mutedForever: mutedForever,
  unreadCount: 0,
  isAuthor: false,
);

void main() {
  late _Posts posts;
  late QueryPost query;
  late GraphQL graphQL;
  setUp(() {
    posts = _Posts();
    query = QueryPost(postCase: posts);
    graphQL = GraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', null)..fields.addAll(query.all),
      ),
    );
  });

  test(
    'declares registered PostSummary and a non-null list of non-null rows',
    () {
      expect(query.myPosts.type.toString(), '[PostSummary!]!');
      expect(query.myPosts.inputs, isEmpty);
      expect(customTypes, contains(gqlTypePostSummary));
    },
  );
  test('uses JWT viewer and serializes all summary fields', () async {
    posts.result = [
      PostSummary(
        id: 'Bpost',
        authorId: 'Uauthor',
        authorName: 'Author',
        authorAvatar: 'https://images.example/avatar.webp',
        rootImageUrl: 'https://images.example/root.webp',
        rootExcerpt: 'Root',
        lastMessageExcerpt: 'Latest',
        lastMessageAt: DateTime.utc(2030, 1, 3),
        lastActivityAt: DateTime.utc(2030, 1, 4),
        pinnedAt: DateTime.utc(2030, 2),
        mutedUntil: DateTime.utc(2030, 3),
        unreadCount: 2,
        isAuthor: false,
      ),
    ];
    final response = await graphQL.parseAndExecute(
      '{ myPosts { id authorId authorName authorAvatar rootImageUrl rootExcerpt '
      'lastMessageExcerpt lastMessageAt lastActivityAt pinnedAt mutedUntil '
      'mutedForever unreadCount isAuthor } }',
      globalVariables: {kGlobalInputQueryJwt: const JwtEntity(sub: 'Uviewer')},
    );
    expect(response, {
      'myPosts': [
        {
          'id': 'Bpost',
          'authorId': 'Uauthor',
          'authorName': 'Author',
          'authorAvatar': 'https://images.example/avatar.webp',
          'rootImageUrl': 'https://images.example/root.webp',
          'rootExcerpt': 'Root',
          'lastMessageExcerpt': 'Latest',
          'lastMessageAt': '2030-01-03T00:00:00.000Z',
          'lastActivityAt': '2030-01-04T00:00:00.000Z',
          'pinnedAt': '2030-02-01T00:00:00.000Z',
          'mutedUntil': '2030-03-01T00:00:00.000Z',
          'mutedForever': false,
          'unreadCount': 2,
          'isAuthor': false,
        },
      ],
    });
    expect(posts.viewers, ['Uviewer']);
  });
  test('returns an empty list for a viewer with no Posts', () async {
    final response = await graphQL.parseAndExecute(
      '{ myPosts { id } }',
      globalVariables: {kGlobalInputQueryJwt: const JwtEntity(sub: 'Uviewer')},
    );
    expect(response, {'myPosts': <Object>[]});
  });
  test('rejects unauthenticated requests before reading summaries', () async {
    await expectLater(
      graphQL.parseAndExecute('{ myPosts { id } }'),
      throwsA(isA<UnauthorizedException>()),
    );
    expect(posts.viewers, isEmpty);
  });
  test('postSummary takes an id and returns a nullable PostSummary', () {
    expect(query.postSummary.type.toString(), 'PostSummary');
    expect(query.postSummary.inputs.map((i) => i.name), ['id']);
  });
  test("postSummary returns the viewer's row for that Post", () async {
    const id = 'Bpostsummary1';
    posts.result = [_summary(id, mutedForever: true)];
    final response = await graphQL.parseAndExecute(
      '{ postSummary(id: "$id") { id mutedUntil mutedForever } }',
      globalVariables: {kGlobalInputQueryJwt: const JwtEntity(sub: 'Uviewer')},
    );
    expect(response, {
      'postSummary': {'id': id, 'mutedUntil': null, 'mutedForever': true},
    });
    expect(posts.summaryCalls, [(viewerId: 'Uviewer', beaconId: id)]);
  });
  test('postSummary is null when the viewer is not in the Post', () async {
    final response = await graphQL.parseAndExecute(
      '{ postSummary(id: "Bpostsummary2") { id } }',
      globalVariables: {kGlobalInputQueryJwt: const JwtEntity(sub: 'Uviewer')},
    );
    expect(response, {'postSummary': null});
  });
}
