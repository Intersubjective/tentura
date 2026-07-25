import 'package:tentura/domain/entity/image_entity.dart';

import '../gql/_g/image_model_v2.data.gql.dart';

extension type const ImageModelV2(GImageModelV2 i) implements GImageModelV2 {
  ImageEntity get asEntity => ImageEntity(
    id: i.id,
    authorId: i.author_id,
    blurHash: i.hash,
    height: i.height,
    width: i.width,
  );
}
