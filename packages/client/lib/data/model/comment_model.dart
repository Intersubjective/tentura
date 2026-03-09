import 'package:tentura/domain/entity/comment.dart';
import 'package:tentura/data/model/user_model.dart';

import '../gql/_g/comment_model.data.gql.dart';

extension type const CommentModel(GCommentModel i) implements GCommentModel {
  Comment get asEntity => Comment(
    id: i.id,
    content: i.content,
    beaconId: i.beacon_id,
    createdAt: i.created_at,
    myVote: i.my_vote ?? 0,
    author: (i.author as UserModel).toEntity(),
    score: double.tryParse(i.scores?.first.dst_score?.value ?? '') ?? 0,
  );
}
