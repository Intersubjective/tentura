import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';

import 'entity/constellation_field.dart';

/// Supplies the inputs that [Beacon.resolveIdentity] uses in the Request header.
Beacon constellationRequestAsIdentityBeacon(ConstellationRequest request) {
  final coverImage = request.coverImage;
  return Beacon.empty.copyWith(
    id: request.id,
    title: request.title,
    author: Profile(id: request.authorId),
    needs: request.needs.toSet(),
    primaryNeedSlug: request.primaryNeedSlug,
    coverSource: request.coverSource,
    coverThumb: request.coverThumb,
    coverImageId: coverImage?.key,
    images: [?coverImage],
  );
}
