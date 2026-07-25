import 'package:flutter/material.dart';

import 'package:tentura/domain/capability/capability_group.dart';

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
    required this.special,
  });

  final CapabilitySwatch logistics;
  final CapabilitySwatch communication;
  final CapabilitySwatch knowledge;
  final CapabilitySwatch care;
  final CapabilitySwatch resources;
  final CapabilitySwatch technical;
  final CapabilitySwatch special;

  /// Exact light palette from the cover/capability colour plan.
  static const light = TenturaCapabilityColors(
    logistics: CapabilitySwatch(
      container: Color(0xFFEEF2FF),
      onContainer: Color(0xFF3730A3),
    ),
    communication: CapabilitySwatch(
      container: Color(0xFFECFEFF),
      onContainer: Color(0xFF155E75),
    ),
    knowledge: CapabilitySwatch(
      container: Color(0xFFF5F3FF),
      onContainer: Color(0xFF5B21B6),
    ),
    care: CapabilitySwatch(
      container: Color(0xFFFDF4FF),
      onContainer: Color(0xFF86198F),
    ),
    resources: CapabilitySwatch(
      container: Color(0xFFF0FDFA),
      onContainer: Color(0xFF115E59),
    ),
    technical: CapabilitySwatch(
      container: Color(0xFFF5F5F4),
      onContainer: Color(0xFF44403C),
    ),
    special: CapabilitySwatch(
      container: Color(0xFFF1F5F9),
      onContainer: Color(0xFF475569),
    ),
  );

  /// Exact dark palette from the cover/capability colour plan.
  static const dark = TenturaCapabilityColors(
    logistics: CapabilitySwatch(
      container: Color(0xFF252F4A),
      onContainer: Color(0xFFA5B4FC),
    ),
    communication: CapabilitySwatch(
      container: Color(0xFF16323C),
      onContainer: Color(0xFF67E8F9),
    ),
    knowledge: CapabilitySwatch(
      container: Color(0xFF2A2647),
      onContainer: Color(0xFFC4B5FD),
    ),
    care: CapabilitySwatch(
      container: Color(0xFF3A1F3F),
      onContainer: Color(0xFFF0ABFC),
    ),
    resources: CapabilitySwatch(
      container: Color(0xFF123832),
      onContainer: Color(0xFF5EEAD4),
    ),
    technical: CapabilitySwatch(
      container: Color(0xFF292524),
      onContainer: Color(0xFFD6D3D1),
    ),
    special: CapabilitySwatch(
      container: Color(0xFF273240),
      onContainer: Color(0xFFCBD5E1),
    ),
  );

  CapabilitySwatch swatchFor(CapabilityGroup group) => switch (group) {
        CapabilityGroup.logistics => logistics,
        CapabilityGroup.communication => communication,
        CapabilityGroup.knowledge => knowledge,
        CapabilityGroup.care => care,
        CapabilityGroup.resources => resources,
        CapabilityGroup.technical => technical,
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
    CapabilitySwatch? special,
  }) =>
      TenturaCapabilityColors(
        logistics: logistics ?? this.logistics,
        communication: communication ?? this.communication,
        knowledge: knowledge ?? this.knowledge,
        care: care ?? this.care,
        resources: resources ?? this.resources,
        technical: technical ?? this.technical,
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
      special: CapabilitySwatch.lerp(special, other.special, t),
    );
  }
}

extension TenturaCapabilityColorsX on BuildContext {
  /// Fail-fast access; callers must sit under [TenturaTheme].
  TenturaCapabilityColors get capabilityColors =>
      Theme.of(this).extension<TenturaCapabilityColors>()!;
}
