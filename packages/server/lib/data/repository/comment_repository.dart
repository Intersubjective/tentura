import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/comment_entity.dart';

import '../database/tentura_db.dart';
import '../mapper/comment_mapper.dart';

export 'package:tentura_server/domain/entity/comment_entity.dart';

@Injectable(
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class CommentRepository {
  CommentRepository(this._database);

  final TenturaDb _database;

  Future<CommentEntity> createComment({
    required String authorId,
    required String beaconId,
    required String content,
    int ticker = 0,
  }) async {
    final comment = await _database.managers.comments.createReturning(
      (o) => o(userId: authorId, beaconId: beaconId, content: content),
    );
    return getCommentById(comment.id);
  }

  Future<CommentEntity> getCommentById(String id) async {
    final (comment, commentRefs) = await _database.managers.comments
        .filter((e) => e.id.equals(id))
        .withReferences((p) => p(userId: true, beaconId: true))
        .getSingle();
    final (beacon, beaconRefs) = await commentRefs.beaconId
        .withReferences((p) => p(userId: true))
        .getSingle();
    return commentModelToEntity(
      comment,
      beacon: beacon,
      beaconAuthor: await beaconRefs.userId.getSingle(),
      commentAuthor: await commentRefs.userId.getSingle(),
    );
  }
}
