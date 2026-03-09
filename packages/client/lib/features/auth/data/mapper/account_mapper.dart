import 'package:tentura/data/database/database.dart';
import 'package:tentura/domain/entity/image_entity.dart';

import '../../domain/entity/account_entity.dart';

AccountEntity accountModelToEntity(Account model) => AccountEntity(
  id: model.id,
  title: model.title,
  fcmTokenUpdatedAt: model.fcmTokenUpdatedAt,
  image: model.imageId.isEmpty
      ? null
      : ImageEntity(
          id: model.imageId,
          blurHash: model.blurHash,
          height: model.height,
          width: model.width,
        ),
);
