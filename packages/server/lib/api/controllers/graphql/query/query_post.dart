import 'package:tentura_server/domain/entity/post_summary.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

/// Viewer-scoped Post conversation summaries.
final class QueryPost extends GqlNodeBase {
  QueryPost({PostCase? postCase}) : _case = postCase ?? GetIt.I<PostCase>();

  final PostCase _case;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [myPosts, postSummary];

  GraphQLObjectField<dynamic, dynamic> get myPosts => GraphQLObjectField(
    'myPosts',
    GraphQLListType(gqlTypePostSummary.nonNullable()).nonNullable(),
    resolve: (_, args) async => [
      for (final post in await _case.myPosts(getCredentials(args).sub))
        _toJson(post),
    ],
  );

  /// One Post's row for the Post screen; null when the viewer is not in it.
  GraphQLObjectField<dynamic, dynamic> get postSummary => GraphQLObjectField(
    'postSummary',
    gqlTypePostSummary,
    arguments: [InputFieldId.field],
    resolve: (_, args) async {
      final post = await _case.postSummary(
        viewerId: getCredentials(args).sub,
        beaconId: InputFieldId.fromArgsNonNullable(args),
      );
      return post == null ? null : _toJson(post);
    },
  );

  static Map<String, Object?> _toJson(PostSummary post) => {
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
    'mutedForever': post.mutedForever,
    'unreadCount': post.unreadCount,
    'isAuthor': post.isAuthor,
  };
}
