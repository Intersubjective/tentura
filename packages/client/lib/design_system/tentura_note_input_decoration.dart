import 'package:flutter/material.dart';

import 'tentura_radii.dart';
import 'tentura_text.dart';
import 'tentura_tokens.dart';

/// Shared outlined note field decoration (Forward beacon, Offer Help dialog, …).
InputDecoration tenturaNoteInputDecoration(
  BuildContext context, {
  String? labelText,
  String? hintText,
  Widget? suffixIcon,
}) {
  final tt = context.tt;
  return InputDecoration(
    labelText: labelText,
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
