import 'package:tentura_server/domain/entity/fcm_token_entity.dart';

import '../database/tentura_db.dart';

FcmTokenEntity fcmTokenModelToEntity(FcmToken model) => FcmTokenEntity(
  userId: model.userId,
  appId: model.appId,
  token: model.token,
  platform: model.platform,
  createdAt: model.createdAt.dateTime,
);
