import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';

/// Tiny overlapping forwarder avatars + optional `+N` (My Work committed footer).
class CompactForwarderAvatars extends StatelessWidget {
  const CompactForwarderAvatars({
    required this.profiles,
    this.overflowCount = 0,
    this.size = 20,
    this.overlap = 6,
    super.key,
  });

  final List<Profile> profiles;
  final int overflowCount;
  final double size;
  final double overlap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ringColor = scheme.outlineVariant;
    final badgeFill = scheme.surfaceContainerHigh;
    final badgeFg = scheme.onSurfaceVariant;

    final extraSlots = overflowCount > 0 ? 1 : 0;
    final n = profiles.length + extraSlots;
    if (n == 0) {
      return const SizedBox.shrink();
    }

    final step = size - overlap;
    final width = size + (n - 1) * step;

    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < profiles.length; i++)
            Positioned(
              left: i * step,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ringColor),
                ),
                child: AvatarRated(
                  profile: profiles[i],
                  withRating: false,
                  size: size,
                ),
              ),
            ),
          if (overflowCount > 0)
            Positioned(
              left: profiles.length * step,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: badgeFill,
                  border: Border.all(color: ringColor),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$overflowCount',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: badgeFg,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
