import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'package:tentura_server/domain/entity/comment_entity.dart';

import 'avatar_component.dart';

class CommentViewComponent extends StatelessComponent {
  const CommentViewComponent({
    required this.comment,
  });

  final CommentEntity comment;

  @override
  Component build(BuildContext context) => section(
    [
      AvatarComponent(user: comment.author),

      p(
        [
          Component.text(comment.content),
        ],
      ),
    ],
  );
}
