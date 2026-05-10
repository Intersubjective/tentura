import 'dart:convert';

import 'package:tentura/domain/capability/capability_tag.dart';

/// Parses `beacon_commitment.help_type`: JSON-encoded slug list from the server
/// upsert path, or a legacy single slug. Returns slugs known to CapabilityTag.
Set<String> commitmentStoredHelpTypeSlugs(String? helpType) {
  if (helpType == null || helpType.trim().isEmpty) return {};
  final raw = helpType.trim();
  if (raw.startsWith('[')) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final out = <String>{};
        for (final e in decoded) {
          if (e is! String) continue;
          final s = e.trim();
          if (s.isEmpty) continue;
          if (CapabilityTag.fromSlug(s) != null) out.add(s);
        }
        return out;
      }
    } on Object {
      return {};
    }
  }
  if (CapabilityTag.fromSlug(raw) != null) return {raw};
  return {};
}

/// Drop unknown slugs before commit (defensive).
List<String>? normalizeCommitHelpTypesWire(List<String>? wire) {
  if (wire == null || wire.isEmpty) return null;
  final out = <String>[];
  for (final s in wire) {
    final t = s.trim();
    if (t.isEmpty) continue;
    if (CapabilityTag.fromSlug(t) != null) out.add(t);
  }
  return out.isEmpty ? null : out;
}
