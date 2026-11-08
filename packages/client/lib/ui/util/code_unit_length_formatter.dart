import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Caps a field at [maxLength] UTF-16 code units — the unit `String.length`
/// counts, and so the unit the server and `StringInputValidator` check.
///
/// `TextField.maxLength` counts user-perceived characters, so an emoji counts
/// once there but twice in `String.length`: a field could fill to its limit
/// with text the validators then reject. This formatter truncates on a
/// character boundary, so it never splits an emoji or a combining sequence.
class CodeUnitLengthLimitingTextInputFormatter extends TextInputFormatter {
  const CodeUnitLengthLimitingTextInputFormatter(
    this.maxLength, {
    this.onTruncated,
  });

  final int maxLength;

  /// Called when an edit (typically a paste) was cut to fit, so the field can
  /// tell the user their text was shortened. Not called when the edit is
  /// taken whole or rejected whole (a keystroke at the cap).
  final VoidCallback? onTruncated;

  /// The longest prefix of [text] that fits in [maxLength] code units and
  /// ends on a character boundary.
  static String truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    var end = 0;
    for (final char in text.characters) {
      if (end + char.length > maxLength) break;
      end += char.length;
    }
    return text.substring(0, end);
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length <= maxLength) return newValue;
    // An IME is still composing (CJK, phonetic input): the composing text can
    // run long before it commits to fewer code units. Per the
    // TextInputFormatter contract, leave it alone until composition ends.
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    // Already over the cap (e.g. a draft saved before the cap existed):
    // allow edits that do not make it longer.
    if (oldValue.text.length > maxLength &&
        newValue.text.length <= oldValue.text.length) {
      return newValue;
    }
    // Trim only what this edit inserted, so text that was already accepted
    // is never removed: neither the tail after a mid-text insertion nor a
    // final grapheme the edit extended (e.g. a skin-tone modifier added to
    // an emoji at the cap).
    final old = oldValue.text;
    final text = newValue.text;
    final prefix = _commonPrefix(old, text);
    final suffix = _commonSuffix(old, text, prefix);
    final inserted = text.substring(prefix, text.length - suffix);
    final room = maxLength - (text.length - inserted.length);
    final fit = room <= 0 ? 0 : truncate(inserted, room).length;
    // The cut must also be a character boundary of the whole new text: an
    // insertion that extends the character before it (e.g. ZWJ + 👧 after
    // 👨‍👩) would otherwise leave a dangling, invisible joiner.
    final end = _boundaryAtOrBefore(text, prefix + fit, prefix);
    final kept = end == null ? '' : text.substring(prefix, end);
    if (kept.isEmpty) return oldValue;
    final result =
        text.substring(0, prefix) + kept + text.substring(text.length - suffix);
    onTruncated?.call();
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: prefix + kept.length),
    );
  }

  /// The last character boundary of [text] in [floor]..[limit], or null.
  static int? _boundaryAtOrBefore(String text, int limit, int floor) {
    var offset = 0;
    var best = floor == 0 ? 0 : null;
    for (final char in text.characters) {
      offset += char.length;
      if (offset > limit) break;
      if (offset >= floor) best = offset;
    }
    return best;
  }

  /// Code units [a] and [b] share at the start, never ending inside a
  /// surrogate pair.
  static int _commonPrefix(String a, String b) {
    final n = a.length < b.length ? a.length : b.length;
    var i = 0;
    while (i < n && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    if (i > 0 && i < b.length && _isLowSurrogate(b.codeUnitAt(i))) i--;
    return i;
  }

  /// Code units [a] and [b] share at the end, not overlapping the first
  /// [prefix] units and never starting inside a surrogate pair.
  static int _commonSuffix(String a, String b, int prefix) {
    final n = (a.length < b.length ? a.length : b.length) - prefix;
    var i = 0;
    while (i < n &&
        a.codeUnitAt(a.length - 1 - i) == b.codeUnitAt(b.length - 1 - i)) {
      i++;
    }
    if (i > 0 && _isLowSurrogate(b.codeUnitAt(b.length - i))) i--;
    return i;
  }

  static bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
}
