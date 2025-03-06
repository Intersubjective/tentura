import 'package:injectable/injectable.dart';

import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/image_repository.dart';

import '../entity/action_entity.dart';
import '../entity/event_entity.dart';
import '../enum.dart';

@Injectable(order: 2)
class BeaconMutationCase {
  const BeaconMutationCase(this._beaconRepository, this._imageRepository);

  final BeaconRepository _beaconRepository;

  final ImageRepository _imageRepository;

  Future<bool> handleActionDelete(ActionEntity action) async {
    final beacon = await _beaconRepository.getBeaconById(
      action.input['id']! as String,
    );

    if (beacon.author.id != action.userId) {
      throw Exception('Not authorized');
    }

    await _imageRepository.removeBeaconImage(
      authorId: beacon.author.id,
      beaconId: beacon.id,
    );
    await _beaconRepository.deleteBeaconById(beacon.id);

    return true;
  }

  Future<void> handleEvent(EventEntity event) async {
    switch (event.operation) {
      case HasuraOperation.insert:
      case HasuraOperation.manual:
        final beacon = event.newData!;
        if (beacon['has_picture'] == true) {
          final beaconId = beacon['id']! as String;
          await _beaconRepository.updateBeaconBlurHash(
            beaconId: beaconId,
            imageBytes: await _imageRepository.getBeaconImage(
              authorId: beacon['user_id']! as String,
              beaconId: beaconId,
            ),
          );
        }

      case HasuraOperation.delete:
      case HasuraOperation.update:
    }
  }
}
