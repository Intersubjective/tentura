import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/exception.dart';

/// Guards for operations that only make sense on a Request, not on a Post.
abstract final class BeaconKindPolicy {
  BeaconKindPolicy._();

  static void requireRequest(BeaconEntity b) {
    if (b.kind != BeaconKind.request) throw const BeaconNotRequestException();
  }
}
