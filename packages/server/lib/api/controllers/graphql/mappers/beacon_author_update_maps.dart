import 'package:tentura_server/domain/entity/beacon_update_entity.dart';
import 'package:tentura_server/domain/entity/gql_public/image_public_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';

UserPublicRecord userEntityToPublicRecord(UserEntity u) {
  ImagePublicRecord? imageRecord;
  final img = u.image;
  if (img != null) {
    imageRecord = ImagePublicRecord(
      id: img.id,
      hash: img.blurHash,
      height: img.height,
      width: img.width,
      authorId: img.authorId,
      createdAt: img.createdAt.toUtc(),
    );
  }
  return UserPublicRecord(
    id: u.id,
    title: u.title,
    description: u.description,
    image: imageRecord,
  );
}

Map<String, Object?> beaconAuthorUpdateToGqlMap(
  BeaconUpdateEntity e,
  Map<String, dynamic> authorMap,
) => {
  'id': e.id,
  'beaconId': e.beaconId,
  'number': e.number,
  'content': e.content,
  'createdAt': e.createdAt.toUtc(),
  'author': authorMap,
};
