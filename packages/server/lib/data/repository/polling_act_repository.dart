import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/polling_act_repository_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: PollingActRepositoryPort,
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class PollingActRepository implements PollingActRepositoryPort {
  const PollingActRepository(this._database);

  final TenturaDb _database;

  @override
  Future<void> upsert({
    required String authorId,
    required String pollingId,
    required List<String> variantIds,
    required String pollType,
    required bool allowRevote,
    int? score,
  }) =>
      _database.transaction(() async {
        switch (pollType) {
          case 'single':
            await _handleSingle(
              authorId: authorId,
              pollingId: pollingId,
              variantId: variantIds.first,
              allowRevote: allowRevote,
            );
          case 'multiple':
            for (final id in variantIds) {
              await _handleMultipleVariant(
                authorId: authorId,
                pollingId: pollingId,
                variantId: id,
                allowRevote: allowRevote,
              );
            }
          case 'range':
            for (final id in variantIds) {
              await _handleRangeVariant(
                authorId: authorId,
                pollingId: pollingId,
                variantId: id,
                allowRevote: allowRevote,
                score: score,
              );
            }
        }
      });

  Future<void> _handleSingle({
    required String authorId,
    required String pollingId,
    required String variantId,
    required bool allowRevote,
  }) async {
    if (!allowRevote) {
      final existing = await (_database.select(_database.pollingActs)
            ..where(
              (a) =>
                  a.pollingId.equals(pollingId) & a.authorId.equals(authorId),
            ))
          .get();
      if (existing.isNotEmpty) return;
    } else {
      await (_database.delete(_database.pollingActs)
            ..where(
              (a) =>
                  a.pollingId.equals(pollingId) & a.authorId.equals(authorId),
            ))
          .go();
    }
    await _database.into(_database.pollingActs).insert(
          PollingActsCompanion.insert(
            authorId: authorId,
            pollingId: pollingId,
            pollingVariantId: variantId,
          ),
        );
  }

  Future<void> _handleMultipleVariant({
    required String authorId,
    required String pollingId,
    required String variantId,
    required bool allowRevote,
  }) async {
    final existing = await (_database.select(_database.pollingActs)
          ..where(
            (a) =>
                a.pollingId.equals(pollingId) &
                a.authorId.equals(authorId) &
                a.pollingVariantId.equals(variantId),
          ))
        .get();

    if (existing.isNotEmpty) {
      if (allowRevote) {
        await (_database.delete(_database.pollingActs)
              ..where(
                (a) =>
                    a.pollingId.equals(pollingId) &
                    a.authorId.equals(authorId) &
                    a.pollingVariantId.equals(variantId),
              ))
            .go();
      }
    } else {
      await _database.into(_database.pollingActs).insert(
            PollingActsCompanion.insert(
              authorId: authorId,
              pollingId: pollingId,
              pollingVariantId: variantId,
            ),
          );
    }
  }

  Future<void> _handleRangeVariant({
    required String authorId,
    required String pollingId,
    required String variantId,
    required bool allowRevote,
    required int? score,
  }) async {
    if (!allowRevote) {
      final existing = await (_database.select(_database.pollingActs)
            ..where(
              (a) =>
                  a.pollingId.equals(pollingId) &
                  a.authorId.equals(authorId) &
                  a.pollingVariantId.equals(variantId),
            ))
          .get();
      if (existing.isNotEmpty) return;
    }
    await _database.into(_database.pollingActs).insertOnConflictUpdate(
          PollingActsCompanion.insert(
            authorId: authorId,
            pollingId: pollingId,
            pollingVariantId: variantId,
            score: Value(score),
          ),
        );
  }
}
