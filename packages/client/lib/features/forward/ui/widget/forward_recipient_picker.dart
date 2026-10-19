import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/invite_new_person_enabled.dart';
import 'package:tentura/features/forward/domain/forward_draft_policy.dart';
import 'package:tentura/features/forward/domain/forward_target_profile.dart';
import 'package:tentura/features/forward_candidate_context/ui/widget/forward_candidate_context_sheet.dart';
import 'package:tentura/features/invitation/ui/bloc/invitation_cubit.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';
import 'package:tentura/ui/widget/tentura_info_hint_button.dart';
import 'package:tentura/ui/widget/unfocus_sheet_body.dart';

import '../bloc/forward_cubit.dart';
import 'compact_beacon_context_strip.dart';
import 'forward_attribution_dialog.dart';
import 'forward_band_strip.dart';
import 'forward_bottom_composer.dart';
import 'forward_input_decoration.dart';
import 'forward_invite_bar.dart';
import '../model/forward_recipient_row_host.dart';
import 'forward_pinned_tab_bar_delegate.dart';
import 'forward_recipient_row.dart';
import 'forward_scope_links.dart';
import 'forward_beacon_subtitle.dart';
import 'lineage_forward_section.dart';
import 'per_recipient_note_input.dart';

/// Shared recipient picker body for the forward route and beacon-create tab.
class ForwardRecipientPicker extends StatefulWidget {
  const ForwardRecipientPicker({
    required this.beaconId,
    this.embedded = false,
    this.onToggle,
    this.onSendPressed,
    this.sendEnabled = false,
    this.externalActionLoading = false,
    this.isLive = false,
    this.sendLabel,
    this.recipientNoteHint,
    this.promptUncoveredNotes = true,
    this.copyProfile,
    super.key,
  });

  final String beaconId;

  /// When true, omits route chrome (close/search top bar).
  ///
  /// Bottom send uses [onSendPressed] when provided (beacon-create tab).
  final bool embedded;

  /// Overrides what a row toggle does; defaults to
  /// [ForwardCubit.toggleSelection]. The graph composer routes it through its
  /// radius selection.
  final ValueChanged<String>? onToggle;

  /// Host-provided send action (beacon create publish + forward).
  final VoidCallback? onSendPressed;

  /// Whether [onSendPressed] is enabled (recipient + publish readiness).
  final bool sendEnabled;

  /// Loading overlay while the host runs publish before forward.
  final bool externalActionLoading;

  /// Create-session flag: the draft was made live in this screen.
  final bool isLive;

  /// Send button label for the selected count (also on the shared-note
  /// sheet); defaults to «Forward to …».
  final String Function(int count)? sendLabel;

  /// Hint of the per-person note under a picked recipient; defaults to
  /// «Note for {name}». The author's new-Request step sets it.
  final String? recipientNoteHint;

  /// Whether send first offers a note for recipients who have none. Off for a
  /// new Post: its text already is the message.
  final bool promptUncoveredNotes;

  /// Whether the copy (title, tab hints) speaks of a request or a post;
  /// defaults to [ForwardState.profile]. The Post composer sets it, as its
  /// draft is not a loaded beacon.
  final ForwardTargetProfile? copyProfile;

  @override
  State<ForwardRecipientPicker> createState() => _ForwardRecipientPickerState();
}

class _ForwardRecipientPickerState extends State<ForwardRecipientPicker> {
  final _sharedNoteController = TextEditingController();
  final _recipientNoteControllers = <String, TextEditingController>{};
  InvitationCubit? _invitation;

  /// Built on first use: most pickers never start an invite, and a host that
  /// has no invitation backend (a new Post) must still be able to show the
  /// recipient list.
  InvitationCubit get _invitationCubit => _invitation ??= InvitationCubit();
  final _editNoteController = TextEditingController();
  final _scrollController = ScrollController();

  bool _noteExpanded = false;

