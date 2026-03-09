import 'package:tentura_server/domain/entity/comment_entity.dart';

import '../database/tentura_db.dart';
import 'beacon_mapper.dart';
import 'user_mapper.dart';

CommentEntity commentModelToEntity(
  Comment model, {
  required Beacon beacon,
  required User beaconAuthor,
  required User commentAuthor,
}) => CommentEntity(
  id: model.id,
  content: model.content,
  createdAt: model.createdAt.dateTime,
  author: userModelToEntity(beaconAuthor),
  beacon: beaconModelToEntity(beacon, author: beaconAuthor),
);
