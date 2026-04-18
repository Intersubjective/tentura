import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura_server/utils/id.dart';

import 'user_entity.dart';

part 'beacon_update_entity.freezed.dart';

@freezed
abstract class BeaconUpdateEntity with _$BeaconUpdateEntity {
  static String get newId => generateId('A');

  const factory BeaconUpdateEntity({
    required String id,
    required String beaconId,
    required String authorId,
    required String content,
    required int number,
    required DateTime createdAt,
    UserEntity? author,
  }) = _BeaconUpdateEntity;

  const BeaconUpdateEntity._();
}
