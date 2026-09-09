import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';

import 'entity/constellation_field.dart';

/// Thin identity projection for [BeaconIdentityTile] on the field map.
Beacon constellationRequestAsIdentityBeacon(ConstellationRequest request) =>
    Beacon.empty.copyWith(
      id: request.id,
      title: request.title,
      author: Profile(id: request.authorId),
      needs: request.needs.toSet(),
      primaryNeedSlug: request.primaryNeedSlug,
      coverSource: request.coverSource,
      coverThumb: request.coverThumb,
    );
