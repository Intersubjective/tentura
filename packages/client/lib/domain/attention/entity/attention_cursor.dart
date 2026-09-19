import 'dart:convert';

/// The attention cursor contract (U10c).
///
/// A cursor is only meaningful under the sort keys that minted it, so the
/// server refuses anything that is not the current generation rather than
/// resuming from it — resuming would drop or repeat rows without saying so.
///
/// **A client holding a v1 (or unversioned) cursor** must therefore, on the
/// refusal: bump the session's `requestGeneration`, drop every held page
/// cursor, and re-fetch the head. It must never retry the tail with the dead
/// cursor, because that request can only fail again. Carrying the version is
/// this unit's job; U13b implements the reset.
abstract final class AttentionCursorContract {
  /// Mirrors `kAttentionCursorVersion` in the server's `attention_models.dart`.
  static const version = 2;

  /// Substring of the server's `ArgumentError` for a cursor it will not decode.
  static const staleCursorMarker = 'invalid attention cursor';

  /// The generation an opaque cursor was minted under, or `null` when it is
  /// unversioned or undecodable.
  static int? versionOf(String? cursor) {
    if (cursor == null || cursor.isEmpty) return null;
    try {
      final padding = '=' * ((4 - cursor.length % 4) % 4);
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode('$cursor$padding')),
      );
      if (decoded is! Map) return null;
      final raw = decoded['v'];
      return raw is int ? raw : null;
    } on Object {
      return null;
    }
  }

  /// A null cursor is a head fetch, which is always current.
  static bool isCurrent(String? cursor) =>
      cursor == null || versionOf(cursor) == version;

  /// A cursor that *decodes* to an older generation.
  ///
  /// Deliberately narrower than `!isCurrent`: a cursor whose payload this
  /// client cannot read is not evidence of an older generation, and refusing
  /// to send it would break pagination against any future opaque format. Let
  /// the server judge that one — [isStaleCursorError] catches its answer.
  static bool isKnownStale(String? cursor) {
    final decoded = versionOf(cursor);
    return decoded != null && decoded != version;
  }

  /// Whether [error] is the server refusing a cursor from an older generation.
  static bool isStaleCursorError(Object? error) =>
      error != null && '$error'.contains(staleCursorMarker);
}
