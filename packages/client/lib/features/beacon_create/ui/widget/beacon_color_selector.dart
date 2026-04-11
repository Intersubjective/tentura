import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_identity_catalog.dart';

class BeaconColorSelector extends StatelessWidget {
  const BeaconColorSelector({
    required this.selectedArgb,
    required this.onSelected,
    super.key,
  });

  final int? selectedArgb;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final s in kBeaconIdentityPalette)
          GestureDetector(
            onTap: () => onSelected(s.backgroundArgb),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: s.background,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selectedArgb == s.backgroundArgb
                      ? scheme.primary
                      : scheme.outlineVariant.withValues(alpha: 0.5),
                  width: selectedArgb == s.backgroundArgb ? 3 : 1,
                ),
              ),
              child: selectedArgb == s.backgroundArgb
                  ? Icon(Icons.check, size: 20, color: s.foreground)
                  : null,
            ),
          ),
      ],
    );
  }
}
