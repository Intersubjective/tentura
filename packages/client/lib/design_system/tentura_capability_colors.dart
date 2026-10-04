import 'package:flutter/material.dart';

import 'package:tentura/domain/capability/capability_group.dart';

import 'tentura_colors.dart';

/// Container + on-container pair for one capability group.
@immutable
class CapabilitySwatch {
  const CapabilitySwatch({
    required this.container,
    required this.onContainer,
  });

  final Color container;
  final Color onContainer;

  CapabilitySwatch copyWith({
    Color? container,
    Color? onContainer,
  }) =>
      CapabilitySwatch(
        container: container ?? this.container,
        onContainer: onContainer ?? this.onContainer,
      );

  static CapabilitySwatch lerp(
    CapabilitySwatch a,
    CapabilitySwatch b,
    double t,
  ) =>
      CapabilitySwatch(
        container: Color.lerp(a.container, b.container, t)!,
        onContainer: Color.lerp(a.onContainer, b.onContainer, t)!,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CapabilitySwatch &&
          container == other.container &&
          onContainer == other.onContainer;

  @override
  int get hashCode => Object.hash(container, onContainer);
}

/// Capability-group tint palette as a [ThemeExtension].
class TenturaCapabilityColors extends ThemeExtension<TenturaCapabilityColors> {
  const TenturaCapabilityColors({
    required this.logistics,
    required this.communication,
    required this.knowledge,
    required this.care,
    required this.resources,
    required this.technical,
    required this.rpg,
    required this.special,
  });

  final CapabilitySwatch logistics;
  final CapabilitySwatch communication;
  final CapabilitySwatch knowledge;
  final CapabilitySwatch care;
  final CapabilitySwatch resources;
  final CapabilitySwatch technical;
  final CapabilitySwatch rpg;
  final CapabilitySwatch special;

  /// Light swatches — defined in [TenturaColorPalette.light].
  static TenturaCapabilityColors get light =>
      TenturaColorPalette.light.capabilities;

  /// Dark swatches — defined in [TenturaColorPalette.dark].
  static TenturaCapabilityColors get dark =>
      TenturaColorPalette.dark.capabilities;

  CapabilitySwatch swatchFor(CapabilityGroup group) => switch (group) {
        CapabilityGroup.logistics => logistics,
        CapabilityGroup.communication => communication,
        CapabilityGroup.knowledge => knowledge,
        CapabilityGroup.care => care,
        CapabilityGroup.resources => resources,
        CapabilityGroup.technical => technical,
        CapabilityGroup.rpg => rpg,
        CapabilityGroup.special => special,
      };

  @override
  TenturaCapabilityColors copyWith({
    CapabilitySwatch? logistics,
    CapabilitySwatch? communication,
    CapabilitySwatch? knowledge,
    CapabilitySwatch? care,
    CapabilitySwatch? resources,
    CapabilitySwatch? technical,
    CapabilitySwatch? rpg,
    CapabilitySwatch? special,
  }) =>
      TenturaCapabilityColors(
        logistics: logistics ?? this.logistics,
        communication: communication ?? this.communication,
        knowledge: knowledge ?? this.knowledge,
        care: care ?? this.care,
        resources: resources ?? this.resources,
        technical: technical ?? this.technical,
        rpg: rpg ?? this.rpg,
        special: special ?? this.special,
      );

  @override
  TenturaCapabilityColors lerp(
    ThemeExtension<TenturaCapabilityColors>? other,
    double t,
  ) {
    if (other is! TenturaCapabilityColors) return this;
    return TenturaCapabilityColors(
      logistics: CapabilitySwatch.lerp(logistics, other.logistics, t),
      communication:
          CapabilitySwatch.lerp(communication, other.communication, t),
      knowledge: CapabilitySwatch.lerp(knowledge, other.knowledge, t),
      care: CapabilitySwatch.lerp(care, other.care, t),
      resources: CapabilitySwatch.lerp(resources, other.resources, t),
      technical: CapabilitySwatch.lerp(technical, other.technical, t),
      rpg: CapabilitySwatch.lerp(rpg, other.rpg, t),
      special: CapabilitySwatch.lerp(special, other.special, t),
    );
  }
}

extension TenturaCapabilityColorsX on BuildContext {
  /// Fail-fast access; callers must sit under [TenturaTheme].
  TenturaCapabilityColors get capabilityColors =>
      Theme.of(this).extension<TenturaCapabilityColors>()!;
}
