import 'package:flutter/material.dart';

import 'tentura_radii.dart';
import 'tentura_text.dart';
import 'tentura_tokens.dart';

/// Outlined form field for screens that are mostly a form (Edit profile,
/// New Request): a visible container, a floating label, helper text that
/// wraps instead of dropping its last word ("(option…"), and one input text
/// style for every field on the form.
///
/// Counters are shown only near the limit — pass [tenturaCounterNearLimit]
/// as `buildCounter`.
InputDecoration tenturaFormFieldDecoration(
  BuildContext context, {
  String? labelText,
  String? hintText,
  String? helperText,
  String? errorText,
  String? prefixText,
  bool alignLabelWithHint = false,
}) {
  final tt = context.tt;
  final scheme = Theme.of(context).colorScheme;
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    helperText: helperText,
    errorText: errorText,
    prefixText: prefixText,
    alignLabelWithHint: alignLabelWithHint,
    helperMaxLines: 3,
    errorMaxLines: 3,
    filled: true,
    fillColor: tt.surface,
    labelStyle: TenturaText.bodyMedium(tt.textMuted),
    hintStyle: TenturaText.bodyMedium(tt.textFaint),
    helperStyle: TenturaText.bodySmall(tt.textMuted),
    errorStyle: TenturaText.bodySmall(tt.danger),
    prefixStyle: TenturaText.bodyLarge(tt.textMuted),
    contentPadding: tt.cardPadding,
    // textFaint is ≥ 3:1 on the surface — the non-text contrast minimum a
    // field boundary needs to be found at all.
    border: border(tt.textFaint),
    enabledBorder: border(tt.textFaint),
    focusedBorder: border(scheme.primary, 2),
    errorBorder: border(tt.danger),
    focusedErrorBorder: border(tt.danger, 2),
  );
}

/// The input text style shared by every [tenturaFormFieldDecoration] field.
TextStyle tenturaFormFieldTextStyle(BuildContext context) =>
    TenturaText.bodyLarge(context.tt.text);

/// `buildCounter` that stays silent until 80 % of [maxLength]; a counter at
/// 15/32 is noise, one at 30/32 is information.
Widget? tenturaCounterNearLimit(
  BuildContext context, {
  required int currentLength,
  required int? maxLength,
  required bool isFocused,
}) {
  if (maxLength == null || currentLength < maxLength * 0.8) return null;
  final tt = context.tt;
  return Text(
    '$currentLength/$maxLength',
    style: TenturaText.withTabular(
      TenturaText.bodySmall(
        currentLength >= maxLength ? tt.danger : tt.textMuted,
      ),
    ),
  );
}
