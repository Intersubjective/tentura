import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
            child: _EdgeFadedRow(
              color: theme.colorScheme.surface,
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
          ),
        );
      },
    );
  }
}

/// Fades the edges of the horizontally scrolled chip row where more chips
/// are hidden (#659), so on a phone the row reads as scrollable.
class _EdgeFadedRow extends StatefulWidget {
  const _EdgeFadedRow({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  State<_EdgeFadedRow> createState() => _EdgeFadedRowState();
}

class _EdgeFadedRowState extends State<_EdgeFadedRow> {
  static const _fadeWidth = 32.0;

  var _moreBefore = false;
  var _moreAfter = false;

  bool _onMetrics(ScrollMetrics metrics) {
    if (metrics.axis != Axis.horizontal) return false;
    final moreBefore = metrics.extentBefore > 0.5;
    final moreAfter = metrics.extentAfter > 0.5;
    if (moreBefore == _moreBefore && moreAfter == _moreAfter) return false;
    void apply() {
      if (!mounted) return;
      setState(() {
        _moreBefore = moreBefore;
        _moreAfter = moreAfter;
      });
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
    return false;
  }

  Widget _fade(String key, AlignmentDirectional towards) => IgnorePointer(
    key: Key(key),
    child: SizedBox(
      width: _fadeWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: -towards,
            end: towards,
            colors: [widget.color.withValues(alpha: 0), widget.color],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) => _onMetrics(notification.metrics),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) =>
              notification.depth == 0 && _onMetrics(notification.metrics),
          child: widget.child,
        ),
      ),
      if (_moreBefore)
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          child: _fade(
            'constellation.show.fade_start',
            AlignmentDirectional.centerStart,
          ),
        ),
      if (_moreAfter)
        PositionedDirectional(
          end: 0,
          top: 0,
          bottom: 0,
          child: _fade(
            'constellation.show.fade_end',
            AlignmentDirectional.centerEnd,
          ),
        ),
    ],
  );
}
