import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';

import 'beacon_fact_cards.dart';
import 'users.dart';

/// Backed by `public.beacon_fact_card_revision` (see `m0199`). No NOTIFY
/// trigger; `(factCardId, seq)` is unique and quoted by room messages.
class BeaconFactCardRevisions extends Table {
  late final id = text()();

  late final factCardId = text().references(
    BeaconFactCards,
    #id,
    onDelete: KeyAction.cascade,
  )();

  late final seq = integer()();

  late final factText = text()();

  @ReferenceName('factRevisionActor')
  late final actorId = text().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// [BeaconFactCardRevisionKindBits]
  late final Column<int> kind = integer()();

  /// Same-fact `seq` this revision restored.
  late final restoredFromSeq = integer().nullable()();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {factCardId, seq},
  ];

  @override
  String get tableName => 'beacon_fact_card_revision';

  @override
  bool get withoutRowId => true;
}
