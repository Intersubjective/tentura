import 'package:tentura_server/domain/entity/polling_entity.dart';
import 'package:tentura_server/domain/entity/polling_variant_entity.dart';

import '../database/tentura_db.dart';
import 'user_mapper.dart';

PollingEntity pollingModelToEntity(
  Polling model, {
  required User author,
  List<PollingVariant>? variants,
}) => PollingEntity(
  id: model.id,
  question: model.question,
  isEnabled: model.isEnabled,
  author: userModelToEntity(author),
  createdAt: model.createdAt.dateTime,
  updatedAt: model.updatedAt.dateTime,
  variants:
      variants
          ?.map(
            (e) => PollingVariantEntity(
              id: e.id,
              pollingId: e.pollingId,
              description: e.description,
            ),
          )
          .toList() ??
      [],
);
