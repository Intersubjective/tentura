import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';

import '../../domain/constellation_filters.dart';
import '../bloc/constellation_cubit.dart';

class ConstellationFilterBar extends StatelessWidget {
  const ConstellationFilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConstellationCubit, ConstellationState>(
      buildWhen: (previous, current) =>
          previous.filterCapabilitySlugs != current.filterCapabilitySlugs ||
          previous.filterLocation != current.filterLocation ||
          previous.filterTiming != current.filterTiming ||
          previous.filterIncludeUnspecified !=
              current.filterIncludeUnspecified ||
          previous.field != current.field ||
          previous.capped != current.capped ||
          previous.keptPeerIds != current.keptPeerIds ||
          previous.paths != current.paths,
      builder: (context, state) {
        final cubit = context.read<ConstellationCubit>();
        final l10n = L10n.of(context)!;
        final tt = context.tt;
        final theme = Theme.of(context);

        return Material(
          key: const Key('constellation.filter_bar'),
          color: theme.colorScheme.surface,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tt.screenHPadding,
                vertical: tt.tightGap,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FieldLevelNotices(cubit: cubit),
                  if (cubit.isFilteredResultEmpty) ...[
                    SizedBox(height: tt.rowGap),
                    Text(
                      l10n.constellationEmptyFiltered,
                      key: const Key('constellation.filter.empty'),
                      style: theme.textTheme.bodyMedium,
                    ),
                    SizedBox(height: tt.tightGap),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonal(
                        key: const Key('constellation.filter.clear'),
                        onPressed: cubit.clearFilters,
                        child: Text(l10n.constellationClearFilters),
                      ),
                    ),
                  ] else ...[
                    SizedBox(height: tt.rowGap),
                    _CapabilityFilters(cubit: cubit),
                    SizedBox(height: tt.tightGap),
                    _LocationFilters(cubit: cubit),
                    SizedBox(height: tt.tightGap),
                    _TimingFilters(cubit: cubit),
                    SizedBox(height: tt.tightGap),
                    SwitchListTile.adaptive(
                      key: const Key('constellation.filter.include_unspecified'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.constellationIncludeUnspecified),
                      value: state.filterIncludeUnspecified,
                      onChanged: cubit.setFilterIncludeUnspecified,
                    ),
                  ],
                  SizedBox(height: tt.tightGap),
                  Text(
                    l10n.constellationFilterLimitations,
                    key: const Key('constellation.filter.limitations'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FieldLevelNotices extends StatelessWidget {
  const _FieldLevelNotices({required this.cubit});

  final ConstellationCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    final notices = <Widget>[];

    if (cubit.peersCapped) {
      notices.add(
        _NoticeCard(
          key: const Key('constellation.notice.peers_capped'),
          message: l10n.constellationPathOmittedByCap,
          actionLabel: l10n.constellationFallbackListLink,
          onAction: () => cubit.setViewMode(ConstellationViewMode.text),
        ),
      );
    }
    if (cubit.requestsCapped) {
      notices.add(
        _NoticeCard(
          key: const Key('constellation.notice.requests_capped'),
          message: l10n.constellationRequestsCapped,
        ),
      );
    }
    if (cubit.renderBudgetCapped) {
      notices.add(
        _NoticeCard(
          key: const Key('constellation.notice.render_budget_capped'),
          message: l10n.constellationRenderBudgetCapped,
        ),
      );
    }

    if (notices.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < notices.length; i++) ...[
          if (i > 0) SizedBox(height: tt.tightGap),
          notices[i],
        ],
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(tt.cardRadius),
      ),
      child: Padding(
        padding: tt.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: tt.tightGap),
              TextButton(
                key: const Key('constellation.notice.fallback_list'),
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CapabilityFilters extends StatelessWidget {
  const _CapabilityFilters({required this.cubit});

  final ConstellationCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final slugs = cubit.availableCapabilitySlugs().toList()..sort();
    if (slugs.isEmpty) {
      return const SizedBox.shrink();
    }

    final selected = cubit.state.filterCapabilitySlugs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.constellationFilterCapability, style: Theme.of(context).textTheme.labelLarge),
        SizedBox(height: tt.tightGap),
        Wrap(
          spacing: tt.tightGap,
          runSpacing: tt.tightGap,
          children: [
            for (final slug in slugs)
              FilterChip(
                key: Key('constellation.filter.capability.$slug'),
                label: Text(
                  CapabilityTag.fromSlug(slug)?.labelOf(l10n) ?? slug,
                ),
                selected: selected.contains(slug),
                onSelected: (value) {
                  final next = Set<String>.from(selected);
                  value ? next.add(slug) : next.remove(slug);
                  cubit.setFilterCapabilitySlugs(next);
                },
              ),
            FilterChip(
              key: const Key('constellation.filter.capability.unspecified'),
              label: Text(l10n.constellationUnspecifiedGroup),
              selected: selected.isEmpty,
              onSelected: (_) => cubit.setFilterCapabilitySlugs(const {}),
            ),
          ],
        ),
      ],
    );
  }
}

class _LocationFilters extends StatelessWidget {
  const _LocationFilters({required this.cubit});

  final ConstellationCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final current = cubit.state.filterLocation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.constellationFilterLocation, style: Theme.of(context).textTheme.labelLarge),
        SizedBox(height: tt.tightGap),
        Wrap(
          spacing: tt.tightGap,
          runSpacing: tt.tightGap,
          children: [
            for (final option in LocationFilter.values)
              FilterChip(
                key: Key('constellation.filter.location.${option.name}'),
                label: Text(_locationLabel(l10n, option)),
                selected: current == option,
                onSelected: (selected) {
                  if (selected) {
                    cubit.setFilterLocation(option);
                  }
                },
              ),
          ],
        ),
      ],
    );
  }

  String _locationLabel(L10n l10n, LocationFilter filter) => switch (filter) {
    LocationFilter.any => l10n.constellationFilterLocationAny,
    LocationFilter.hasLocation => l10n.constellationFilterLocationHas,
    LocationFilter.unspecified => l10n.constellationUnspecifiedGroup,
  };
}

class _TimingFilters extends StatelessWidget {
  const _TimingFilters({required this.cubit});

  final ConstellationCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final timing = cubit.state.filterTiming;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.constellationFilterTiming, style: Theme.of(context).textTheme.labelLarge),
        SizedBox(height: tt.tightGap),
        Wrap(
          spacing: tt.tightGap,
          runSpacing: tt.tightGap,
          children: [
            FilterChip(
              key: const Key('constellation.filter.timing.any'),
              label: Text(l10n.constellationFilterTimingAny),
              selected: timing is TimingFilterAny,
              onSelected: (selected) {
                if (selected) {
                  cubit.setFilterTiming(const TimingFilterAny());
                }
              },
            ),
            FilterChip(
              key: const Key('constellation.filter.timing.undated'),
              label: Text(l10n.constellationUnspecifiedGroup),
              selected: timing is TimingFilterUndated,
              onSelected: (selected) {
                if (selected) {
                  cubit.setFilterTiming(const TimingFilterUndated());
                }
              },
            ),
            FilterChip(
              key: const Key('constellation.filter.timing.within_7'),
              label: Text(l10n.constellationFilterTimingWithinDays(7)),
              selected: timing is TimingFilterWithinDays && timing.days == 7,
              onSelected: (selected) {
                if (selected) {
                  cubit.setFilterTiming(timingFilterWithinDays(7));
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}
