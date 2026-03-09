import 'package:tentura_server/env.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/storage/remote_storage.dart';

Future<void> convertImages([Env? env]) async {
  final getIt = await configureDependencies(env ?? Env.prod());
  final database = getIt<TenturaDb>();
  final remoteStorage = getIt<RemoteStorage>();

  final users = await database.managers.users
      .filter((e) => e.imageId.id.isNotNull())
      .get();
  print('Found ${users.length} users');

  try {
    for (final user in users) {
      await remoteStorage.putObject(
        '$kImagesPath/${user.id}/${user.imageId!.uuid}.$kImageExt',
        Stream.fromFuture(
          remoteStorage.getObject(
            '$kImagesPath/${user.id}/avatar.$kImageExt',
          ),
        ),
      );
    }
  } catch (e) {
    print(e);
  }

  final beacons = await database.managers.beacons
      .filter((e) => e.imageId.id.isNotNull())
      .get();
  print('Found ${beacons.length} beacons');

  try {
    for (final beacon in beacons) {
      await remoteStorage.putObject(
        '$kImagesPath/${beacon.userId}/${beacon.imageId!.uuid}.$kImageExt',
        Stream.fromFuture(
          remoteStorage.getObject(
            '$kImagesPath/${beacon.userId}/${beacon.id}.$kImageExt',
          ),
        ),
      );
    }
  } catch (e) {
    print(e);
  }

  await getIt.reset();
}
