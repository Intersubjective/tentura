import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/enum.dart';

import '../database/tentura_db.dart';
import 'image_mapper.dart';

UserEntity userModelToEntity(User model, {Image? image}) => UserEntity(
  id: model.id,
  title: model.title,
  publicKey: model.publicKey,
  description: model.description,
  image: image == null ? null : imageModelToEntity(image),
  privileges: model.privileges == null
      ? null
      : {
          for (final p in model.privileges! as List<dynamic>)
            UserPrivileges.values.firstWhere((e) => e.name == p),
        },
);
