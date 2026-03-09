import 'package:tentura_server/domain/entity/opinion_entity.dart';

import '../database/tentura_db.dart';
import 'user_mapper.dart';

OpinionEntity opinionModelToEntity(
  Opinion model, {
  required User subject,
  required User object,
}) => OpinionEntity(
  id: model.id,
  content: model.content,
  author: userModelToEntity(subject),
  user: userModelToEntity(object),
  createdAt: model.createdAt.dateTime,
);
