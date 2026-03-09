import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';

import '../database/tentura_db.dart';
import 'image_mapper.dart';
import 'polling_mapper.dart';
import 'user_mapper.dart';

BeaconEntity beaconModelToEntity(
  Beacon model, {
  required User author,
  Image? image,
  Polling? polling,
  List<PollingVariant>? variants,
}) => BeaconEntity(
  id: model.id,
  title: model.title,
  context: model.context,
  isEnabled: model.isEnabled,
  description: model.description,
  author: userModelToEntity(author),
  createdAt: model.createdAt.dateTime,
  updatedAt: model.updatedAt.dateTime,
  startAt: model.startAt?.dateTime,
  endAt: model.endAt?.dateTime,
  coordinates: model.lat != null && model.long != null
      ? Coordinates(lat: model.lat!, long: model.long!)
      : null,
  image: image == null ? null : imageModelToEntity(image),
  polling: polling == null
      ? null
      : pollingModelToEntity(polling, author: author, variants: variants),
  tags: model.tags.split(',').toSet(),
);
