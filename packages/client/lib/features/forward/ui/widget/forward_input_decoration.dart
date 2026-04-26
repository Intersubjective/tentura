import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

/// Shared [InputDecoration] for Forward Beacon note fields (shared + per-recipient).
InputDecoration forwardNoteInputDecoration(
  BuildContext context, {
  String? hintText,
  Widget? suffixIcon,
}) {
  final tt = context.tt;
  return InputDecoration(
    hintText: hintText,
    hintStyle: TenturaText.bodySmall(tt.textFaint),
    filled: true,
    fillColor: tt.surface,
    isDense: true,
    contentPadding: EdgeInsets.all(tt.cardPadding.top),
    suffixIcon: suffixIcon,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
      borderSide: BorderSide(color: tt.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
      borderSide: BorderSide(color: tt.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
      borderSide: BorderSide(color: tt.skyBorder),
    ),
  );
}
