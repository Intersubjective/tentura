import 'dart:convert' show jsonEncode;

import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: HelpOfferRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class HelpOfferRepository implements HelpOfferRepositoryPort {
  const HelpOfferRepository(this._database);

  final TenturaDb _database;

  @override
  Future<void> upsert({
    required String beaconId,
    required String userId,
    String message = '',
    List<String>? helpTypes,
    int status = 0,
  }) => _database.withMutatingUser(userId, () async {
    final helpTypesJson = helpTypes?.isEmpty ?? true
        ? null
        : jsonEncode(helpTypes);
    await _database.into(_database.beaconHelpOffers).insert(
      BeaconHelpOffersCompanion.insert(
        beaconId: beaconId,
        userId: userId,
        message: Value(message),
        helpType: Value(helpTypesJson),
        status: Value(status),
      ),
      onConflict: DoUpdate(
        (_) => BeaconHelpOffersCompanion(
          message: Value(message),
          helpType: Value(helpTypesJson),
          withdrawReason: status == 0
              ? const Value(null)
              : const Value.absent(),
          status: Value(status),
          updatedAt: Value(PgDateTime(DateTime.timestamp())),
        ),
      ),
    );
  });

  @override
  Future<void> withdraw({
    required String beaconId,
    required String userId,
    required String withdrawReason,
    String message = '',
  }) => _database.withMutatingUser(userId, () async {
    await _database.managers.beaconHelpOffers
        .filter(
          (e) => e.beaconId.id(beaconId) & e.userId.id(userId),
        )
        .update(
          (o) => o(
            status: const Value(1),
            message: Value(message),
            withdrawReason: Value(withdrawReason),
            updatedAt: Value(PgDateTime(DateTime.timestamp())),
          ),
        );
  });

  @override
  Future<List<HelpOfferEntity>> fetchByBeaconId(String beaconId) =>
      _database.managers.beaconHelpOffers
          .filter((e) => e.beaconId.id(beaconId) & e.status.equals(0))
          .get()
          .then((rows) => rows.map(_toEntity).toList());

  /// Active and withdrawn rows (status 0 and 1). Used for forward involvement.
  @override
  Future<List<HelpOfferEntity>> fetchAllByBeaconId(String beaconId) =>
      _database.managers.beaconHelpOffers
          .filter((e) => e.beaconId.id(beaconId))
          .get()
          .then((rows) => rows.map(_toEntity).toList());

  @override
  Future<List<HelpOfferEntity>> fetchByUserId(String userId) =>
      _database.managers.beaconHelpOffers
          .filter((e) => e.userId.id(userId) & e.status.equals(0))
          .orderBy((e) => e.updatedAt.desc())
          .get()
          .then((rows) => rows.map(_toEntity).toList());

  @override
  Future<bool> hasActiveHelpOffer({
    required String beaconId,
    required String userId,
  }) async {
    final row = await _database.managers.beaconHelpOffers
        .filter(
          (e) => e.beaconId.id(beaconId) & e.userId.id(userId) & e.status.equals(0),
        )
        .getSingleOrNull();
    return row != null;
  }

  static HelpOfferEntity _toEntity(BeaconHelpOffer row) =>
      HelpOfferEntity(
        beaconId: row.beaconId,
        userId: row.userId,
        message: row.message,
        status: row.status,
        helpType: row.helpType,
        withdrawReason: row.withdrawReason,
        createdAt: row.createdAt.dateTime,
        updatedAt: row.updatedAt.dateTime,
      );
}
