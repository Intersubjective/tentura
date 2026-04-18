import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

import '../bloc/rating_cubit.dart';

/// Threshold on 0-100 scale for "support" (above = meaningful trust).
const _kSupportThreshold = 10.0;

enum _ReciprocityClass { mutual, oneWayOut, oneWayIn, none }

_ReciprocityClass _reciprocityClass(double direct, double reverse) {
  final dp = direct > _kSupportThreshold;
  final rp = reverse > _kSupportThreshold;
  if (dp && rp) return _ReciprocityClass.mutual;
  if (dp && !rp) return _ReciprocityClass.oneWayOut;
  if (!dp && rp) return _ReciprocityClass.oneWayIn;
  return _ReciprocityClass.none;
}

class RatingListTile extends StatelessWidget {
  const RatingListTile({
    required this.profile,
    super.key,
  });

  final Profile profile;

  static double _heatmapAlpha(double score) {
    final v = score / 100;
    if (v <= 0) return 0.08;
    if (v >= 1) return 1;
    return v.clamp(0.08, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final l10n = L10n.of(context)!;
    final direct = profile.score;
    final reverse = profile.rScore;
    final alphaDirect = _heatmapAlpha(direct);
    final alphaReverse = _heatmapAlpha(reverse);
    final reciprocity = _reciprocityClass(direct, reverse);

    String badgeLabel;
    Color badgeBg;
    Color badgeFg;
    Color badgeBorder;
    switch (reciprocity) {
      case _ReciprocityClass.mutual:
        badgeLabel = l10n.classMutual;
        badgeBg = colorScheme.primary.withValues(alpha: 12 / 100);
        badgeFg = colorScheme.primary;
        badgeBorder = colorScheme.primary.withValues(alpha: 4 / 10);
      case _ReciprocityClass.oneWayOut:
        badgeLabel = l10n.classOneWayOut;
        badgeBg = const Color(0x1AFF9800); // amber 50 tint
        badgeFg = const Color(0xFFE65100);
        badgeBorder = const Color(0x4DFF9800);
      case _ReciprocityClass.oneWayIn:
        badgeLabel = l10n.classOneWayIn;
        badgeBg = colorScheme.secondary.withValues(alpha: 2 / 10);
        badgeFg = colorScheme.secondary;
        badgeBorder = colorScheme.secondary.withValues(alpha: 5 / 10);
      case _ReciprocityClass.none:
        badgeLabel = l10n.classNone;
        badgeBg = colorScheme.surfaceContainer;
        badgeFg = colorScheme.onSurfaceVariant;
        badgeBorder = colorScheme.outlineVariant;
    }

    const rowHeight = 56.0;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => context.read<RatingCubit>().showProfile(profile.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: kSpacingSmall),
        child: SizedBox(
          height: rowHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Alter: avatar + name (double width)
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  SelfAwareAvatar(profile: profile),
                  const SizedBox(width: kSpacingSmall),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BlocBuilder<ProfileCubit, ProfileState>(
                          buildWhen: (p, c) => p.profile.id != c.profile.id,
                          builder: (context, state) {
                            final l10n = L10n.of(context)!;
                            return Text(
                              SelfUserHighlight.displayName(
                                l10n,
                                profile,
                                state.profile.id,
                              ),
                              style: SelfUserHighlight.nameStyle(
                                Theme.of(context),
                                textTheme.titleSmall,
                                SelfUserHighlight.profileIsSelf(
                                  profile,
                                  state.profile.id,
                                ),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: kSpacingSmall),
            // I trust them (heatmap) – rectangle filling the cell
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: kSpacingSmall),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: alphaDirect),
                    borderRadius: BorderRadius.circular(kBorderRadius),
                  ),
                  child: Text(
                    direct.toStringAsFixed(1),
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: kSpacingSmall),
            // They trust me (heatmap) – rectangle filling the cell
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: kSpacingSmall),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: alphaReverse),
                    borderRadius: BorderRadius.circular(kBorderRadius),
                  ),
                  child: Text(
                    reverse.toStringAsFixed(1),
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: kSpacingSmall),
            // Class badge
            SizedBox(
              width: 100,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: kSpacingSmall,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: badgeBorder),
                  ),
                  child: Text(
                    badgeLabel,
                    style: textTheme.labelSmall?.copyWith(
                      color: badgeFg,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
