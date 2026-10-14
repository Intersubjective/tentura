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
  const CodeUnitLengthLimitingTextInputFormatter(this.maxLength);

  final int maxLength;

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
    // Already over the cap (e.g. a draft saved before the cap existed):
    // allow edits that do not make it longer.
    if (oldValue.text.length > maxLength &&
        newValue.text.length <= oldValue.text.length) {
      return newValue;
    }
    final text = truncate(newValue.text, maxLength);
    return TextEditingValue(
      text: text,
      selection: newValue.selection.copyWith(
        baseOffset: newValue.selection.baseOffset.clamp(0, text.length),
        extentOffset: newValue.selection.extentOffset.clamp(0, text.length),
      ),
    );
  }
}