  /// In-place recipient search (#453): the header turns into a search field
  /// and the list below filters, so the footer Forward button stays visible.
  bool _searchActive = false;
  final _searchController = TextEditingController();
  bool _inviteFlowActive = false;
  bool _hitTestReady = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _hitTestReady = true);
    });
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _closeSearch() {
    _searchController.clear();
    setState(() => _searchActive = false);
  }

  /// Keeps [candidates] in their order, dropping those that do not match
  /// [query] (same match rule as [ForwardState.filterCandidatesByQuery]).
  static List<ForwardCandidate> _filterInPlace(
    List<ForwardCandidate> candidates,
    String query,
  ) {
    if (query.trim().isEmpty) return candidates;
    final matchIds = ForwardState.filterCandidatesByQuery(
      candidates,
      query,
    ).map((c) => c.id).toSet();
    return candidates.where((c) => matchIds.contains(c.id)).toList();
  }

  Widget _buildSearchField({
    required TenturaTokens tt,
    required L10n l10n,
  }) {
    return Row(
      children: [
        Icon(Icons.search, size: 20, color: tt.textMuted),
        SizedBox(width: tt.iconTextGap),
        Expanded(
          child: TextField(
            controller: _searchController,
            autofocus: true,
            style: TenturaText.body(tt.text),
            decoration: InputDecoration.collapsed(
              hintText: l10n.forwardOverlaySearchHint,
              hintStyle: TenturaText.bodySmall(tt.textFaint),
            ),
          ),
        ),
      ],
    );
  }

  void _syncRecipientNoteControllers(ForwardState state) {
    final selected = state.selectedIds;
    for (final id in _recipientNoteControllers.keys.toList()) {
      if (!selected.contains(id)) {
        _recipientNoteControllers.remove(id)?.dispose();
      }
    }
    for (final id in selected) {
      final noteText = state.perRecipientNotes[id] ?? '';
      final existing = _recipientNoteControllers[id];
      if (existing == null) {
        _recipientNoteControllers[id] = TextEditingController(text: noteText);
      } else if (existing.text != noteText) {
        existing.text = noteText;
      }
    }

    final draftCleared =
        state.selectedIds.isEmpty &&
        state.perRecipientNotes.isEmpty &&
        state.skippedPersonalNoteIds.isEmpty &&
        state.note.isEmpty;
    if (draftCleared) {
      _sharedNoteController.text = '';
    } else if (_sharedNoteController.text != state.note) {
      _sharedNoteController.text = state.note;
    }
  }

  void _toggle(ForwardCubit cubit, String userId) {
    final override = widget.onToggle;
    if (override != null) {
      override(userId);
    } else {
      cubit.toggleSelection(userId);
    }
  }

  bool _forwardEdgeActionsEnabled(ForwardCandidate candidate) {
    return candidate.forwardEdgeId != null &&
        forwardEdgeIsCancellable(
          recipientReadAt: candidate.recipientReadAt,
          hasOnwardChild: candidate.hasOnwardChild,
          recipientHasActiveHelpOffer: candidate.recipientHasActiveHelpOffer,
          recipientDeclined: candidate.recipientDeclined,
        );
  }

  Future<void> _handleForwardPressed(BuildContext context) async {
    final cubit = context.read<ForwardCubit>();
    final uncovered = uncoveredRecipientIds(
      selectedIds: cubit.state.selectedIds,
      perRecipientNotes: cubit.state.perRecipientNotes,
      skippedPersonalNoteIds: cubit.state.skippedPersonalNoteIds,
    );
    if (widget.promptUncoveredNotes && uncovered.isNotEmpty) {
      final sent = await _showUncoveredRecipientsSheet(
        context: context,
        cubit: cubit,
        uncoveredIds: uncovered,
      );
      if (!sent || !context.mounted) return;
    }
    if (widget.onSendPressed != null) {
      widget.onSendPressed!();
    } else {
      await _submitForward(context);
    }
  }

  Future<bool> _showUncoveredRecipientsSheet({
    required BuildContext context,
    required ForwardCubit cubit,
    required Set<String> uncoveredIds,
  }) async {
    final names = <String>[];
    for (final id in uncoveredIds) {
      ForwardCandidate? match;
      for (final c in [
        ...cubit.state.candidates,
        ...cubit.state.lineageSuggestions,
      ]) {
        if (c.id == id) {
          match = c;
          break;
        }
      }
      names.add(match?.displayName ?? id);
    }

    final result = await showTenturaAdaptiveSheet<_UncoveredSheetResult>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => _UncoveredRecipientsSheet(
        recipientNames: names,
        selectedCount: cubit.state.selectedIds.length,
        sendLabel: widget.sendLabel,
        initialSharedNote: cubit.state.note,
        onForward: (sharedNote) {
          cubit.setNote(sharedNote);
          uncoveredIds.forEach(cubit.skipPersonalNote);
        },
      ),
    );
    return result == _UncoveredSheetResult.sent;
  }

  Future<void> _submitForward(BuildContext context) async {
    final cubit = context.read<ForwardCubit>();
    List<String>? attributionParentEdgeIds;
    if (cubit.state.profile.showsAttribution &&
        !cubit.state.hasMyOutgoingForward) {
      try {
        final sources = await cubit.fetchInboundSources();
        if (!context.mounted) return;
        if (sources.length > 1) {
          attributionParentEdgeIds = await showForwardAttributionDialog(
            context: context,
            sources: sources,
          );
        }
      } catch (_) {
        // Attribution is optional UX sugar; never block the forward.
      }
    }
    if (!context.mounted) return;
    await cubit.forward(attributionParentEdgeIds: attributionParentEdgeIds);
  }

  @override
  void dispose() {
    for (final c in _recipientNoteControllers.values) {
      c.dispose();
    }
    _recipientNoteControllers.clear();
    _sharedNoteController.dispose();
    _editNoteController.dispose();
    _scrollController.dispose();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    unawaited(_invitation?.close());
    super.dispose();
  }

  Future<void> _editReasons(
    BuildContext context,
    ForwardCubit cubit,
    String recipientId,
    List<String> currentSlugs,
  ) async {
    final l10n = L10n.of(context)!;
    final baseline = Set<String>.from(currentSlugs);
    var selected = Set<String>.from(currentSlugs);

    var existingSlugs = <String>{};
    try {
      final cues = await GetIt.I<CapabilityRepositoryPort>().fetchCues(
        recipientId,
      );
      existingSlugs = cues.viewerVisible.map((c) => c.slug).toSet();
    } catch (_) {}

    if (!context.mounted) return;

    await showTenturaAdaptiveSheet<void>(
      context: context,
      showDragHandle: false,
      builder: (_) => UnfocusSheetBody(
        child: StatefulBuilder(
          builder: (ctx, setModalState) {
            final modalTt = ctx.tt;
            final isDirty =
                selected.length != baseline.length ||
                !selected.containsAll(baseline);
            return TenturaSheetDismissGuard(
              isDirty: isDirty,
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.7,
                minChildSize: 0.4,
                maxChildSize: 0.95,
                builder: (_, scrollController) => Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        modalTt.screenHPadding,
                        modalTt.screenHPadding,
                        modalTt.screenHPadding,
                        modalTt.rowGap,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.forwardReasonPrompt,
                              style: TenturaText.title(modalTt.text),
                            ),
                          ),
                          FilledButton(
                            onPressed: () {
                              cubit.setRecipientReasons(
                                recipientId,
                                selected.toList(),
                              );
                              Navigator.of(ctx).pop();
                            },
                            child: Text(l10n.buttonSave),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: EdgeInsets.only(
                          left: modalTt.screenHPadding,
                          right: modalTt.screenHPadding,
                          bottom: modalTt.sectionGap,
                        ),
                        children: [
                          CapabilityChipSet(
                            selectedSlugs: selected,
                            automaticSlugs: existingSlugs,
                            onChanged: (s) => setModalState(() => selected = s),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _inviteNewPerson(BuildContext context) async {
    if (_inviteFlowActive) return;
    _inviteFlowActive = true;
    try {
      final l10n = L10n.of(context)!;

      final invitation = await _invitationCubit.createInvitation(
        addresseeName: '',
        beaconId: widget.beaconId.isNotEmpty ? widget.beaconId : null,
      );
      if (invitation == null || !context.mounted) return;

      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted) return;

      // A request invite says what it does: who it brings in, to what, and
      // that the link is single-use with a limited life (#452).
      final forRequest = widget.beaconId.isNotEmpty;
      final used = await ShareCodeDialog.show(
        context,
        header: forRequest
            ? l10n.forwardInviteDialogTitle
            : l10n.labelInvitationCode,
        caption: forRequest
            ? l10n.forwardInviteDialogBody(kInvitationDefaultTTL ~/ 24)
            : null,
        link: inviteShareUri(invitation.id),
      );
      // Closed without Copy, Share or a visible QR: the link never left the
      // dialog, so drop the invite instead of leaving a silent one (#454).
      if (!used) {
        await _invitationCubit.deleteInvitationById(invitation.id);
        return;
      }
      if (!context.mounted) return;
      showSnackBar(
        context,
        text: l10n.forwardInviteCreatedHint,
        action: SnackBarAction(
          label: l10n.forwardViewInvitations,
          onPressed: () => unawaited(GetIt.I<RootRouter>().openInvitations()),
        ),
      );
    } finally {
      _inviteFlowActive = false;
    }
  }

  String _lifecycleLabel(L10n l10n, Beacon beacon) => switch (beacon.status) {
    BeaconStatus.open => l10n.beaconLifecycleOpen,
    BeaconStatus.needsMoreHelp => l10n.coordinationMoreHelpNeeded,
    BeaconStatus.enoughHelp => l10n.coordinationEnoughHelp,
    BeaconStatus.cancelled => l10n.beaconLifecycleCancelled,
    BeaconStatus.closed => l10n.beaconLifecycleClosed,
    BeaconStatus.deleted => l10n.beaconLifecycleDeleted,
    BeaconStatus.draft => l10n.beaconLifecycleDraft,
    BeaconStatus.reviewOpen => l10n.beaconLifecycleReviewOpen,
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

    return BlocProvider(
      create: (_) => _invitationCubit,
      child: MultiBlocListener(
        listeners: [
          BlocListener<ForwardCubit, ForwardState>(
            listenWhen: (prev, next) =>
                prev.note != next.note &&
                next.lineageSuggestions.isNotEmpty &&
                next.note.trim().isNotEmpty,
            listener: (context, state) {
              if (_sharedNoteController.text != state.note) {
                _sharedNoteController.text = state.note;
              }
              if (!_noteExpanded) {
                setState(() => _noteExpanded = true);
              }
            },
          ),
          BlocListener<ForwardCubit, ForwardState>(
            listenWhen: (prev, next) => prev.activeFilter != next.activeFilter,
            listener: (context, state) {
              if (_scrollController.hasClients) {
                _scrollController.jumpTo(0);
              }
            },
          ),
        ],
        child: BlocBuilder<ForwardCubit, ForwardState>(
          builder: (_, state) {
            switch (state.candidatesLoad) {
              case ForwardCandidatesLoading():
                return const Center(
                  child: CircularProgressIndicator.adaptive(),
                );
              case ForwardCandidatesError(:final error):
                final details = describeScreenLoadError(
                  error: error,
                  l10n: l10n,
                );
                return ScreenLoadErrorPanel(
                  details: details,
                  onRetry: () => unawaited(cubit.retryLoadCandidates()),
                );
              case ForwardCandidatesEmpty():
              case ForwardCandidatesReady():
                break;
            }

            final beacon = state.beacon;
            final searchQuery = _searchActive ? _searchController.text : '';
            final isFiltering = searchQuery.trim().isNotEmpty;
            final visible = _filterInPlace(
              state.visibleRecipients,
              searchQuery,
            );
            final profile = state.profile;
            final copyProfile = widget.copyProfile ?? profile;
            final showLineageBlock =
                profile.showsLineage &&
                state.activeFilter != ForwardFilter.alreadyInvolved;
            final lineage = showLineageBlock
                ? _filterInPlace(state.lineageSuggestions, searchQuery)
                : const <ForwardCandidate>[];
            final showBandBlock =
                !isFiltering &&
                profile.showsBand &&
                state.activeFilter != ForwardFilter.alreadyInvolved &&
                state.band.isNotEmpty;
            final counts = state.scopeCounts;
            final listIsEmpty =
                state.activeFilter == ForwardFilter.alreadyInvolved
                ? visible.isEmpty
                : visible.isEmpty && lineage.isEmpty;

            final showGenuineEmptyMessage =
                state.candidatesLoad is ForwardCandidatesEmpty && listIsEmpty;

            _syncRecipientNoteControllers(state);

            final actionLoading =
                widget.externalActionLoading ||
                (state.isLoading && state.candidates.isNotEmpty);

            final topBarLeading = _searchActive
                ? IconButton(
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(
                      minWidth: tt.buttonHeight,
                      minHeight: tt.buttonHeight,
                    ),
                    icon: Icon(Icons.arrow_back, size: tt.iconSize),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    onPressed: _closeSearch,
                  )
                : IconButton(
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(
                      minWidth: tt.buttonHeight,
                      minHeight: tt.buttonHeight,
                    ),
                    icon: Icon(Icons.close, size: tt.iconSize),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () {
                      final router = context.router;
                      if (router.canPop()) {
                        unawaited(router.maybePop());
                      } else if (widget.beaconId.isNotEmpty) {
                        unawaited(
                          router.navigate(
                            BeaconViewRoute(
                              id: widget.beaconId,
                              entry: kBeaconEntryForward,
                            ),
                          ),
                        );
                      }
                    },
                  );
            final topBarTitle = _searchActive
                ? _buildSearchField(tt: tt, l10n: l10n)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        copyProfile == ForwardTargetProfile.post
                            ? l10n.forwardPostTitle
                            : l10n.forwardBeaconTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TenturaText.title(tt.text),
                      ),
                      Text(
                        beacon != null && beacon.id.isNotEmpty
                            ? forwardBeaconSubtitle(
                                l10n: l10n,
                                beaconTitle: beacon.title,
                                lifecycleLabel: _lifecycleLabel(
                                  l10n,
                                  beacon,
                                ),
                              )
                            : '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TenturaText.bodySmall(tt.textMuted),
                      ),
                    ],
                  );

            return IgnorePointer(
              ignoring: !_hitTestReady,
              child: Stack(
                children: [
                  AbsorbPointer(
                    absorbing: actionLoading,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!widget.embedded) ...[
                          TenturaTopBar.of(
                            context,
                            leading: topBarLeading,
                            title: topBarTitle,
                            actions: [
                              if (!_searchActive)
                                IconButton(
                                  tooltip: l10n.forwardOverlaySearchHint,
                                  icon: const Icon(Icons.search),
                                  onPressed: () {
                                    setState(() => _searchActive = true);
                                  },
                                )
                              else if (_searchController.text.isNotEmpty)
                                IconButton(
                                  tooltip: MaterialLocalizations.of(
                                    context,
                                  ).cancelButtonLabel,
                                  icon: const Icon(Icons.clear),
                                  onPressed: _searchController.clear,
                                ),
                            ],
                          ),
                          const TenturaHairlineDivider(),
                        ],
                        if (beacon != null &&
                            beacon.id.isNotEmpty &&
                            !widget.embedded) ...[
                          CompactBeaconContextStrip(
                            beacon: beacon,
                            showRequirements: profile.showsRequirements,
                          ),
                          SizedBox(height: tt.rowGap),
                        ],
                        Expanded(
                          child: CustomScrollView(
                            controller: _scrollController,
                            slivers: [
                              if (inviteNewPersonEnabled(
                                beaconId: widget.beaconId,
                                allowsForward:
                                    state.beacon?.viewerCanForward == true,
                                isLive: widget.isLive,
                              ))
                                SliverPersistentHeader(
                                  pinned: true,
                                  delegate: ForwardPinnedSliverHeaderDelegate(
                                    height:
                                        ForwardInviteBar.buttonHeight +
                                        tt.rowGap * 2,
                                    child: ForwardInviteBar(
                                      hasSelection:
                                          state.selectedIds.isNotEmpty,
                                      onInvite: () => unawaited(
                                        _inviteNewPerson(context),
                                      ),
                                      onClearSelection: cubit.clearSelection,
                                    ),
                                  ),
                                ),
                              if (showBandBlock)
                                SliverToBoxAdapter(
                                  child: ForwardBandStrip(
                                    band: state.band,
                                    candidates: state.candidates,
                                    selectedIds: state.selectedIds,
                                    beacon: beacon,
                                    recipientNoteHint: widget.recipientNoteHint,
                                    recipientReasons: state.recipientReasons,
                                    recipientNoteControllers:
                                        _recipientNoteControllers,
                                    onRecipientNoteChanged:
                                        cubit.setRecipientNote,
                                    skippedPersonalNoteIds:
                                        state.skippedPersonalNoteIds,
                                    onSkipPersonalNote: cubit.skipPersonalNote,
                                    onToggle: (userId) =>
                                        _toggle(cubit, userId),
                                    onEditReasons: (userId) => unawaited(
                                      _editReasons(
                                        context,
                                        cubit,
                                        userId,
                                        state.recipientReasons[userId] ??
                                            const [],
                                      ),
                                    ),
                                  ),
                                ),
                              SliverPersistentHeader(
                                pinned: true,
                                delegate: ForwardPinnedSliverHeaderDelegate(
                                  height: ForwardScopeLinks.preferredHeight(
                                    tt,
                                    MediaQuery.textScalerOf(context),
                                  ),
                                  child: ForwardScopeLinks(
                                    activeFilter: state.activeFilter,
                                    counts: counts,
                                    onScopeChanged: cubit.setFilter,
                                    profile: copyProfile,
                                  ),
                                ),
                              ),
                              if (lineage.isNotEmpty)
                                SliverToBoxAdapter(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: _buildLineageList(
                                      context: context,
                                      cubit: cubit,
                                      state: state,
                                      lineage: lineage,
                                      beacon: beacon,
                                    ),
                                  ),
                                ),
                              if (listIsEmpty)
                                SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: Center(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: tt.screenHPadding,
                                      ),
                                      child: Text(
                                        showGenuineEmptyMessage
                                            ? l10n.noReachableContacts
                                            : l10n.labelNothingHere,
                                        textAlign: TextAlign.center,
                                        style: TenturaText.bodySmall(
                                          tt.textMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              else ...[
                                SliverPadding(
                                  padding: EdgeInsets.only(bottom: tt.rowGap),
                                  sliver: SliverList.list(
                                    children: _buildVisibleRecipientList(
                                      context: context,
                                      cubit: cubit,
                                      state: state,
                                      visible: visible,
                                      beacon: beacon,
                                    ),
                                  ),
                                ),
                                const SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: SizedBox.shrink(),
                                ),
                              ],
                            ],
                          ),
                        ),
                        ForwardBottomComposer(
                          sendLabel: widget.sendLabel,
                          selectedIds: state.selectedIds,
                          noteExpanded: _noteExpanded,
                          onToggleNoteExpanded: _toggleNote,
                          sharedNoteController: _sharedNoteController,
                          onSharedNoteChanged: cubit.setNote,
                          showSuggestedNoteHelper:
                              state.lineageSuggestions.isNotEmpty &&
                              state.note.trim().isNotEmpty &&
                              _noteExpanded,
                          onForward: widget.onSendPressed != null
                              ? (widget.sendEnabled
                                    ? () => unawaited(
                                        _handleForwardPressed(context),
                                      )
                                    : null)
                              : (!widget.embedded && state.selectedCount > 0
                                    ? () => unawaited(
                                        _handleForwardPressed(context),
                                      )
                                    : null),
                        ),
                      ],
                    ),
                  ),
                  if (actionLoading)
                    const Positioned.fill(
                      child: Center(
                        child: CircularProgressIndicator.adaptive(),
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

  List<Widget> _buildLineageList({
    required BuildContext context,
    required ForwardCubit cubit,
    required ForwardState state,
    required List<ForwardCandidate> lineage,
    required Beacon? beacon,
  }) {
    final tt = context.tt;
    final children = <Widget>[
      LineageForwardSectionHeader(
        onClear: cubit.clearLineageSuggestions,
      ),
      for (var i = 0; i < lineage.length; i++) ...[
        if (i > 0) const TenturaHairlineDivider(),
        ForwardRecipientRow(
          host: ForwardRecipientRowHost.pickerLineage,
          candidate: lineage[i],
          requiredCapabilitySlugs: beacon?.needs ?? const {},
          isSelected: state.selectedIds.contains(lineage[i].id),
          onToggle: () => _toggle(cubit, lineage[i].id),
          onOpenDetails: () => unawaited(
            showForwardCandidateContextSheet(
              sourceContext: context,
              forwardCubit: cubit,
              candidate: lineage[i],
            ),
          ),
          reasonSlugs: state.profile.showsReasons
              ? state.recipientReasons[lineage[i].id] ?? const []
              : const [],
          onEditReasons: !state.profile.showsReasons
              ? null
              : () => unawaited(
                  _editReasons(
                    context,
                    cubit,
                    lineage[i].id,
                    state.recipientReasons[lineage[i].id] ?? const [],
                  ),
                ),
        ),
        if (state.selectedIds.contains(lineage[i].id) &&
            !state.skippedPersonalNoteIds.contains(lineage[i].id))
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tt.screenHPadding,
            ),
            child: PerRecipientNoteInput(
              profile: lineage[i].profile,
              controller: _recipientNoteControllers[lineage[i].id]!,
              onChanged: (text) => cubit.setRecipientNote(lineage[i].id, text),
              onClose: () => cubit.skipPersonalNote(lineage[i].id),
              hintText: widget.recipientNoteHint,
            ),
          ),
      ],
      const TenturaHairlineDivider(),
    ];
    return children;
  }

  List<Widget> _buildVisibleRecipientList({
    required BuildContext context,
    required ForwardCubit cubit,
    required ForwardState state,
    required List<ForwardCandidate> visible,
    required Beacon? beacon,
  }) {
    final tt = context.tt;
    final children = <Widget>[];

    for (var i = 0; i < visible.length; i++) {
      if (i > 0) {
        children.add(const TenturaHairlineDivider());
      }
      children.add(
        ForwardRecipientRow(
          host: ForwardRecipientRowHost.pickerStandard,
          candidate: visible[i],
          requiredCapabilitySlugs: beacon?.needs ?? const {},
          isSelected: state.selectedIds.contains(visible[i].id),
          onToggle: () => _toggle(cubit, visible[i].id),
          onOpenDetails: () => unawaited(
            showForwardCandidateContextSheet(
              sourceContext: context,
              forwardCubit: cubit,
              candidate: visible[i],
            ),
          ),
          reasonSlugs: state.profile.showsReasons
              ? state.recipientReasons[visible[i].id] ?? const []
              : const [],
          onEditReasons: !state.profile.showsReasons
              ? null
              : () => unawaited(
                  _editReasons(
                    context,
                    cubit,
                    visible[i].id,
                    state.recipientReasons[visible[i].id] ?? const [],
                  ),
                ),
          onEditForward: _forwardEdgeActionsEnabled(visible[i])
              ? () {
                  _editNoteController.text = visible[i].myForwardNote ?? '';
                  cubit.startEditForward(visible[i].id);
                }
              : null,
          onCancelForward: _forwardEdgeActionsEnabled(visible[i])
              ? () => unawaited(cubit.cancelForward(visible[i].id))
              : null,
        ),
      );
      if (state.editingRecipientId == visible[i].id) {
        children.add(
          ForwardEditPanel(
            controller: _editNoteController,
            onNoteChanged: cubit.setEditNote,
            onSave: () => unawaited(cubit.saveForwardEdit()),
            onCancel: cubit.cancelEditForward,
          ),
        );
      }
      if (state.selectedIds.contains(visible[i].id) &&
          !state.skippedPersonalNoteIds.contains(visible[i].id)) {
        children.add(
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tt.screenHPadding,
            ),
            child: PerRecipientNoteInput(
              profile: visible[i].profile,
              controller: _recipientNoteControllers[visible[i].id]!,
              onChanged: (text) => cubit.setRecipientNote(visible[i].id, text),
              onClose: () => cubit.skipPersonalNote(visible[i].id),
              hintText: widget.recipientNoteHint,
            ),
          ),
        );
      }
    }

    return children;
  }
}

class ForwardEditPanel extends StatelessWidget {
  const ForwardEditPanel({
    required this.controller,
    required this.onNoteChanged,
    required this.onSave,
    required this.onCancel,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onNoteChanged;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tt.screenHPadding,
      ).copyWith(bottom: tt.rowGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            onChanged: onNoteChanged,
            minLines: 2,
            maxLines: 5,
            decoration: forwardNoteInputDecoration(
              context,
              hintText: l10n.forwardNotePlaceholder,
            ),
          ),
          SizedBox(height: tt.rowGap),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onCancel,
                child: Text(l10n.buttonCancel),
              ),
              SizedBox(width: tt.iconTextGap),
              FilledButton(
                onPressed: onSave,
                child: Text(l10n.buttonSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _UncoveredSheetResult { sent }

class _UncoveredRecipientsSheet extends StatefulWidget {
  const _UncoveredRecipientsSheet({
    required this.recipientNames,
    required this.selectedCount,
    required this.initialSharedNote,
    required this.onForward,
    this.sendLabel,
  });

  final List<String> recipientNames;
  final int selectedCount;

  /// Confirm button label; defaults to «Forward to …».
  final String Function(int count)? sendLabel;
  final String initialSharedNote;
  final void Function(String sharedNote) onForward;

  @override
  State<_UncoveredRecipientsSheet> createState() =>
      _UncoveredRecipientsSheetState();
}

class _UncoveredRecipientsSheetState extends State<_UncoveredRecipientsSheet> {
  late final TextEditingController _sharedNoteController;
  late final String _initialSnapshot;

  @override
  void initState() {
    super.initState();
    _initialSnapshot = widget.initialSharedNote;
    _sharedNoteController = TextEditingController(text: _initialSnapshot);
  }

  @override
  void dispose() {
    _sharedNoteController.dispose();
    super.dispose();
  }

  bool get _isDirty =>
      _sharedNoteController.text.trim() != _initialSnapshot.trim();

  Future<void> _requestClose() => TenturaSheetDismissGuard.requestClose(
    context,
    isDirty: _isDirty,
    useRootNavigator: true,
  );

  void _forward() {
    widget.onForward(_sharedNoteController.text.trim());
    Navigator.of(context).pop(_UncoveredSheetResult.sent);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;

    return UnfocusSheetBody(
      child: TenturaSheetDismissGuard(
        isDirty: _isDirty,
        useRootNavigator: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mediaHeight = MediaQuery.sizeOf(context).height;
            final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
            final maxHeight = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : mediaHeight * 0.9;
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Padding(
                padding: EdgeInsets.only(
                  left: tt.screenHPadding,
                  right: tt.screenHPadding,
                  top: tt.sectionGap,
                  bottom: viewInsets + tt.sectionGap,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.forwardUncoveredRecipientsTitle,
                            style: TenturaText.title(tt.text),
                          ),
                        ),
                        TenturaInfoHintButton(
                          fullText: l10n.forwardUncoveredSharedNoteInfo,
                          semanticsLabel: l10n.forwardUncoveredSharedNoteInfo,
                        ),
                      ],
                    ),
                    SizedBox(height: tt.rowGap),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              l10n.forwardUncoveredSharedNoteInfo,
                              style: TenturaText.bodySmall(tt.textMuted),
                            ),
                            SizedBox(height: tt.rowGap),
                            Text(
                              l10n.forwardUncoveredRecipientsListCaption,
                              style: TenturaText.bodySmall(tt.textMuted),
                            ),
                            SizedBox(height: tt.tightGap),
                            for (final name in widget.recipientNames)
                              Padding(
                                padding: EdgeInsets.only(bottom: tt.tightGap),
                                child: Text(
                                  name,
                                  style: TenturaText.body(tt.text),
                                ),
                              ),
                            SizedBox(height: tt.rowGap),
                            TextField(
                              controller: _sharedNoteController,
                              onChanged: (_) => setState(() {}),
                              minLines: 2,
                              maxLines: 4,
                              decoration: forwardNoteInputDecoration(
                                context,
                                hintText:
                                    l10n.forwardUncoveredSharedNoteFieldHint,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: tt.rowGap),
                    TextButton(
                      onPressed: _requestClose,
                      child: Text(l10n.buttonCancel),
                    ),
                    SizedBox(
                      height: tt.buttonHeight,
                      child: FilledButton(
                        onPressed: _forward,
                        child: Text(
                          (widget.sendLabel ?? l10n.forwardToCount)(
                            widget.selectedCount,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
