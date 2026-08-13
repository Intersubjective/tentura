import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_group.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/accordion_expansion.dart';

import '../bloc/routing_mute_cubit.dart';

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
    return Scaffold(
      appBar: TenturaTopBar.of(
        context,
        leading: const AutoLeadingButton(),
        title: Text(l10n.routingMuteScreenTitle),
      ),
      body: BlocBuilder<RoutingMuteCubit, RoutingMuteState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final cubit = context.read<RoutingMuteCubit>();
          final isCompact = context.windowClass == WindowClass.compact;
          return TenturaContentColumn(
            child: ListView(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    context.tt.screenHPadding,
                    context.tt.sectionGap,
                    context.tt.screenHPadding,
                    context.tt.tightGap,
                  ),
                  child: Text(
                    l10n.routingMuteScreenDescription,
                    style: TenturaText.bodySmall(context.tt.textMuted),
                  ),
                ),
                AccordionExpansionGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final group in CapabilityGroup.values)
                        _GroupSection(
                          group: group,
                          mutedSlugs: state.mutedSlugs,
                          initiallyExpanded: !isCompact,
                          onToggle: cubit.toggleMute,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.group,
    required this.mutedSlugs,
    required this.initiallyExpanded,
    required this.onToggle,
  });

  final CapabilityGroup group;
  final Set<String> mutedSlugs;
  final bool initiallyExpanded;
  final Future<void> Function({required String slug, required bool muted})
  onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tags = CapabilityTag.values.where((t) => t.group == group).toList();
    final groupSlugs = tags.map((t) => t.slug).toSet();
    final mutedInGroup = mutedSlugs.intersection(groupSlugs).length;
    final expanded = initiallyExpanded || mutedInGroup > 0;

    return AccordionExpansionTile(
      id: group.name,
      initiallyExpanded: expanded,
      maintainState: false,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _groupLabel(l10n, group),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            _groupDescription(l10n, group),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      children: [
        for (final tag in tags)
          SwitchListTile(
            title: Text(tag.labelOf(l10n)),
            value: mutedSlugs.contains(tag.slug),
            onChanged: (muted) => unawaited(
              onToggle(slug: tag.slug, muted: muted),
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
        CapabilityGroup.special => l10n.capabilityGroupSpecialDescription,
      };
}
