import 'package:tentura_server/domain/entity/image_entity.dart';

import '../database/tentura_db.dart';

ImageEntity imageModelToEntity(Image model) => ImageEntity(
  id: model.id.uuid,
  authorId: model.authorId,
  blurHash: model.hash,
  height: model.height,
  width: model.width,
);
