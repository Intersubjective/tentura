import 'package:get_it/get_it.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/entity/user_presence_entity.dart';

import '../database/tentura_db.dart';

UserPresenceEntity userPresenceModelToEntity(UserPresenceData model) =>
    UserPresenceEntity(
      userId: model.userId,
      status: model.status,
      lastSeenAt: model.lastSeenAt.dateTime,
      lastNotifiedAt: model.lastNotifiedAt.dateTime,
      offlineAfterDelay: GetIt.I<Env>().chatStatusOfflineAfterDelay,
    );
