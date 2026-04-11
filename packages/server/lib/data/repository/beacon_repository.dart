import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart' show PgDateTime, UuidValue;

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/polling_entity.dart';

import '../database/tentura_db.dart';
import '../mapper/beacon_mapper.dart';

export 'package:tentura_server/domain/entity/beacon_entity.dart';

@Injectable(
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class BeaconRepository {
  const BeaconRepository(this._database);

  final TenturaDb _database;

  Future<BeaconEntity> createBeacon({
    required String authorId,
    required String title,
    String? description,
    String? context,
    List<String>? imageIds,
    double? latitude,
    double? longitude,
    DateTime? startAt,
    DateTime? endAt,
    ({String question, List<String> variants})? polling,
    Set<String>? tags,
    int ticker = 0,
    String? iconCode,
    int? iconBackground,
  }) => _database.withMutatingUser(authorId, () async {
    final pollingModel = polling == null
        ? null
        : await _database.transaction<Polling>(() async {
            final pollingModel = await _database.managers.pollings
                .createReturning(
                  (o) => o(
                    id: Value(PollingEntity.newId),
                    authorId: authorId,
                    question: polling.question,
                  ),
                );
            await _database.managers.pollingVariants.bulkCreate(
              (o) => polling.variants.map(
                (e) => o(pollingId: pollingModel.id, description: e),
              ),
            );
            return pollingModel;
          });

    final beacon = await _database.managers.beacons.createReturning(
      (o) => o(
        userId: authorId,
        title: title,
        context: Value(context),
        description: Value(description ?? ''),
        ticker: Value(ticker),
        lat: Value(latitude),
        long: Value(longitude),
        startAt: Value(startAt == null ? null : PgDateTime(startAt)),
        endAt: Value(endAt == null ? null : PgDateTime(endAt)),
        pollingId: Value(pollingModel?.id),
        tags: Value.absentIfNull(tags?.join(',')),
        iconCode: Value(iconCode),
        iconBackground: Value(iconBackground),
      ),
    );

    if (imageIds != null && imageIds.isNotEmpty) {
      await _database.managers.beaconImages.bulkCreate(
        (o) => [
          for (var i = 0; i < imageIds.length; i++)
            o(
              beaconId: beacon.id,
              imageId: UuidValue.fromString(imageIds[i]),
              position: Value(i),
            ),
        ],
      );
    }

    final author = await _database.managers.users
        .filter((e) => e.id.equals(authorId))
        .getSingle();

    final pollingVariants = pollingModel == null
        ? null
        : await _database.managers.pollingVariants
              .filter((e) => e.pollingId.id(pollingModel.id))
              .get();

    final images = await _getBeaconImages(beacon.id);

    return beaconModelToEntity(
      beacon,
      author: author,
      images: images,
      polling: pollingModel,
      variants: pollingVariants,
    );
  });

  ///
  /// Query Beacon by beaconId, filter by userId if set
  ///
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async {
    final (beacon, author) = await _database.managers.beacons
        .filter(
          filterByUserId == null
              ? (e) => e.id.equals(beaconId)
              : (e) =>
                    e.id.equals(beaconId) & e.userId.id.equals(filterByUserId),
        )
        .withReferences((p) => p(userId: true))
        .getSingle();

    final images = await _getBeaconImages(beaconId);

    return beaconModelToEntity(
      beacon,
      author: await author.userId.getSingle(),
      images: images,
    );
  }

  Future<void> deleteBeaconById(String id, {required String userId}) =>
      _database.withMutatingUser(userId, () async {
        await _database.managers.beacons
            .filter((e) => e.id.equals(id))
            .delete();
      });

  Future<void> updateBeaconState({
    required String beaconId,
    required int state,
  }) => _database.managers.beacons
      .filter((e) => e.id.equals(beaconId))
      .update((o) => o(state: Value(state)));

  Future<void> addImage({
    required String beaconId,
    required String imageId,
    required int position,
  }) => _database.managers.beaconImages.create(
    (o) => o(
      beaconId: beaconId,
      imageId: UuidValue.fromString(imageId),
      position: Value(position),
    ),
  );

  Future<void> removeImage({
    required String beaconId,
    required String imageId,
  }) => _database.managers.beaconImages
      .filter(
        (e) =>
            e.beaconId.id.equals(beaconId) &
            e.imageId.id(UuidValue.fromString(imageId)),
      )
      .delete();

  Future<int> getImageCount(String beaconId) =>
      _database.managers.beaconImages
          .filter((e) => e.beaconId.id.equals(beaconId))
          .count();

  Future<void> reorderImages({
    required String beaconId,
    required List<String> imageIds,
  }) async {
    for (var i = 0; i < imageIds.length; i++) {
      await _database.managers.beaconImages
          .filter(
            (e) =>
                e.beaconId.id.equals(beaconId) &
                e.imageId.id(UuidValue.fromString(imageIds[i])),
          )
          .update((o) => o(position: Value(i)));
    }
  }

  Future<List<Image>> _getBeaconImages(String beaconId) async {
    final beaconImageRows = await _database.managers.beaconImages
        .filter((e) => e.beaconId.id.equals(beaconId))
        .orderBy((e) => e.position.asc())
        .get();

    if (beaconImageRows.isEmpty) return const [];

    final imageIds = beaconImageRows.map((e) => e.imageId).toList();
    final imageRows = await _database.managers.images
        .filter((e) => e.id.isIn(imageIds))
        .get();

    final imageMap = {for (final img in imageRows) img.id: img};
    return [
      for (final bi in beaconImageRows)
        ?imageMap[bi.imageId],
    ];
  }
}
