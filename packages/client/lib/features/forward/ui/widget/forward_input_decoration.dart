import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

/// Shared [InputDecoration] for Forward Beacon note fields (shared + per-recipient).
InputDecoration forwardNoteInputDecoration(
  BuildContext context, {
  String? hintText,
  Widget? suffixIcon,
}) => tenturaNoteInputDecoration(
  context,
  hintText: hintText,
  suffixIcon: suffixIcon,
);
