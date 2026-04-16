import 'package:flutter/material.dart';

/// Small "new stuff" dot used across tabs/cards/rows.
class NewStuffDot extends StatelessWidget {
  const NewStuffDot({
    super.key,
    this.size = 10,
    this.padding,
  });

  final double size;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: BoxShape.circle,
          border: Border.all(color: scheme.surface, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.30),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}
