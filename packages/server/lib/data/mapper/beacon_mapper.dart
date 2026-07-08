import 'package:tentura_root/domain/entity/beacon_status.dart';
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
  status: BeaconStatus.fromSmallint(model.status),
  statusChangedAt: model.statusChangedAt?.dateTime,
  description: model.description,
  author: userModelToEntity(author),
  createdAt: model.createdAt.dateTime,
  updatedAt: model.updatedAt.dateTime,
  startAt: model.startAt?.dateTime,
  endAt: model.endAt?.dateTime,
  coordinates: model.lat != null && model.long != null
      ? Coordinates(lat: model.lat!, long: model.long!)
      : null,
  addressLabel: model.addressLabel,
  images: images?.map(imageModelToEntity).toList() ?? const [],
  tags: model.tags.split(',').toSet(),
  needs: model.needs.isEmpty
      ? const <String>{}
      : model.needs.split(',').toSet(),
  iconCode: model.iconCode,
  iconBackground: model.iconBackground,
  lineageParentBeaconId: model.lineageParentBeaconId,
  lineageRootBeaconId: model.lineageRootBeaconId,
);
