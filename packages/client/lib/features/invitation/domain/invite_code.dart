import 'package:tentura/consts.dart';

/// Strips surrounding whitespace and trailing `-` from pasted or URL fragments
/// (e.g. `I806d29daebbe-` → `I806d29daebbe`).
String normalizeInviteCode(String raw) {
  var code = raw.trim();
  while (code.endsWith('-')) {
    code = code.substring(0, code.length - 1);
  }
  return code;
}

bool isValidInviteCode(String code) {
  final match = kInvitationCodeRegExp.firstMatch(code);
  return match != null && match.start == 0 && match.end == code.length;
}

/// True when [raw] ends with `-` after trim (helps explain a common paste typo).
bool inviteCodeHadTrailingDash(String raw) => raw.trim().endsWith('-');

final _invitePathInText = RegExp(r'/invite/([^/?#\s]+)');

/// Extracts and normalizes an invite code from raw text, a `/invite/…` URL, or
/// a `?id=I…` query fragment. Returns null when nothing valid is found.
String? extractInviteCodeFromText(String text, {String prefix = ''}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final direct = normalizeInviteCode(trimmed);
  if (direct.startsWith(prefix) && isValidInviteCode(direct)) {
    return direct;
  }

  final pathMatch = _invitePathInText.firstMatch(trimmed);
  if (pathMatch != null) {
    String segment;
    try {
      segment = Uri.decodeComponent(pathMatch.group(1)!);
    } catch (_) {
      return null;
    }
    final fromUrl = normalizeInviteCode(segment.split(RegExp('[?#]')).first);
    if (fromUrl.startsWith(prefix) && isValidInviteCode(fromUrl)) {
      return fromUrl;
    }
  }

  try {
    final id = Uri.dataFromString(trimmed).queryParameters['id'];
    if (id != null) {
      final fromQuery = normalizeInviteCode(id);
      if (fromQuery.startsWith(prefix) && isValidInviteCode(fromQuery)) {
        return fromQuery;
      }
    }
  } catch (_) {}

  return null;
}

final _entityIdExact = RegExp(r'^[UBCI][0-9a-f]{12}$');
final _entityIdInPath = RegExp(
  r'/(?:invite|profile/view|beacon/view)/([UBCI][0-9a-f]{12})(?![0-9a-f])',
);

/// Extracts a profile / request / invite id (`U`/`B`/`C`/`I` + 12 hex) from a
/// bare id, a share link (`/profile/view/U…`, `/beacon/view/B…`,
/// `/invite/I…`, also behind `#/` hash routing) or a legacy `?id=` query.
///
/// Used by the connect sheet for typed, pasted and QR-scanned input: a
/// scanned profile QR is the full link, not the bare id.
String? extractEntityIdFromText(String text) {
  final trimmed = normalizeInviteCode(text);
  if (trimmed.isEmpty) return null;
  if (_entityIdExact.hasMatch(trimmed)) return trimmed;

  final pathMatch = _entityIdInPath.firstMatch(trimmed);
  if (pathMatch != null) return pathMatch.group(1);

  try {
    final id = Uri.parse(trimmed).queryParameters['id'];
    if (id != null) {
      final normalized = normalizeInviteCode(id);
      if (_entityIdExact.hasMatch(normalized)) return normalized;
    }
  } on FormatException catch (_) {}
  return null;
}
