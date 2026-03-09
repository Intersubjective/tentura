import 'package:tentura/domain/entity/image_entity.dart';

import '../gql/_g/image_model.data.gql.dart';

extension type const ImageModel(GImageModel i) implements GImageModel {
  ImageEntity get asEntity => ImageEntity(
    id: i.id.value,
    authorId: i.author_id,
    blurHash: i.hash,
    height: i.height,
    width: i.width,
  );
}
