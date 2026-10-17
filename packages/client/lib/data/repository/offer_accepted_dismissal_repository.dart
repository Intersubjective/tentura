import 'dart:convert';

import 'package:injectable/injectable.dart';

import 'package:tentura/data/database/database.dart';
import 'package:tentura/domain/attention/offer_accepted_dismissals.dart';

/// B077 — the dismissed «offer accepted» sub-cards, kept in the local
/// settings table as one JSON list.
@Singleton(
  as: OfferAcceptedDismissalPort,
  env: [Environment.dev, Environment.prod],
)
class OfferAcceptedDismissalRepository implements OfferAcceptedDismissalPort {
  OfferAcceptedDismissalRepository(this._database);

  final Database _database;

  static const _kKey = 'offerAcceptedDismissed';

  @override
  Future<Set<String>> load() async {
    final raw = await _database.managers.settings
        .filter((f) => f.key.equals(_kKey))
        .getSingleOrNull()
        .then((v) => v?.valueText);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    return decoded is List ? {for (final k in decoded) '$k'} : {};
  }

  @override
  Future<void> save(Set<String> keys) {
    final encoded = jsonEncode(keys.toList()..sort());
    return _database.managers.settings.create(
      (o) => o(key: _kKey, valueText: Value(encoded)),
      mode: InsertMode.insertOrReplace,
      onConflict: DoUpdate((_) => SettingsCompanion(valueText: Value(encoded))),
    );
  }
}
