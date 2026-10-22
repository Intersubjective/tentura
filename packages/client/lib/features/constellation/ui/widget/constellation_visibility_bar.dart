import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/constellation_visibility.dart';
import '../bloc/constellation_cubit.dart';

/// One row of on/off chips above the field (#645): all Requests, all Posts,
/// and all people of each trust degree, each with how many the field holds.
/// They apply to the map and the list alike, hide pinned objects too (the
/// pins are kept), and are kept per viewer on this device.
class ConstellationVisibilityBar extends StatelessWidget {
  const ConstellationVisibilityBar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConstellationCubit, ConstellationState>(
      buildWhen: (previous, current) =>
          previous.visibility != current.visibility ||
          previous.composition != current.composition ||
          previous.field != current.field,
      builder: (context, state) {
        final cubit = context.read<ConstellationCubit>();
        final counts = cubit.visibilityCounts;
        if (counts == null) {
          return const SizedBox.shrink();
        }
        final l10n = L10n.of(context)!;
        final tt = context.tt;
        final theme = Theme.of(context);
        final visibility = state.visibility;

        Widget chip({
          required String key,
          required String label,
          required String hint,
          required int count,
          required bool shown,
          required ConstellationVisibility Function(bool shown) next,
        }) => Tooltip(
          message: hint,
          child: Semantics(
            hint: hint,
            child: FilterChip(
              key: Key('constellation.show.$key'),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label),
                  SizedBox(width: tt.tightGap),
                  Text(
                    '$count',
                    key: Key('constellation.show.$key.count'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              selected: shown,
              onSelected: (value) => cubit.setVisibility(next(value)),
            ),
          ),
        );

        final chips = [
          chip(
            key: 'requests',
            label: l10n.constellationShowRequests,
            hint: l10n.constellationShowRequestsHint,
            count: counts.requests,
            shown: visibility.requests,
            next: (shown) => visibility.copyWith(requests: shown),
          ),
          chip(
            key: 'posts',
            label: l10n.constellationShowPosts,
            hint: l10n.constellationShowPostsHint,
            count: counts.posts,
            shown: visibility.posts,
            next: (shown) => visibility.copyWith(posts: shown),
          ),
          for (final degree in ConstellationTrustDegree.values)
            chip(
              key: 'degree.${degree.name}',
              label: switch (degree) {
                ConstellationTrustDegree.first =>
                  l10n.constellationShowDegreeFirst,
                ConstellationTrustDegree.second =>
                  l10n.constellationShowDegreeSecond,
                ConstellationTrustDegree.further =>
                  l10n.constellationShowDegreeFurther,
              },
              hint: switch (degree) {
                ConstellationTrustDegree.first =>
                  l10n.constellationShowDegreeFirstHint,
                ConstellationTrustDegree.second =>
                  l10n.constellationShowDegreeSecondHint,
                ConstellationTrustDegree.further =>
                  l10n.constellationShowDegreeFurtherHint,
              },
              count: counts.people[degree] ?? 0,
              shown: visibility.showsDegree(degree),
              next: (shown) => visibility.withDegree(degree, shown: shown),
            ),
        ];

        return Material(
          color: theme.colorScheme.surface,
          child: Semantics(
            container: true,
            label: l10n.constellationShowSection,
            child: SingleChildScrollView(
              key: const Key('constellation.show'),
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(
                horizontal: tt.screenHPadding,
                vertical: tt.tightGap,
              ),
              child: Row(
                children: [
                  for (var i = 0; i < chips.length; i++) ...[
                    if (i > 0) SizedBox(width: tt.tightGap),
                    chips[i],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
