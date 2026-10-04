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
  List<PostSummary> result = [];

  @override
  Future<List<PostSummary>> myPosts(String viewerId) async {
    viewers.add(viewerId);
    return result;
  }
}

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
      '{ myPosts { id authorId authorName authorAvatar rootExcerpt '
      'lastMessageExcerpt lastMessageAt lastActivityAt pinnedAt mutedUntil '
      'unreadCount isAuthor } }',
      globalVariables: {kGlobalInputQueryJwt: const JwtEntity(sub: 'Uviewer')},
    );
    expect(response, {
      'myPosts': [
        {
          'id': 'Bpost',
          'authorId': 'Uauthor',
          'authorName': 'Author',
          'authorAvatar': 'https://images.example/avatar.webp',
          'rootExcerpt': 'Root',
          'lastMessageExcerpt': 'Latest',
          'lastMessageAt': '2030-01-03T00:00:00.000Z',
          'lastActivityAt': '2030-01-04T00:00:00.000Z',
          'pinnedAt': '2030-02-01T00:00:00.000Z',
          'mutedUntil': '2030-03-01T00:00:00.000Z',
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
}
