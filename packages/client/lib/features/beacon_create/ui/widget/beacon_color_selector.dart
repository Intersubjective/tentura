import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
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
    final tt = context.tt;
    const swatchSize = 36.0;
    final hitSize = tt.buttonHeight < kMinInteractiveDimension
        ? kMinInteractiveDimension
        : tt.buttonHeight;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final s in kBeaconIdentityPalette)
          SizedBox(
            width: hitSize,
            height: hitSize,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onSelected(s.backgroundArgb),
                child: Center(
                  child: Container(
                    width: swatchSize,
                    height: swatchSize,
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
                        ? Icon(Icons.check, size: tt.iconSize, color: s.foreground)
                        : null,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
