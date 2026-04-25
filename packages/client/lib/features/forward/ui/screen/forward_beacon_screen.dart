import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/forward_cubit.dart';
import '../widget/compact_beacon_context_strip.dart';
import '../widget/forward_bottom_composer.dart';
import '../widget/forward_recipient_row.dart';
import '../widget/forward_scope_links.dart';
import '../widget/forward_search_overlay.dart';
import '../widget/forward_top_bar.dart';
import '../widget/per_recipient_note_input.dart';

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
    return const ForwardBeaconPage();
  }
}

/// Forward beacon recipient picker (compact operational layout).
class ForwardBeaconPage extends StatefulWidget {
  const ForwardBeaconPage({super.key});

  @override
  State<ForwardBeaconPage> createState() => _ForwardBeaconPageState();
}

class _ForwardBeaconPageState extends State<ForwardBeaconPage> {
  final _sharedNoteController = TextEditingController();
  final _recipientNoteControllers = <String, TextEditingController>{};
  final _personalizedNoteEditorOpenIds = <String>{};

  bool _noteExpanded = false;
  bool _searchOverlayOpen = false;

  void _syncRecipientNoteControllers(ForwardState state) {
    final selected = state.selectedIds;
    for (final id in _recipientNoteControllers.keys.toList()) {
      if (!selected.contains(id)) {
        _recipientNoteControllers.remove(id)?.dispose();
      }
    }
    for (final id in selected) {
      _recipientNoteControllers.putIfAbsent(
        id,
        () => TextEditingController(text: state.perRecipientNotes[id] ?? ''),
      );
    }
  }

  void _prunePersonalizedNoteEditors(ForwardState state) {
    _personalizedNoteEditorOpenIds.removeWhere(
      (id) => !state.selectedIds.contains(id),
    );
  }

  void _togglePersonalizedNoteEditor(String userId) {
    setState(() {
      if (_personalizedNoteEditorOpenIds.contains(userId)) {
        _personalizedNoteEditorOpenIds.remove(userId);
      } else {
        _personalizedNoteEditorOpenIds.add(userId);
      }
    });
  }

  @override
  void dispose() {
    for (final c in _recipientNoteControllers.values) {
      c.dispose();
    }
    _recipientNoteControllers.clear();
    _sharedNoteController.dispose();
    super.dispose();
  }

  String _lifecycleLabel(L10n l10n, Beacon beacon) => switch (beacon.lifecycle) {
        BeaconLifecycle.open => l10n.beaconLifecycleOpen,
        BeaconLifecycle.closed => l10n.beaconLifecycleClosed,
        BeaconLifecycle.deleted => l10n.beaconLifecycleDeleted,
        BeaconLifecycle.draft => l10n.beaconLifecycleDraft,
        BeaconLifecycle.pendingReview => l10n.beaconLifecyclePendingReview,
        BeaconLifecycle.closedReviewOpen =>
          l10n.beaconLifecycleClosedReviewOpen,
        BeaconLifecycle.closedReviewComplete =>
          l10n.beaconLifecycleClosedReviewComplete,
      };

  void _toggleNote() {
    setState(() {
      _noteExpanded = !_noteExpanded;
      if (_noteExpanded) {
        _sharedNoteController.text = context.read<ForwardCubit>().state.note;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final cubit = context.read<ForwardCubit>();

    return Scaffold(
      backgroundColor: tt.bg,
      body: SafeArea(
        child: BlocBuilder<ForwardCubit, ForwardState>(
          builder: (_, state) {
            if (state.isLoading && state.candidates.isEmpty) {
              return const Center(
                child: CircularProgressIndicator.adaptive(),
              );
            }

            final beacon = state.beacon;
            final visible = state.visibleRecipients;
            final counts = state.scopeCounts;

            _syncRecipientNoteControllers(state);
            _prunePersonalizedNoteEditors(state);

            return Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ForwardTopBar(
                      titleLine: l10n.forwardBeaconTitle,
                      subtitleLine: beacon != null && beacon.id.isNotEmpty
                          ? forwardBeaconSubtitle(
                              l10n: l10n,
                              beaconTitle: beacon.title,
                              lifecycleLabel: _lifecycleLabel(l10n, beacon),
                            )
                          : '',
                      searchTooltip: l10n.forwardOverlaySearchHint,
                      onSearchPressed: () {
                        setState(() => _searchOverlayOpen = true);
                      },
                      onFilterPressed: () {
                        // Advanced filters sheet (later).
                      },
                    ),
                    const TenturaHairlineDivider(),
                    if (beacon != null && beacon.id.isNotEmpty) ...[
                      CompactBeaconContextStrip(beacon: beacon),
                      const SizedBox(height: 8),
                    ],
                    ForwardScopeLinks(
                      activeFilter: state.activeFilter,
                      counts: counts,
                      onScopeChanged: cubit.setFilter,
                    ),
                    Expanded(
                      child: visible.isEmpty
                          ? Center(
                              child: Padding(
                                padding: kPaddingH,
                                child: Text(
                                  state.candidates.isEmpty
                                      ? l10n.noReachableContacts
                                      : l10n.labelNothingHere,
                                  textAlign: TextAlign.center,
                                  style: TenturaText.meta(tt.textMuted),
                                ),
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.only(bottom: 8),
                              children: [
                                for (var i = 0; i < visible.length; i++) ...[
                                  if (i > 0) const TenturaHairlineDivider(),
                                  ForwardRecipientRow(
                                    candidate: visible[i],
                                    isSelected: state.selectedIds
                                        .contains(visible[i].id),
                                    onToggle: () =>
                                        cubit.toggleSelection(visible[i].id),
                                    personalizedNoteEditorOpen:
                                        _personalizedNoteEditorOpenIds
                                            .contains(visible[i].id),
                                    onTogglePersonalizedNoteEditor: () =>
                                        _togglePersonalizedNoteEditor(
                                      visible[i].id,
                                    ),
                                  ),
                                  if (state.selectedIds
                                          .contains(visible[i].id) &&
                                      _personalizedNoteEditorOpenIds
                                          .contains(visible[i].id))
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: tt.screenHPadding,
                                      ),
                                      child: PerRecipientNoteInput(
                                        profile: visible[i].profile,
                                        controller: _recipientNoteControllers[
                                            visible[i].id]!,
                                        onChanged: (text) => cubit
                                            .setRecipientNote(
                                          visible[i].id,
                                          text,
                                        ),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                    ),
                    ForwardBottomComposer(
                      selectedIds: state.selectedIds,
                      noteExpanded: _noteExpanded,
                      onToggleNoteExpanded: _toggleNote,
                      sharedNoteController: _sharedNoteController,
                      onSharedNoteChanged: cubit.setNote,
                      onForward:
                          state.selectedCount > 0 ? cubit.forward : null,
                    ),
                  ],
                ),
                if (_searchOverlayOpen)
                  Positioned.fill(
                    child: ForwardSearchOverlay(
                      onClose: () {
                        setState(() => _searchOverlayOpen = false);
                      },
                      recipientNoteControllers: _recipientNoteControllers,
                      onRecipientNoteChanged: cubit.setRecipientNote,
                      personalizedNoteEditorOpenIds:
                          _personalizedNoteEditorOpenIds,
                      onTogglePersonalizedNoteEditor:
                          _togglePersonalizedNoteEditor,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
