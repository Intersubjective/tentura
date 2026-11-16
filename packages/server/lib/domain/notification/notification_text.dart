import 'package:characters/characters.dart';

/// Pure text helpers shared by every notification channel
/// (docs/plans/notification-identity-spec.md §4.3–4.4).
abstract final class NotificationText {
  static const _ellipsis = '…';

  static const _enMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _ruMonths = [
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня', //
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];

  /// Same words as the client `beaconLifecycle*` ARB keys.
  static const _statusLabels = <String, (String, String)>{
    'open': ('Open', 'Открыт'),
    'closed': ('Closed', 'Закрыт'),
    'deleted': ('Deleted', 'Удалён'),
    'draft': ('Draft', 'Черновик'),
    'cancelled': ('Cancelled', 'Отменён'),
    'reviewOpen': ('Final check', 'Подводим итоги'),
  };

  static bool _isRu(String locale) => locale.startsWith('ru');

  static bool _isPictographic(int rune) => rune >= 0x203C;

  /// Strips control, bidi and zero-width characters, collapses whitespace.
  static String normalize(String input) {
    final runes = input.runes.toList();
    final out = StringBuffer();
    for (var i = 0; i < runes.length; i++) {
      final r = runes[i];
      final isWhitespaceControl = r >= 0x09 && r <= 0x0D;
      final isControl = r <= 0x1F || (r >= 0x7F && r <= 0x9F);
      if (isControl && !isWhitespaceControl) continue;
      if ((r >= 0x202A && r <= 0x202E) ||
          (r >= 0x2066 && r <= 0x2069) ||
          r == 0x200E ||
          r == 0x200F ||
          r == 0x200B) {
        continue;
      }
      if (r == 0x200D) {
        final keep =
            i > 0 &&
            i + 1 < runes.length &&
            _isPictographic(runes[i - 1]) &&
            _isPictographic(runes[i + 1]);
        if (!keep) continue;
      }
      out.writeCharCode(r);
    }
    return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Cuts to at most [limit] grapheme clusters, ellipsis included.
  static String truncate(String input, int limit) {
    final chars = input.characters;
    if (chars.length <= limit) return input;
    final keep = limit - 1;
    final head = chars.take(keep + 1).toList();
    final windowStart = (limit * 0.7).ceil();
    var cut = keep;
    for (var i = keep; i >= windowStart; i--) {
      if (head[i] == ' ') {
        cut = i;
        break;
      }
    }
    return '${head.take(cut).join().trimRight()}$_ellipsis';
  }

  /// `«label»`; the label is truncated to [limit] first, never the quotes.
  static String quote(String label, String locale, {int? limit}) =>
      '«${limit == null ? label : truncate(label, limit)}»';

  /// CLDR plural selection for `ru*` (one/few/many) and everything else
  /// (one/other, where other is [many]).
  static String plural(
    int n,
    String locale, {
    required String one,
    required String few,
    required String many,
  }) {
    if (!_isRu(locale)) return n == 1 ? one : many;
    final m10 = n % 10;
    final m100 = n % 100;
    if (m10 == 1 && m100 != 11) return one;
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
    return many;
  }

  /// `21 Nov, 18:00` / `21 ноября, 18:00`; year only when it differs from
  /// the current local year.
  static String formatDate(
    DateTime at,
    String locale, {
    required int tzOffsetMinutes,
    required DateTime now,
  }) {
    final offset = Duration(minutes: tzOffsetMinutes);
    final local = at.toUtc().add(offset);
    final year = now.toUtc().add(offset).year;
    final month = (_isRu(locale) ? _ruMonths : _enMonths)[local.month - 1];
    final yearPart = local.year == year ? '' : ' ${local.year}';
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day} $month$yearPart, $hh:$mm';
  }

  /// A relative duration, never a clock time (plan K16): `15 min`, `1 h 5 min`.
  static String minutes(int? minutes, String locale) {
    final ru = _isRu(locale);
    final m = (minutes ?? 0) < 1 ? 1 : minutes!;
    if (m < 60) return ru ? '$m мин' : '$m min';
    final h = m ~/ 60;
    final rest = m % 60;
    if (rest == 0) return ru ? '$h ч' : '$h h';
    return ru ? '$h ч $rest мин' : '$h h $rest min';
  }

  /// Request lifecycle status word; unknown names come back unchanged.
  static String statusLabel(String status, String locale) {
    final pair = _statusLabels[status];
    if (pair == null) return status;
    return _isRu(locale) ? pair.$2 : pair.$1;
  }
}
