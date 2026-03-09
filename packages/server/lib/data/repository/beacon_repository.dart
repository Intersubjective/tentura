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
    String? imageId,
    double? latitude,
    double? longitude,
    DateTime? startAt,
    DateTime? endAt,
    ({String question, List<String> variants})? polling,
    Set<String>? tags,
    int ticker = 0,
  }) async {
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
        imageId: Value(imageId == null ? null : UuidValue.fromString(imageId)),
        startAt: Value(startAt == null ? null : PgDateTime(startAt)),
        endAt: Value(endAt == null ? null : PgDateTime(endAt)),
        pollingId: Value(pollingModel?.id),
        tags: Value.absentIfNull(tags?.join(',')),
      ),
    );

    final author = await _database.managers.users
        .filter((e) => e.id.equals(authorId))
        .getSingle();

    final pollingVariants = pollingModel == null
        ? null
        : await _database.managers.pollingVariants
              .filter((e) => e.pollingId.id(pollingModel.id))
              .get();

    return beaconModelToEntity(
      beacon,
      author: author,
      polling: pollingModel,
      variants: pollingVariants,
    );
  }

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

    return beaconModelToEntity(
      beacon,
      author: await author.userId.getSingle(),
    );
  }

  Future<void> deleteBeaconById(String id) =>
      _database.managers.beacons.filter((e) => e.id.equals(id)).delete();
}
