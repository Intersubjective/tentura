import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

/// Shared auth form field wrapper — consistent [context.tt.cardPadding] around inputs.
class AuthFormField extends StatelessWidget {
  const AuthFormField({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: context.tt.cardPadding,
      child: child,
    );
  }
}
