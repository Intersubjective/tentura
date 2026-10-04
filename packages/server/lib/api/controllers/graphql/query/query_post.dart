import 'package:tentura_server/domain/use_case/post_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';

/// Viewer-scoped Post conversation summaries.
final class QueryPost extends GqlNodeBase {
  QueryPost({PostCase? postCase}) : _case = postCase ?? GetIt.I<PostCase>();

  final PostCase _case;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [myPosts];

  GraphQLObjectField<dynamic, dynamic> get myPosts => GraphQLObjectField(
    'myPosts',
    GraphQLListType(gqlTypePostSummary.nonNullable()).nonNullable(),
    resolve: (_, args) async => [
      for (final post in await _case.myPosts(getCredentials(args).sub))
        {
          'id': post.id,
          'authorId': post.authorId,
          'authorName': post.authorName,
          'authorAvatar': post.authorAvatar,
          'rootImageUrl': post.rootImageUrl,
          'rootExcerpt': post.rootExcerpt,
          'lastMessageExcerpt': post.lastMessageExcerpt,
          'lastMessageAt': post.lastMessageAt?.toUtc().toIso8601String(),
          'lastActivityAt': post.lastActivityAt?.toUtc().toIso8601String(),
          'pinnedAt': post.pinnedAt?.toUtc().toIso8601String(),
          'mutedUntil': post.mutedUntil?.toUtc().toIso8601String(),
          'unreadCount': post.unreadCount,
          'isAuthor': post.isAuthor,
        },
    ],
  );
}
