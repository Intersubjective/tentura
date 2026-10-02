import 'package:drift/drift.dart';

import 'package:tentura_server/domain/entity/polling_variant_entity.dart';

import 'pollings.dart';

class PollingVariants extends Table {
  late final id = text().clientDefault(() => PollingVariantEntity.newId)();

  late final pollingId = text().references(Pollings, #id)();

  late final description = text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'polling_variant';
}
