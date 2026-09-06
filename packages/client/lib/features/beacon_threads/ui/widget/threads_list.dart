import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_child_requests_section.dart';
import 'package:tentura/features/beacon_threads/ui/widget/item_card.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/focus_flash_highlight.dart';

import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';

class ThreadsList extends StatelessWidget {
  const ThreadsList({
    required this.beaconState,
    required this.onOpenGeneral,
    this.onSwitchToPeopleTab,
    this.focusGeneral = false,
    this.selectedGeneral = false,
    super.key,
  });

  final BeaconViewState beaconState;
  final VoidCallback onOpenGeneral;

  /// General card face pile tap — switches to People tab.
  final VoidCallback? onSwitchToPeopleTab;

  final bool focusGeneral;
  final bool selectedGeneral;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;

    return BlocBuilder<ThreadsCubit, ThreadsState>(
      buildWhen: (prev, curr) {
        if (curr.status is StateIsLoading && prev.threads.isEmpty) {
          return true;
        }
        return prev != curr;
      },
      builder: (context, threadsState) {
        if (threadsState.status is StateIsLoading &&
            threadsState.threads.isEmpty) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }

        final general = threadsState.general;
        final showGeneral = general != null;
        final admitted = !beaconState.isRoomAdmissionBlocked;

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tt.screenHPadding,
            vertical: tt.rowGap,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (beaconState.isRoomAdmissionBlocked)
                Padding(
                  padding: EdgeInsets.only(top: tt.sectionGap * 2),
                  child: Center(
                    child: Text(
                      beaconState.coordinationDeniesRoomAdmission
                          ? l10n.beaconRoomNoAdmission
                          : l10n.beaconRoomWaitingForApproval,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else if (!showGeneral)
                Padding(
                  padding: EdgeInsets.only(top: tt.sectionGap * 2),
                  child: Center(
                    child: Text(
                      l10n.beaconItemsEmptyPlaceholder,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              if (showGeneral) ...[
                SizedBox(height: tt.rowGap),
                FocusFlashHighlight(
                  active: focusGeneral,
                  child: ItemCard(
                    key: threadRowKey(general),
                    thread: general,
                    viewerProfile: beaconState.myProfile,
                    participants: beaconState.roomParticipants,
                    resolvedUnreadCount:
                        threadsState.resolvedUnreadFor(general),
                    isSelected: selectedGeneral,
                    onOpenThread: (_) => onOpenGeneral(),
                    generalBeacon: beaconState.beacon,
                    generalInvolvedProfiles: beaconState.activeHelpOfferUsers,
                    onGeneralFacePileTap: onSwitchToPeopleTab,
                  ),
                ),
              ],
              if (admitted) ...[
                const _HierarchyBootstrap(),
                BeaconChildRequestsSection(beaconState: beaconState),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HierarchyBootstrap extends StatefulWidget {
  const _HierarchyBootstrap();

  @override
  State<_HierarchyBootstrap> createState() => _HierarchyBootstrapState();
}

class _HierarchyBootstrapState extends State<_HierarchyBootstrap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<BeaconHierarchyCubit>().load());
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
