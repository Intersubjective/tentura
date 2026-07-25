import 'package:flutter/material.dart';

import 'package:tentura/domain/capability/capability_tag.dart';

import '../tentura_capability_colors.dart';

/// Square tinted capability glyph: group container with on-container icon.
class TenturaCapabilityGlyph extends StatelessWidget {
  const TenturaCapabilityGlyph({
    required this.tag,
    required this.size,
    super.key,
  });

  final CapabilityTag tag;
  final double size;

  @override
  Widget build(BuildContext context) {
    final swatch = context.capabilityColors.swatchFor(tag.group);
    final iconSize = size * 0.52;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: swatch.container,
          borderRadius: BorderRadius.circular(size * 0.2),
        ),
        child: Center(
          child: Icon(
            tag.icon,
            size: iconSize,
            color: swatch.onContainer,
          ),
        ),
      ),
    );
  }
}
