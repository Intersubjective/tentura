import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';

import 'package:tentura/features/context/ui/bloc/context_cubit.dart';

import '../bloc/forward_cubit.dart';

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
        buildWhen: (_, c) => c.isSuccess || c.isLoading,
        builder: (_, state) {
          if (state.isLoading && state.candidates.isEmpty) {
            return const Center(
              child: CircularProgressIndicator.adaptive(),
            );
          }
          final filtered = state.filteredCandidates;
          return Column(
            children: [
              // Search
              Padding(
                padding: kPaddingH,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: l10n.searchContacts,
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: cubit.setSearchQuery,
                ),
              ),

              // Candidates list
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          l10n.noReachableContacts,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: kPaddingSmallV,
                        itemCount: filtered.length,
                        separatorBuilder: separatorBuilder,
                        itemBuilder: (_, i) {
                          final profile = filtered[i];
                          final isSelected =
                              state.selectedIds.contains(profile.id);
                          final canSelect = profile.isSeeingMe;
                          return ListTile(
                            enabled: canSelect,
                            leading: AvatarRated(
                              size: 40,
                              profile: profile,
                            ),
                            title: Text(
                              profile.title,
                              style: canSelect
                                  ? null
                                  : theme.textTheme.bodyLarge?.copyWith(
                                      color: theme.colorScheme
                                          .onSurfaceVariant,
                                    ),
                            ),
                            subtitle: canSelect
                                ? null
                                : Text(
                                    l10n.notReachable,
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                            trailing: canSelect
                                ? Checkbox(
                                    value: isSelected,
                                    onChanged: (_) =>
                                        cubit.toggleSelection(profile.id),
                                  )
                                : Icon(
                                    Icons.visibility_off,
                                    size: 20,
                                    color:
                                        theme.colorScheme.onSurfaceVariant,
                                  ),
                            onTap: canSelect
                                ? () => cubit.toggleSelection(profile.id)
                                : null,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar:
          BlocSelector<ForwardCubit, ForwardState, int>(
        selector: (state) => state.selectedCount,
        builder: (_, count) => SafeArea(
          child: Padding(
            padding: kPaddingAll,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Note field
                TextField(
                  decoration: InputDecoration(
                    hintText: l10n.addNoteOptional,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 2,
                  onChanged: cubit.setNote,
                ),
                const SizedBox(height: kSpacingSmall),
                // Forward button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: count > 0 ? cubit.forward : null,
                    icon: const Icon(Icons.send),
                    label: Text(
                      count > 0
                          ? l10n.forwardToCount(count)
                          : l10n.selectRecipients,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
