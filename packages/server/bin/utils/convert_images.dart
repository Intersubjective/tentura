import 'package:tentura_server/env.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';

Future<void> convertImages([Env? env]) async {
  final getIt = await configureDependencies(env ?? Env.prod());
  final database = getIt<TenturaDb>();
  final remoteStorage = getIt<RemoteStoragePort>();

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

  // beacon.image_id was removed in m0029; beacon images are now in
  // the beacon_image join table — no legacy conversion needed.

  await getIt.reset();
}
