import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordinates.dart';
import '../gql/_g/beacon_model.data.gql.dart';
import 'image_model.dart';
import 'polling_model.dart';
import 'user_model.dart';

extension type const BeaconModel(GBeaconModel i) implements GBeaconModel {
  Beacon toEntity({ImageModel? image}) {
    final author = (i.author as UserModel).toEntity();
    final reviewWindow = i.beacon_review_window;
    return Beacon(
      id: i.id,
      author: author,
      title: i.title,
      lifecycle: BeaconLifecycle.fromSmallint(i.state),
      createdAt: i.created_at,
      updatedAt: i.updated_at,
      description: i.description,
      isPinned: i.is_pinned ?? false,
      context: i.context ?? '',
      myVote: i.my_vote ?? 0,
      coordinates: i.lat == null || i.long == null
          ? Coordinates.zero
          : Coordinates(
              lat: i.lat ?? 0,
              long: i.long ?? 0,
            ),
      rScore: i.scores?.firstOrNull?.src_score ?? 0,
      score: i.scores?.firstOrNull?.dst_score ?? 0,
      polling: (i.polling as PollingModel?)?.toEntity(author: author),
      image: (i.image as ImageModel?)?.asEntity ?? image?.asEntity,
      tags: {
        if (i.tags.isNotEmpty) ...i.tags.split(','),
      },
      startAt: i.start_at,
      endAt: i.end_at,
      reviewClosesAt: reviewWindow?.closes_at,
      reviewWindowStatus: reviewWindow?.status,
    );
  }
}
