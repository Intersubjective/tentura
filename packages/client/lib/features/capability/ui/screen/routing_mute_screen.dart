import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_group.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/features/capability/ui/widget/capability_selection_count_badge.dart';
import 'package:tentura/features/capability/ui/widget/capability_tag_chip.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/accordion_expansion.dart';

import '../bloc/routing_mute_cubit.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/features/home/ui/widget/home_rail_frame.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';
import 'package:tentura/consts.dart';

@RoutePage()
class RoutingMuteScreen extends StatelessWidget implements AutoRouteWrapper {
  const RoutingMuteScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = RoutingMuteCubit();
      unawaited(cubit.fetch());
      return cubit;
    },
    child: this,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return HomeRailFrame(
      selectedTab: HomeTab.me,
      child: Scaffold(
        appBar: TenturaTopBar.of(
          context,
          leading: const AutoLeadingWithFallback(fallbackPath: kPathSettings),
          title: Text(
            l10n.routingMuteScreenTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: BlocBuilder<RoutingMuteCubit, RoutingMuteState>(
          builder: (context, state) {
            if (state.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            final cubit = context.read<RoutingMuteCubit>();
            final theme = Theme.of(context);
            final tt = context.tt;
            return TenturaContentColumn(
              child: ListView(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      tt.screenHPadding,
                      tt.sectionGap,
                      tt.screenHPadding,
                      tt.tightGap,
                    ),
                    child: Text(
                      l10n.routingMuteScreenDescription,
                      style: TenturaText.bodySmall(tt.textMuted),
                    ),
                  ),
                  ExpansionTileTheme(
                    // Keeps tile headers flush with the description's left
                    // edge (issue #139).
                    data: ExpansionTileTheme.of(context).copyWith(
                      tilePadding: EdgeInsets.symmetric(
                        horizontal: tt.screenHPadding,
                      ),
                    ),
                    child: AccordionExpansionGroup(
                      child: Theme(
                        // One interaction theme for the whole set, matching
                        // CapabilityChipSet's per-chip styling.
                        data: theme.copyWith(
                          splashFactory: NoSplash.splashFactory,
                          highlightColor: Colors.transparent,
                          hoverColor: Colors.transparent,
                          focusColor: Colors.transparent,
                          splashColor: Colors.transparent,
                          colorScheme: theme.colorScheme.copyWith(
                            surfaceTint: Colors.transparent,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final group in CapabilityGroup.values)
                              _GroupSection(
                                group: group,
                                mutedSlugs: state.mutedSlugs,
                                onToggle: cubit.toggleMute,
                                theme: theme,
                                l10n: l10n,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.group,
    required this.mutedSlugs,
    required this.onToggle,
    required this.theme,
    required this.l10n,
  });

  final CapabilityGroup group;
  final Set<String> mutedSlugs;
  final Future<void> Function({required String slug, required bool muted})
  onToggle;
  final ThemeData theme;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final tags = CapabilityTag.values.where((t) => t.group == group).toList();
    final groupSlugs = tags.map((t) => t.slug).toSet();
    final mutedInGroup = mutedSlugs.intersection(groupSlugs).length;
    final selectedInGroup = groupSlugs.length - mutedInGroup;

    return AccordionExpansionTile(
      id: group.name,
      // Groups start folded; one with a turned-off tag opens so the
      // exception is visible without hunting for it.
      initiallyExpanded: mutedInGroup > 0,
      // Collapsed groups must not keep chip Wrap in the tree — matches
      // CapabilityChipSet's own guard against building every chip up front.
      maintainState: false,
      title: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _groupLabel(l10n, group),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _groupDescription(l10n, group),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          CapabilityReservedCountSlot(
            visible: true,
            count: selectedInGroup,
            total: groupSlugs.length,
          ),
        ],
      ),
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: context.tt.tightGap,
            right: context.tt.tightGap,
            bottom: context.tt.rowGap,
          ),
          child: Wrap(
            spacing: context.tt.tightGap,
            runSpacing: context.tt.tightGap,
            children: [
              for (final tag in tags)
                CapabilityTagFilterChip(
                  tag: tag,
                  l10n: l10n,
                  theme: theme,
                  selected: !mutedSlugs.contains(tag.slug),
                  isAutomatic: false,
                  onSelected: (enabled) => unawaited(
                    onToggle(slug: tag.slug, muted: !enabled),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _groupLabel(L10n l10n, CapabilityGroup group) =>
      switch (group) {
        CapabilityGroup.logistics => l10n.capabilityGroupLogistics,
        CapabilityGroup.communication => l10n.capabilityGroupCommunication,
        CapabilityGroup.knowledge => l10n.capabilityGroupKnowledge,
        CapabilityGroup.care => l10n.capabilityGroupCare,
        CapabilityGroup.resources => l10n.capabilityGroupResources,
        CapabilityGroup.technical => l10n.capabilityGroupTechnical,
        CapabilityGroup.rpg => l10n.capabilityGroupRpg,
        CapabilityGroup.special => l10n.capabilityGroupSpecial,
      };

  static String _groupDescription(L10n l10n, CapabilityGroup group) =>
      switch (group) {
        CapabilityGroup.logistics => l10n.capabilityGroupLogisticsDescription,
        CapabilityGroup.communication =>
          l10n.capabilityGroupCommunicationDescription,
        CapabilityGroup.knowledge => l10n.capabilityGroupKnowledgeDescription,
        CapabilityGroup.care => l10n.capabilityGroupCareDescription,
        CapabilityGroup.resources => l10n.capabilityGroupResourcesDescription,
        CapabilityGroup.technical => l10n.capabilityGroupTechnicalDescription,
        CapabilityGroup.rpg => l10n.capabilityGroupRpgDescription,
        CapabilityGroup.special => l10n.capabilityGroupSpecialDescription,
      };
}
