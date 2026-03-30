import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/context/ui/bloc/context_cubit.dart';

import '../../domain/entity/forward_candidate.dart';
import '../bloc/forward_cubit.dart';
import '../widget/beacon_forward_header.dart';
import '../widget/forward_candidate_tile.dart';
import '../widget/forward_filter_bar.dart';
import '../widget/per_recipient_notes_panel.dart';

@RoutePage()
class ForwardBeaconScreen extends StatelessWidget
    implements AutoRouteWrapper {
  const ForwardBeaconScreen({
    @PathParam('id') this.beaconId = '',
    super.key,
  });

  final String beaconId;

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
    create: (_) => ForwardCubit(
      beaconId: beaconId,
      context: context.read<ContextCubit>().state.selected,
    ),
    child: BlocListener<ForwardCubit, ForwardState>(
      listener: commonScreenBlocListener,
      child: this,
    ),
  );

  bool _listIsEmpty(ForwardBeaconListSections sections, ForwardState state) {
    if (state.activeFilter == ForwardFilter.all) {
      return sections.isEmptyAllLayout;
    }
    return sections.filteredFlatList.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final cubit = context.read<ForwardCubit>();
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.forwardBeaconTitle),
      ),
      body: BlocBuilder<ForwardCubit, ForwardState>(
        builder: (_, state) {
          if (state.isLoading && state.candidates.isEmpty) {
            return const Center(
              child: CircularProgressIndicator.adaptive(),
            );
          }
          final sections = state.computeBeaconListSections();
          final beacon = state.beacon;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (beacon != null && beacon.id.isNotEmpty)
                BeaconForwardHeader(beacon: beacon),
              ForwardFilterBar(
                activeFilter: state.activeFilter,
                onFilterSelected: cubit.setFilter,
              ),
              Padding(
                padding: kPaddingH,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: l10n.searchContacts,
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: cubit.setSearchQuery,
                ),
              ),
              Expanded(
                child: _listIsEmpty(sections, state)
                    ? Center(
                        child: Text(
                          state.candidates.isEmpty
                              ? l10n.noReachableContacts
                              : l10n.labelNothingHere,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView(
                        padding: kPaddingSmallV,
                        children: [
                          if (state.activeFilter == ForwardFilter.all) ...[
                            if (sections.recommended.isNotEmpty) ...[
                              _SectionTitle(l10n.forwardSectionRecommended),
                              ..._tiles(
                                sections.recommended,
                                state,
                                cubit,
                              ),
                            ],
                            if (sections.other.isNotEmpty) ...[
                              _SectionTitle(l10n.forwardSectionOthers),
                              ..._tiles(
                                sections.other,
                                state,
                                cubit,
                              ),
                            ],
                            if (sections.unavailable.isNotEmpty) ...[
                              _SectionTitle(l10n.forwardSectionUnavailable),
                              ..._tiles(
                                sections.unavailable,
                                state,
                                cubit,
                              ),
                            ],
                            if (sections.notReachable.isNotEmpty) ...[
                              _SectionTitle(l10n.forwardSectionNotReachable),
                              ..._tiles(
                                sections.notReachable,
                                state,
                                cubit,
                              ),
                            ],
                          ] else ...[
                            ..._tiles(
                              sections.filteredFlatList,
                              state,
                              cubit,
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: BlocBuilder<ForwardCubit, ForwardState>(
        builder: (_, state) {
          final profilesById = {
            for (final c in state.candidates) c.id: c.profile,
          };
          return SafeArea(
            child: Padding(
              padding: kPaddingAll,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: l10n.forwardSharedNoteHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    maxLines: 2,
                    onChanged: cubit.setNote,
                  ),
                  PerRecipientNotesPanel(
                    selectedIds: state.selectedIds,
                    profilesById: profilesById,
                    notes: state.perRecipientNotes,
                    onNoteChanged: cubit.setRecipientNote,
                  ),
                  const SizedBox(height: kSpacingSmall),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: state.selectedCount > 0
                          ? cubit.forward
                          : null,
                      icon: const Icon(Icons.send),
                      label: Text(
                        state.selectedCount > 0
                            ? l10n.forwardToCount(state.selectedCount)
                            : l10n.selectRecipients,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static List<Widget> _tiles(
    List<ForwardCandidate> candidates,
    ForwardState state,
    ForwardCubit cubit,
  ) => [
    for (var i = 0; i < candidates.length; i++) ...[
      if (i > 0) separatorBuilder(null, null),
      ForwardCandidateTile(
        candidate: candidates[i],
        isSelected: state.selectedIds.contains(candidates[i].id),
        onToggle: () => cubit.toggleSelection(candidates[i].id),
      ),
    ],
  ];
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: kPaddingH.add(kPaddingSmallT),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
