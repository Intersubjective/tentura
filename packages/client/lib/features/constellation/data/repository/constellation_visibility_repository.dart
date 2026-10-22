import 'dart:convert';

import 'package:injectable/injectable.dart';

import 'package:tentura/data/database/database.dart';

import '../../domain/constellation_visibility.dart';
import '../../domain/port/constellation_visibility_port.dart';

/// Local (Drift settings) store of the field's show/hide toggles (#645).
@LazySingleton(
  as: ConstellationVisibilityPort,
  env: [Environment.dev, Environment.prod],
)
class ConstellationVisibilityRepository implements ConstellationVisibilityPort {
  ConstellationVisibilityRepository(this._database);

  final Database _database;

  static String storageKey(String viewerId) =>
      'constellation:visibility:$viewerId';

  @override
  Future<ConstellationVisibility?> read({required String viewerId}) async {
    final raw = await _database.managers.settings
        .filter((f) => f.key.equals(storageKey(viewerId)))
        .getSingleOrNull()
        .then((v) => v?.valueText);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return ConstellationVisibility.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write({
    required String viewerId,
    required ConstellationVisibility visibility,
  }) {
    final encoded = jsonEncode(visibility.toJson());
    return _database.managers.settings.create(
      (o) => o(key: storageKey(viewerId), valueText: Value(encoded)),
      mode: InsertMode.insertOrReplace,
      onConflict: DoUpdate((_) => SettingsCompanion(valueText: Value(encoded))),
    );
  }
}
