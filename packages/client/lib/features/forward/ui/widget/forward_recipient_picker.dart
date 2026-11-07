import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/entity/forward_reach.dart';
import 'package:tentura/features/forward/domain/invite_new_person_enabled.dart';
import 'package:tentura/features/forward/domain/forward_draft_policy.dart';
import 'package:tentura/features/forward/domain/forward_target_profile.dart';
import 'package:tentura/features/forward_candidate_context/ui/widget/forward_candidate_context_sheet.dart';
import 'package:tentura/features/invitation/ui/bloc/invitation_cubit.dart';
import 'package:tentura/features/post_view/ui/post_remaining_label.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';
import 'package:tentura/ui/widget/tentura_info_hint_button.dart';
import 'package:tentura/ui/widget/unfocus_sheet_body.dart';

import '../bloc/forward_cubit.dart';
import 'beacon_invite_flow.dart';
import 'compact_beacon_context_strip.dart';
import 'forward_attribution_dialog.dart';
import 'forward_band_strip.dart';
import 'forward_bottom_composer.dart';
import 'forward_input_decoration.dart';
import 'forward_invite_bar.dart';
import '../model/forward_recipient_row_host.dart';
import 'forward_recipient_picker_entry.dart';
import 'forward_recipient_wider_expander.dart';
import 'forward_pinned_tab_bar_delegate.dart';
import 'forward_scope_links.dart';
import 'forward_tag_picker.dart';
import 'forward_beacon_subtitle.dart';
import 'lineage_forward_section.dart';

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
    this.debugOnRowBuild,
    this.header,
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

  /// Test hook (#807): called when a recipient row entry rebuilds.
  @visibleForTesting
  final void Function(String candidateId)? debugOnRowBuild;

  /// Optional block above the search field and recipient list (Post composer).
  final Widget? header;

  /// «Your connections» header (#440).
  static const directSectionKey = Key('ForwardRecipientPicker.directSection');

  /// «Through your connections» header (#440).
  static const throughSectionKey = Key('ForwardRecipientPicker.throughSection');

  /// «Wider network» header (#440).
  static const widerSectionKey = Key('ForwardRecipientPicker.widerSection');

  /// Collapsed wider-network expander (#440 mn5y.4).
  static const widerExpanderKey = Key('ForwardRecipientPicker.widerExpander');

  /// «New» mutual-trust-this-week header (#894).
  static const newSectionKey = Key('ForwardRecipientPicker.newSection');

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
  bool _widerNetworkExpanded = false;
  bool _inviteFlowActive = false;
  bool _hitTestReady = false;
  final _expandedPersonalNoteRecipientId = ValueNotifier<String?>(null);

  void _collapseExpandedPersonalNote() {
    if (_expandedPersonalNoteRecipientId.value != null) {
      _expandedPersonalNoteRecipientId.value = null;
    }
  }

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

  void _finishEmbeddedSearch() {
    FocusManager.instance.primaryFocus?.unfocus();
    _searchController.clear();
    setState(() {});
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
    bool autofocus = true,
  }) {
    return Row(
      children: [
        Icon(Icons.search, size: 20, color: tt.textMuted),
        SizedBox(width: tt.iconTextGap),
        Expanded(
          child: TextField(
            controller: _searchController,
            autofocus: autofocus,
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

  Widget _buildTopBarSearchField({
    required TenturaTokens tt,
    required L10n l10n,
  }) {
    // Mounted only while searching: Android/system back closes the search,
    // as the header back arrow does, instead of leaving Forward (#453).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: _buildSearchField(tt: tt, l10n: l10n),
    );
  }

  void _syncRecipientNoteControllers(ForwardState state) {
    final selected = state.selectedIds;
    final draftCleared =
        state.selectedIds.isEmpty &&
        state.perRecipientNotes.isEmpty &&
        state.note.isEmpty;
    if (draftCleared) {
      for (final c in _recipientNoteControllers.values) {
        c.dispose();
      }
      _recipientNoteControllers.clear();
    }
    for (final id in selected) {
      final noteText = state.perRecipientNotes[id] ?? '';
      final existing = _recipientNoteControllers[id];
      if (existing == null) {
        _recipientNoteControllers[id] = TextEditingController(text: noteText);
      } else if (existing.text != noteText &&
          _expandedPersonalNoteRecipientId.value != id) {
        existing.text = noteText;
      }
    }

    if (draftCleared) {
      _sharedNoteController.text = '';
    } else if (_sharedNoteController.text != state.note && !_noteExpanded) {
      _sharedNoteController.text = state.note;
    }
  }

  void _toggle(ForwardCubit cubit, String userId) {
    final expanded = _expandedPersonalNoteRecipientId.value;
    if (expanded != null) {
      if (expanded != userId || cubit.state.selectedIds.contains(userId)) {
        _expandedPersonalNoteRecipientId.value = null;
      }
    }
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
    );
    if (widget.promptUncoveredNotes &&
        uncovered.isNotEmpty &&
        cubit.state.selectedIds.length == 1) {
      // With one person a «shared» note is just the personal note they
      // already left empty inline, so do not ask a second time (#669).
    } else if (widget.promptUncoveredNotes && uncovered.isNotEmpty) {
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
        },
      ),
    );
    return result == _UncoveredSheetResult.sent;
  }

  Future<void> _submitForward(BuildContext context) async {
    final cubit = context.read<ForwardCubit>();
    List<String>? attributionParentEdgeIds;
    if (_profile(cubit.state).showsAttribution &&
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
    _expandedPersonalNoteRecipientId.dispose();
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

    if (_needsMakeLiveBeforeInvite(context)) {
      final l10n = L10n.of(context)!;
      final confirmed = await TenturaConfirmDialog.show(
        context: context,
        title: l10n.beaconCreateInviteMakeLiveConfirmTitle,
        content: l10n.beaconCreateInviteMakeLiveConfirmBody,
        confirmLabel: l10n.beaconMakeLiveWithoutSending,
      );
      if (confirmed != true || !context.mounted) return;

      final createCubit = context.read<BeaconCreateCubit>();
      final contextName = context.read<ContextCubit>().state.selected;
      await createCubit.makeLive(context: contextName);
      if (!context.mounted) return;
      if (!createCubit.state.isLive) return;
    }

    _inviteFlowActive = true;
    try {
      await runBeaconInviteFlow(
        context,
        invitations: _invitationCubit,
        beaconId: widget.beaconId,
        isPost: _isPost(context.read<ForwardCubit>().state),
      );
    } finally {
      _inviteFlowActive = false;
    }
  }

  /// Whether the copy speaks of a Post (#501): the host's `copyProfile`
  /// wins, as a new Post's draft is not a loaded beacon.
  bool _isPost(ForwardState state) =>
      _profile(state) == ForwardTargetProfile.post;

  /// The profile the picker's affordances follow (#501): in the Post
  /// composer the forward state has no beacon and reads as a Request, so the
  /// host's `copyProfile` wins there too, not only for the copy.
  ForwardTargetProfile _profile(ForwardState state) =>
      widget.copyProfile ?? state.profile;

  /// Embedded new-Request recipients step: draft must go live before minting.
  bool _needsMakeLiveBeforeInvite(BuildContext context) =>
      _embeddedDraftInCreateFlow(context);

  BeaconCreateCubit? _readCreateCubit(BuildContext context) {
    try {
      return context.read<BeaconCreateCubit>();
    } catch (_) {
      return null;
    }
  }

  bool _embeddedDraftInCreateFlow(BuildContext context) {
    if (!widget.embedded || widget.isLive || widget.beaconId.isEmpty) {
      return false;
    }
    final createCubit = _readCreateCubit(context);
    return createCubit != null && !createCubit.state.isLive;
  }

  bool _inviteEnabled(BuildContext context, ForwardState state) =>
      inviteNewPersonEnabled(
        beaconId: widget.beaconId,
        allowsForward: state.beacon?.viewerCanForward == true,
        isLive: widget.isLive,
        embeddedDraftInCreateFlow: _embeddedDraftInCreateFlow(context),
      );

  /// The empty-state invite may leave for People › Invitations only from the
  /// standalone forward route: inside a create flow that would abandon the
  /// draft (a new Post's text is not saved yet). The new-Post picker instead
  /// opens the invite-link dialog over the composer (#252).
  bool _canInviteFromEmptyState(BuildContext context, ForwardState state) =>
      _inviteEnabled(context, state) ||
      !widget.embedded ||
      _invitesOverComposer(context, state);

  /// The embedded new-Post picker (#252): a plain invite link in a dialog
  /// over the composer, so the unsaved Post stays as written. A draft
  /// Request instead takes the request-tied invite above (#960).
  bool _invitesOverComposer(BuildContext context, ForwardState state) =>
      widget.embedded && !_inviteEnabled(context, state) && _isPost(state);

  /// Empty-state invite: a request-tied invite where the picker may mint one,
  /// a plain invite link over the new-Post composer, otherwise the People ›
  /// Invitations tab.
  Future<void> _inviteFromEmptyState(
    BuildContext context,
    ForwardState state,
  ) async {
    if (_inviteEnabled(context, state)) {
      await _inviteNewPerson(context);
    } else if (_invitesOverComposer(context, state)) {
      await _invitePlainOverComposer(context);
    } else {
      await GetIt.I<RootRouter>().openInvitations();
    }
  }

  /// The same invite-link dialog as «Invite new person», with no request
  /// attached (a new Post has no beacon yet), and no «View invitations»
  /// shortcut afterwards: that leaves the composer (#252).
  Future<void> _invitePlainOverComposer(BuildContext context) async {
    if (_inviteFlowActive) return;
    _inviteFlowActive = true;
    try {
      await runBeaconInviteFlow(
        context,
        invitations: _invitationCubit,
        beaconId: '',
        isPost: true,
        offerViewInvitations: false,
      );
    } finally {
      _inviteFlowActive = false;
    }
  }

  String _lifecycleLabel(L10n l10n, Beacon beacon) {
    final expiresAt = beacon.expiresAt;
    if (beacon.kind == BeaconKind.post && expiresAt != null) {
      return postRemainingLabel(
        l10n,
        expiresAt.difference(context.read<ForwardCubit>().now),
      );
    }
    return switch (beacon.status) {
      BeaconStatus.open => l10n.beaconLifecycleOpen,
      BeaconStatus.needsMoreHelp => l10n.coordinationMoreHelpNeeded,
      BeaconStatus.enoughHelp => l10n.coordinationEnoughHelp,
      BeaconStatus.cancelled => l10n.beaconLifecycleCancelled,
      BeaconStatus.closed => l10n.beaconLifecycleClosed,
      BeaconStatus.deleted => l10n.beaconLifecycleDeleted,
      BeaconStatus.draft => l10n.beaconLifecycleDraft,
      BeaconStatus.reviewOpen => l10n.beaconLifecycleReviewOpen,
    };
  }

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
              if (_sharedNoteController.text != state.note && !_noteExpanded) {
                _sharedNoteController.text = state.note;
              }
              if (!_noteExpanded) {
                setState(() => _noteExpanded = true);
              }
            },
          ),
          BlocListener<ForwardCubit, ForwardState>(
            listenWhen: (prev, next) =>
                prev.selectedIds != next.selectedIds ||
                prev.perRecipientNotes != next.perRecipientNotes ||
                prev.note != next.note,
            listener: (context, state) {
              _syncRecipientNoteControllers(state);
            },
          ),
          BlocListener<ForwardCubit, ForwardState>(
            listenWhen: (prev, next) => prev.activeFilter != next.activeFilter,
            listener: (context, state) {
              if (_scrollController.hasClients) {
                _scrollController.jumpTo(0);
              }
              if (_widerNetworkExpanded) {
                setState(() => _widerNetworkExpanded = false);
              }
            },
          ),
        ],
        child: BlocBuilder<ForwardCubit, ForwardState>(
          key: ValueKey(_widerNetworkExpanded),
          buildWhen: (prev, next) =>
              prev.candidatesLoad != next.candidatesLoad ||
              prev.candidates != next.candidates ||
              prev.lineageSuggestions != next.lineageSuggestions ||
              prev.activeFilter != next.activeFilter ||
              prev.beacon != next.beacon ||
              prev.band != next.band ||
              prev.status != next.status ||
              prev.viewerIsAuthor != next.viewerIsAuthor ||
              prev.targetProfile != next.targetProfile ||
              prev.tagMembers != next.tagMembers ||
              prev.addedByTag != next.addedByTag ||
              prev.editingRecipientId != next.editingRecipientId,
          builder: (_, state) {
            switch (state.candidatesLoad) {
              case ForwardCandidatesLoading():
                return const Center(
                  child: TenturaCircularProgress(adaptive: true),
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
            final searchQuery = (widget.embedded || _searchActive)
                ? _searchController.text
                : '';
            final isFiltering = searchQuery.trim().isNotEmpty;
            final shownIds = state.visibleRecipients.map((c) => c.id).toSet();
            final tagMemberIds = {
              for (final ids in state.tagMembers.values) ...ids,
            };
            // Members of a tapped tag who cannot be picked stay listed, with
            // their usual reason label.
            final visible = _filterInPlace(
              [
                ...state.visibleRecipients,
                for (final c in state.candidates)
                  if (tagMemberIds.contains(c.id) && !shownIds.contains(c.id))
                    c,
              ],
              searchQuery,
            );
            final profile = _profile(state);
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
            final counts = state.scopeCountsForSearch(searchQuery);
            // The band above lists people too (they are left out of
            // [visible]), so an empty list under a shown band is not an
            // empty picker (#252).
            final listIsEmpty =
                state.activeFilter == ForwardFilter.alreadyInvolved
                ? visible.isEmpty
                : visible.isEmpty && lineage.isEmpty && !showBandBlock;

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
                ? _buildTopBarSearchField(tt: tt, l10n: l10n)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile == ForwardTargetProfile.post
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
                              if (widget.header case final header?)
                                SliverToBoxAdapter(child: header),
                              if (inviteNewPersonEnabled(
                                beaconId: widget.beaconId,
                                allowsForward:
                                    state.beacon?.viewerCanForward == true,
                                isLive: widget.isLive,
                                embeddedDraftInCreateFlow:
                                    _embeddedDraftInCreateFlow(context),
                              ))
                                SliverPersistentHeader(
                                  pinned: true,
                                  delegate: ForwardPinnedSliverHeaderDelegate(
                                    height:
                                        ForwardInviteBar.buttonHeight +
                                        tt.rowGap * 2,
                                    child:
                                        BlocSelector<
                                          ForwardCubit,
                                          ForwardState,
                                          bool
                                        >(
                                          selector: (s) =>
                                              s.selectedIds.isNotEmpty,
                                          builder: (context, hasSelection) =>
                                              ForwardInviteBar(
                                                hasSelection: hasSelection,
                                                onInvite: () => unawaited(
                                                  _inviteNewPerson(context),
                                                ),
                                                onClearSelection:
                                                    cubit.clearSelection,
                                              ),
                                        ),
                                  ),
                                ),
                              if (showBandBlock)
                                SliverToBoxAdapter(
                                  child: BlocBuilder<ForwardCubit, ForwardState>(
                                    buildWhen: (prev, next) =>
                                        prev.band != next.band ||
                                        prev.selectedIds != next.selectedIds ||
                                        prev.perRecipientNotes !=
                                            next.perRecipientNotes ||
                                        prev.recipientReasons !=
                                            next.recipientReasons,
                                    builder: (context, bandState) =>
                                        ForwardBandStrip(
                                          band: bandState.band,
                                          candidates: bandState.candidates,
                                          selectedIds: bandState.selectedIds,
                                          beacon: beacon,
                                          recipientNoteHint:
                                              widget.recipientNoteHint,
                                          recipientReasons:
                                              bandState.recipientReasons,
                                          recipientNoteControllers:
                                              _recipientNoteControllers,
                                          onRecipientNoteChanged:
                                              cubit.setRecipientNote,
                                          showsPersonalNotes:
                                              profile.showsPersonalNotes,
                                          expandedPersonalNoteRecipientId:
                                              _expandedPersonalNoteRecipientId,
                                          onOpenPersonalNote: (userId) =>
                                              _expandedPersonalNoteRecipientId
                                                      .value =
                                                  userId,
                                          onPersonalNoteCollapsed:
                                              _collapseExpandedPersonalNote,
                                          perRecipientNotes:
                                              bandState.perRecipientNotes,
                                          onToggle: (userId) =>
                                              _toggle(cubit, userId),
                                          onEditReasons: (userId) => unawaited(
                                            _editReasons(
                                              context,
                                              cubit,
                                              userId,
                                              bandState
                                                      .recipientReasons[userId] ??
                                                  const [],
                                            ),
                                          ),
                                        ),
                                  ),
                                ),
                              SliverToBoxAdapter(
                                child: ForwardTagPicker(
                                  state: state,
                                  onToggle: (id) => _toggle(cubit, id),
                                  showForwardNote: profile.showsReasons,
                                ),
                              ),
                              if (widget.embedded)
                                SliverPersistentHeader(
                                  pinned: true,
                                  delegate: ForwardPinnedSliverHeaderDelegate(
                                    height:
                                        (isFiltering
                                                ? tt.buttonHeight * 2
                                                : tt.buttonHeight) +
                                            tt.rowGap * 2,
                                    child: Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        tt.screenHPadding,
                                        tt.rowGap,
                                        tt.screenHPadding,
                                        tt.rowGap,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _buildSearchField(
                                            tt: tt,
                                            l10n: l10n,
                                            autofocus: false,
                                          ),
                                          if (isFiltering) ...[
                                            SizedBox(height: tt.tightGap),
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: TextButton(
                                                onPressed: _finishEmbeddedSearch,
                                                child: Text(l10n.buttonOk),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              // No one at all to send to: only the empty
                              // state, no «Not yet seen 0 / Already
                              // involved 0» row (#252).
                              if (!showGenuineEmptyMessage)
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
                                      profile: profile,
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
                                  child: _ForwardPickerEmptyState(
                                    kind: showGenuineEmptyMessage
                                        ? _PickerEmptyKind.noOneToSendTo
                                        : isFiltering
                                        ? _PickerEmptyKind.searchNoMatches
                                        : state.activeFilter ==
                                              ForwardFilter.alreadyInvolved
                                        ? _PickerEmptyKind.noOneInvolved
                                        : _PickerEmptyKind.everyoneInvolved,
                                    onInvite:
                                        _canInviteFromEmptyState(
                                          context,
                                          state,
                                        )
                                        ? () => unawaited(
                                            _inviteFromEmptyState(
                                              context,
                                              state,
                                            ),
                                          )
                                        : null,
                                  ),
                                )
                              else ...[
                                SliverPadding(
                                  padding: EdgeInsets.only(bottom: tt.rowGap),
                                  sliver: () {
                                    final recipientSlots =
                                        _planVisibleRecipientSlots(
                                          state: state,
                                          visible: visible,
                                          flattenGroups: isFiltering,
                                          now: cubit.now,
                                        );
                                    return SliverList.list(
                                      children: [
                                        for (final slot in recipientSlots)
                                          _buildVisibleRecipientSlot(
                                            context: context,
                                            cubit: cubit,
                                            state: state,
                                            beacon: beacon,
                                            slot: slot,
                                          ),
                                      ],
                                    );
                                  }(),
                                ),
                                const SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: SizedBox.shrink(),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // An embedded picker without its host's send action has
                        // no send footer of its own (#720 keeps the count label
                        // on the disabled button, so it must not show here).
                        if (!widget.embedded ||
                            widget.onSendPressed != null) ...[
                          // Marks where the scrolling list ends and the send
                          // footer begins, so a cut-off row does not look
                          // like it slides under the footer (#441).
                          const TenturaHairlineDivider(),
                          BlocBuilder<ForwardCubit, ForwardState>(
                            buildWhen: (prev, next) =>
                                prev.selectedIds != next.selectedIds ||
                                prev.lineageSuggestions !=
                                    next.lineageSuggestions ||
                                prev.note != next.note,
                            builder: (context, footerState) =>
                                ForwardBottomComposer(
                                  sendLabel: widget.sendLabel,
                                  selectedIds: footerState.selectedIds,
                                  noteExpanded: _noteExpanded,
                                  onToggleNoteExpanded: _toggleNote,
                                  sharedNoteController: _sharedNoteController,
                                  onSharedNoteChanged: cubit.setNote,
                                  showSuggestedNoteHelper:
                                      footerState
                                          .lineageSuggestions
                                          .isNotEmpty &&
                                      footerState.note.trim().isNotEmpty &&
                                      _noteExpanded,
                                  onForward: widget.onSendPressed != null
                                      ? (widget.sendEnabled
                                            ? () => unawaited(
                                                _handleForwardPressed(context),
                                              )
                                            : null)
                                      : (!widget.embedded &&
                                                footerState.selectedCount > 0
                                            ? () => unawaited(
                                                _handleForwardPressed(context),
                                              )
                                            : null),
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (actionLoading)
                    const Positioned.fill(
                      child: Center(
                        child: TenturaCircularProgress(adaptive: true),
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

  Widget _pickerEntry({
    required BuildContext context,
    required ForwardCubit cubit,
    required ForwardState state,
    required ForwardCandidate candidate,
    required ForwardRecipientRowHost host,
    required Beacon? beacon,
    VoidCallback? onEditForward,
    VoidCallback? onCancelForward,
    VoidCallback? onBuild,
  }) {
    final profile = _profile(state);
    final id = candidate.id;
    return ForwardRecipientPickerEntry(
      key: ValueKey('forward-picker-entry-$id'),
      candidate: candidate,
      host: host,
      beacon: beacon,
      profile: profile,
      viewerIsAuthor: state.viewerIsAuthor,
      expandedPersonalNoteRecipientId: _expandedPersonalNoteRecipientId,
      onToggle: () => _toggle(cubit, id),
      onOpenDetails: () => unawaited(
        showForwardCandidateContextSheet(
          sourceContext: context,
          forwardCubit: cubit,
          candidate: candidate,
          isPost: _isPost(state),
        ),
      ),
      onEditReasons: !profile.showsReasons
          ? null
          : () => unawaited(
              _editReasons(
                context,
                cubit,
                id,
                state.recipientReasons[id] ?? const [],
              ),
            ),
      onEditForward: onEditForward,
      onCancelForward: onCancelForward,
      onOpenPersonalNote: () => _expandedPersonalNoteRecipientId.value = id,
      onPersonalNoteCollapsed: _collapseExpandedPersonalNote,
      recipientNoteController: _recipientNoteControllers[id],
      onRecipientNoteChanged: (text) => cubit.setRecipientNote(id, text),
      recipientNoteHint: widget.recipientNoteHint,
      onBuild:
          onBuild ??
          (widget.debugOnRowBuild != null
              ? () => widget.debugOnRowBuild!(id)
              : null),
    );
  }

  List<Widget> _buildLineageList({
    required BuildContext context,
    required ForwardCubit cubit,
    required ForwardState state,
    required List<ForwardCandidate> lineage,
    required Beacon? beacon,
  }) {
    final children = <Widget>[
      LineageForwardSectionHeader(
        onClear: cubit.clearLineageSuggestions,
      ),
      for (var i = 0; i < lineage.length; i++) ...[
        if (i > 0) const TenturaHairlineDivider(),
        _pickerEntry(
          context: context,
          cubit: cubit,
          state: state,
          candidate: lineage[i],
          host: ForwardRecipientRowHost.pickerLineage,
          beacon: beacon,
        ),
      ],
      const TenturaHairlineDivider(),
    ];
    return children;
  }

  List<_RecipientListSlot> _planVisibleRecipientSlots({
    required ForwardState state,
    required List<ForwardCandidate> visible,
    required bool flattenGroups,
    required DateTime now,
  }) {
    final grouped =
        state.activeFilter != ForwardFilter.alreadyInvolved && !flattenGroups;

    if (!grouped) {
      final slots = <_RecipientListSlot>[];
      for (var i = 0; i < visible.length; i++) {
        if (i > 0) slots.add(const _RecipientListDivider());
        final candidate = visible[i];
        slots.add(_RecipientListRow(candidate));
        if (state.editingRecipientId == candidate.id) {
          slots.add(const _RecipientListEditPanel());
        }
      }
      return slots;
    }

    final newMutual =
        visible.where((c) => ForwardState.isNewMutualCandidate(c, now)).toList()
          ..sort(ForwardState.compareNewMutualNewestFirst);
    final newIds = newMutual.map((c) => c.id).toSet();
    final rest = visible.where((c) => !newIds.contains(c.id)).toList();
    final directRest = rest
        .where((c) => c.effectiveReachKind == ForwardReachKind.direct)
        .toList();
    final throughRest =
        rest
            .where(
              (c) =>
                  c.effectiveReachKind == ForwardReachKind.viaConnection ||
                  c.effectiveReachKind == ForwardReachKind.sharedRequest,
            )
            .toList()
          ..sort((a, b) {
            final viaOrder = b.reachViaCount.compareTo(a.reachViaCount);
            if (viaOrder != 0) {
              return viaOrder;
            }
            return b.mrScore.compareTo(a.mrScore);
          });
    final widerRest = rest
        .where((c) => c.effectiveReachKind == ForwardReachKind.wider)
        .toList();

    final slots = <_RecipientListSlot>[];

    if (newMutual.isNotEmpty) {
      slots.add(const _RecipientListNewHeader());
    }
    for (var i = 0; i < newMutual.length; i++) {
      if (i > 0) slots.add(const _RecipientListDivider());
      final candidate = newMutual[i];
      slots.add(_RecipientListRow(candidate));
      if (state.editingRecipientId == candidate.id) {
        slots.add(const _RecipientListEditPanel());
      }
    }

    if (directRest.isNotEmpty) {
      slots.add(const _RecipientListDirectHeader());
    }
    for (var i = 0; i < directRest.length; i++) {
      if (i > 0) slots.add(const _RecipientListDivider());
      final candidate = directRest[i];
      slots.add(_RecipientListRow(candidate));
      if (state.editingRecipientId == candidate.id) {
        slots.add(const _RecipientListEditPanel());
      }
    }

    if (throughRest.isNotEmpty) {
      slots.add(const _RecipientListThroughHeader());
    }
    for (var i = 0; i < throughRest.length; i++) {
      if (i > 0) slots.add(const _RecipientListDivider());
      final candidate = throughRest[i];
      slots.add(_RecipientListRow(candidate));
      if (state.editingRecipientId == candidate.id) {
        slots.add(const _RecipientListEditPanel());
      }
    }

    if (widerRest.isNotEmpty) {
      final hasSectionAboveWider =
          newMutual.isNotEmpty ||
          directRest.isNotEmpty ||
          throughRest.isNotEmpty;
      final widerOnly = !hasSectionAboveWider;
      final collapseWider = hasSectionAboveWider && !_widerNetworkExpanded;

      if (widerOnly) {
        for (var i = 0; i < widerRest.length; i++) {
          if (i > 0) slots.add(const _RecipientListDivider());
          final candidate = widerRest[i];
          slots.add(_RecipientListRow(candidate));
          if (state.editingRecipientId == candidate.id) {
            slots.add(const _RecipientListEditPanel());
          }
        }
      } else if (collapseWider) {
        final selectedIds = state.selectedIds;
        final pinned = widerRest
            .where((c) => selectedIds.contains(c.id))
            .toList();
        final hiddenCount = widerRest.length - pinned.length;
        for (var i = 0; i < pinned.length; i++) {
          if (i > 0 || slots.isNotEmpty) {
            slots.add(const _RecipientListDivider());
          }
          final candidate = pinned[i];
          slots.add(_RecipientListRow(candidate));
          if (state.editingRecipientId == candidate.id) {
            slots.add(const _RecipientListEditPanel());
          }
        }
        if (hiddenCount > 0) {
          if (slots.isNotEmpty) slots.add(const _RecipientListDivider());
          slots.add(_RecipientListWiderExpander(hiddenCount: hiddenCount));
        }
      } else {
        slots.add(const _RecipientListWiderHeader());
        for (var i = 0; i < widerRest.length; i++) {
          if (i > 0) slots.add(const _RecipientListDivider());
          final candidate = widerRest[i];
          slots.add(_RecipientListRow(candidate));
          if (state.editingRecipientId == candidate.id) {
            slots.add(const _RecipientListEditPanel());
          }
        }
      }
    }

    return slots;
  }

  void _expandWiderNetwork() {
    setState(() => _widerNetworkExpanded = true);
  }

  Widget _buildVisibleRecipientSlot({
    required BuildContext context,
    required ForwardCubit cubit,
    required ForwardState state,
    required Beacon? beacon,
    required _RecipientListSlot slot,
  }) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    return switch (slot) {
      _RecipientListNewHeader() => Padding(
        key: ForwardRecipientPicker.newSectionKey,
        padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TenturaSectionHeader(
                    label: l10n.forwardSectionNewMutual,
                    helperText: l10n.forwardSectionNewMutualHint,
                  ),
                ),
                TextButton(
                  key: const Key('ForwardRecipientPicker.newSelectAll'),
                  onPressed: cubit.selectNewMutualCandidates,
                  child: Text(l10n.forwardSectionNewMutualSelectAll),
                ),
              ],
            ),
          ],
        ),
      ),
      _RecipientListDirectHeader() => Padding(
        key: ForwardRecipientPicker.directSectionKey,
        padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
        child: TenturaSectionHeader(label: l10n.forwardSectionDirectContacts),
      ),
      _RecipientListThroughHeader() => Padding(
        key: ForwardRecipientPicker.throughSectionKey,
        padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
        child: TenturaSectionHeader(
          label: l10n.forwardSectionThroughConnections,
        ),
      ),
      _RecipientListWiderHeader() => Padding(
        key: ForwardRecipientPicker.widerSectionKey,
        padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
        child: TenturaSectionHeader(label: l10n.forwardSectionWiderNetwork),
      ),
      _RecipientListWiderExpander(:final hiddenCount) =>
        ForwardRecipientWiderExpander(
          key: ForwardRecipientPicker.widerExpanderKey,
          hiddenCount: hiddenCount,
          onExpand: _expandWiderNetwork,
        ),
      _RecipientListDivider() => const TenturaHairlineDivider(),
      _RecipientListEditPanel() => ForwardEditPanel(
        controller: _editNoteController,
        onNoteChanged: cubit.setEditNote,
        onSave: () => unawaited(cubit.saveForwardEdit()),
        onCancel: cubit.cancelEditForward,
      ),
      _RecipientListRow(:final candidate) => _pickerEntry(
        context: context,
        cubit: cubit,
        state: state,
        candidate: candidate,
        host: ForwardRecipientRowHost.pickerStandard,
        beacon: beacon,
        onEditForward: _forwardEdgeActionsEnabled(candidate)
            ? () {
                _editNoteController.text = candidate.myForwardNote ?? '';
                cubit.startEditForward(candidate.id);
              }
            : null,
        onCancelForward: _forwardEdgeActionsEnabled(candidate)
            ? () => unawaited(cubit.cancelForward(candidate.id))
            : null,
      ),
    };
  }
}

sealed class _RecipientListSlot {
  const _RecipientListSlot();
}

final class _RecipientListDirectHeader extends _RecipientListSlot {
  const _RecipientListDirectHeader();
}

final class _RecipientListNewHeader extends _RecipientListSlot {
  const _RecipientListNewHeader();
}

final class _RecipientListThroughHeader extends _RecipientListSlot {
  const _RecipientListThroughHeader();
}

final class _RecipientListWiderHeader extends _RecipientListSlot {
  const _RecipientListWiderHeader();
}

final class _RecipientListWiderExpander extends _RecipientListSlot {
  const _RecipientListWiderExpander({required this.hiddenCount});

  final int hiddenCount;
}

final class _RecipientListDivider extends _RecipientListSlot {
  const _RecipientListDivider();
}

final class _RecipientListEditPanel extends _RecipientListSlot {
  const _RecipientListEditPanel();
}

final class _RecipientListRow extends _RecipientListSlot {
  const _RecipientListRow(this.candidate);

  final ForwardCandidate candidate;
}

/// Why the recipient list is empty (#252): nobody can be picked at all, the
/// search matched nobody, or the active scope tab is empty.
enum _PickerEmptyKind {
  noOneToSendTo,
  searchNoMatches,
  everyoneInvolved,
  noOneInvolved,
}

class _ForwardPickerEmptyState extends StatelessWidget {
  const _ForwardPickerEmptyState({required this.kind, this.onInvite});

  final _PickerEmptyKind kind;

  /// Null hides the invite action.
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return switch (kind) {
      // Says what to do and why trust matters; never claims the viewer has
      // no contacts — one-way trust leaves the list empty too.
      _PickerEmptyKind.noOneToSendTo => TenturaEmptyState(
        icon: Icons.group_add_outlined,
        title: l10n.forwardEmptyNoContactsTitle,
        body: l10n.trustWidensReachHint,
        actionLabel: onInvite == null ? null : l10n.emptyInviteSomeoneAction,
        onAction: onInvite,
      ),
      _PickerEmptyKind.searchNoMatches => TenturaEmptyState(
        icon: Icons.search_off,
        title: l10n.forwardSearchNoMatches,
      ),
      _PickerEmptyKind.everyoneInvolved => TenturaEmptyState(
        icon: Icons.done_all,
        title: l10n.forwardScopeUnseenEmpty,
      ),
      _PickerEmptyKind.noOneInvolved => TenturaEmptyState(
        icon: Icons.people_outline,
        title: l10n.forwardScopeInvolvedEmpty,
      ),
    };
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
