import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';

import '../database/tentura_db.dart';
import 'image_mapper.dart';
import 'user_mapper.dart';

BeaconEntity beaconModelToEntity(
  Beacon model, {
  required User author,
  List<Image>? images,
}) => BeaconEntity(
  id: model.id,
  title: model.title,
  context: model.context,
  state: model.state,
  description: model.description,
  author: userModelToEntity(author),
  createdAt: model.createdAt.dateTime,
  updatedAt: model.updatedAt.dateTime,
  startAt: model.startAt?.dateTime,
  endAt: model.endAt?.dateTime,
  coordinates: model.lat != null && model.long != null
      ? Coordinates(lat: model.lat!, long: model.long!)
      : null,
  images: images?.map(imageModelToEntity).toList() ?? const [],
  tags: model.tags.split(',').toSet(),
  iconCode: model.iconCode,
  iconBackground: model.iconBackground,
  needSummary: model.needSummary,
  successCriteria: model.successCriteria,
  publicStatus: model.publicStatus,
  lastPublicMeaningfulChange: model.lastPublicMeaningfulChange,
);
