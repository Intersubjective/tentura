import 'package:tentura/features/comment/domain/entity/comment.dart';
import 'package:tentura/features/profile/data/model/user_model.dart';

import '../gql/_g/comment_model.data.gql.dart';

extension type const CommentModel(GCommentModel i) implements GCommentModel {
  Comment get toEntity => Comment(
        id: i.id,
        content: i.content,
        beaconId: i.beacon_id,
        createdAt: i.created_at,
        myVote: i.my_vote ?? 0,
        author: (i.author as UserModel).toEntity,
      );
}
