import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_overlay.dart';
import 'package:tentura/domain/util/availability_presets.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/forward_reach.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/forward_target_profile.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/lineage_forward_section.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/ui/utils/availability_line.dart';
import 'package:tentura/ui/utils/ui_utils.dart' show showSnackBar;
import 'package:tentura/ui/widget/show_more_text.dart';
import 'package:tentura/ui/widget/tentura_selection_area.dart';
import 'package:tentura/ui/widget/url_link_annotations.dart';

import '../../domain/entity/candidate_connection_context.dart';
import '../bloc/forward_candidate_context_cubit.dart';
import '../bloc/forward_candidate_context_state.dart';
import 'forward_candidate_context_sheet_presenter.dart';

enum _ForwardCandidateSheetResult { closed, unavailable, dismissedByThem }

/// #730: the author of a Request cannot forward it to someone who dismissed
/// it, but can still invite them from People › Invite; the sheet and its
/// Select say so instead of a bare "no longer available".
bool _authorSeesDismissed(
  ForwardCandidate candidate,
  ForwardState state, {
  required bool isPost,
}) =>
    candidate.involvement == CandidateInvolvement.declined &&
    state.viewerIsAuthor &&
    !isPost &&
    state.profile != ForwardTargetProfile.post;

/// [isPost]: the host speaks of a Post (a new Post's draft has no loaded
/// beacon, so the forward state alone cannot tell).
Future<void> showForwardCandidateContextSheet({
  required BuildContext sourceContext,
  required ForwardCubit forwardCubit,
  required ForwardCandidate candidate,
  String? relevanceLabel,
  bool isPost = false,
}) async {
  final priorFocus = FocusManager.instance.primaryFocus;
  final result = await showTenturaAdaptiveSheet<_ForwardCandidateSheetResult>(
    context: sourceContext,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheetContext) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: forwardCubit),
        BlocProvider(
          create: (_) => ForwardCandidateContextCubit(
            profile: candidate.profile,
            context: forwardCubit.state.context,
          )..load(),
        ),
      ],
      child: _ForwardCandidateContextSheet(
        candidate: candidate,
        relevanceLabel: relevanceLabel,
        isPost: isPost,
      ),
    ),
  );

  if (sourceContext.mounted) {
    final l10n = L10n.of(sourceContext)!;
    switch (result) {
      case _ForwardCandidateSheetResult.unavailable:
        showSnackBar(
          sourceContext,
          text: l10n.forwardCandidateUnavailableMessage,
        );
      case _ForwardCandidateSheetResult.dismissedByThem:
        showSnackBar(sourceContext, text: l10n.forwardDeclinedUseInvite);
      case _ForwardCandidateSheetResult.closed:
      case null:
        break;
    }
  }
  if (priorFocus?.context != null && priorFocus!.canRequestFocus) {
    priorFocus.requestFocus();
  }
}

class _ForwardCandidateContextSheet extends StatefulWidget {
  const _ForwardCandidateContextSheet({
    required this.candidate,
    required this.isPost,
    this.relevanceLabel,
  });

  final ForwardCandidate candidate;
  final String? relevanceLabel;
  final bool isPost;

  @override
  State<_ForwardCandidateContextSheet> createState() =>
      _ForwardCandidateContextSheetState();
}

class _ForwardCandidateContextSheetState
    extends State<_ForwardCandidateContextSheet> {
  bool _candidateUnavailable = false;

  ForwardCandidate? _currentCandidate(ForwardState state) {
    for (final candidate in [
      ...state.candidates,
      ...state.lineageSuggestions,
    ]) {
      if (candidate.id == widget.candidate.id) return candidate;
    }
    return null;
  }

  void _onForwardState(BuildContext context, ForwardState state) {
    if (_currentCandidate(state) != null) return;
    _candidateUnavailable = true;
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      Navigator.of(context, rootNavigator: true).pop(
        _ForwardCandidateSheetResult.unavailable,
      );
    }
  }

  Future<void> _viewProfile(BuildContext context, String id) async {
    await GetIt.I<AppNavigator>().openProfile(id);
    if (!mounted || !_candidateUnavailable) return;
    Navigator.of(context, rootNavigator: true).pop(
      _ForwardCandidateSheetResult.unavailable,
    );
  }

  void _toggleSelection(BuildContext context, ForwardCandidate candidate) {
    final cubit = context.read<ForwardCubit>();
    if (cubit.isClosed ||
        cubit.toggleSelection(candidate.id) ==
            ForwardSelectionResult.unavailable) {
      final dismissed =
          !cubit.isClosed &&
          _currentCandidate(cubit.state) != null &&
          _authorSeesDismissed(
            candidate,
            cubit.state,
            isPost: widget.isPost,
          );
      Navigator.of(context, rootNavigator: true).pop(
        dismissed
            ? _ForwardCandidateSheetResult.dismissedByThem
            : _ForwardCandidateSheetResult.unavailable,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ForwardCubit, ForwardState>(
      listenWhen: (previous, current) =>
          _currentCandidate(previous) != null &&
          _currentCandidate(current) == null,
      listener: _onForwardState,
      builder: (context, state) {
        final candidate = _currentCandidate(state) ?? widget.candidate;
        return _SheetBody(
          candidate: candidate,
          relevanceLabel: widget.relevanceLabel,
          requiredCapabilitySlugs: state.beacon?.needs ?? const {},
          selected: state.selectedIds.contains(candidate.id),
          selectionEnabled: !context.read<ForwardCubit>().isClosed,
          dismissedHint:
              _authorSeesDismissed(candidate, state, isPost: widget.isPost)
              ? L10n.of(context)!.forwardDeclinedUseInvite
              : null,
          onToggleSelection: () => _toggleSelection(context, candidate),
          onViewProfile: () => _viewProfile(context, candidate.id),
          onClose: () => Navigator.of(context, rootNavigator: true).pop(
            _ForwardCandidateSheetResult.closed,
          ),
        );
      },
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.candidate,
    required this.selected,
    required this.selectionEnabled,
    required this.requiredCapabilitySlugs,
    required this.onToggleSelection,
    required this.onViewProfile,
    required this.onClose,
    this.relevanceLabel,
    this.dismissedHint,
  });

  final ForwardCandidate candidate;
  final String? relevanceLabel;
  final Set<String> requiredCapabilitySlugs;

  /// #730: the author's way to still ask someone who dismissed the Request.
  final String? dismissedHint;
  final bool selected;
  final bool selectionEnabled;
  final VoidCallback onToggleSelection;
  final VoidCallback onViewProfile;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final theme = Theme.of(context);
    final l10n = L10n.of(context)!;
    final locale = Localizations.localeOf(context);
    final profile = profileWithContactOverlay(candidate.profile);
    final availability = otherAvailabilityStatusLine(
      l10n,
      profile.availability,
      availabilityTodayUtc(),
    );
    final lineageLabel = candidate.lineageGroup == null
        ? null
        : lineageReasonLabel(
            l10n,
            candidate.lineageReasonCode ?? '',
            arg: candidate.lineageReasonArg,
          );
    final effectiveRelevance = relevanceLabel ?? lineageLabel;
    final matchesLine = forwardCandidateMatchesLine(
      l10n: l10n,
      requiredSlugs: requiredCapabilitySlugs,
      candidateSlugs: candidate.topCapabilities,
    );

    return BlocBuilder<
      ForwardCandidateContextCubit,
      ForwardCandidateContextState
    >(
      builder: (context, ctxState) {
        final joinedAt = forwardCandidateSheetJoinedAt(
          profile: profile,
          phase: ctxState.phase,
          connectionContext: ctxState.connectionContext,
        );
        final headerSubline = forwardCandidateSheetHeaderSubline(
          l10n: l10n,
          locale: locale,
          profile: profile,
          phase: ctxState.phase,
          joinedAt: joinedAt,
          now: clock.now(),
        );

        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(tt.screenHPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TenturaAvatar.medium(
                      profile: profile,
                      withRating: true,
                      withContactBadge: true,
                    ),
                    SizedBox(width: tt.avatarTextGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.shownName,
                            style: TenturaText.title(context.tt.text),
                          ),
                          if (headerSubline.isNotEmpty) ...[
                            SizedBox(height: tt.tightGap),
                            Text(
                              headerSubline,
                              style: TenturaText.bodySmall(tt.textMuted),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.buttonClose,
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                SizedBox(height: tt.sectionGap),
                Text(
                  l10n.forwardCandidateConnectionHeading,
                  style: TenturaText.titleSmall(tt.text),
                ),
                SizedBox(height: tt.rowGap),
                _ConnectionSection(candidate: candidate),
                if (effectiveRelevance != null &&
                        effectiveRelevance.trim().isNotEmpty ||
                    matchesLine != null) ...[
                  SizedBox(height: tt.sectionGap),
                  Text(
                    l10n.forwardCandidateRelevanceHeading,
                    style: TenturaText.titleSmall(tt.text),
                  ),
                  SizedBox(height: tt.tightGap),
                  if (effectiveRelevance != null &&
                      effectiveRelevance.trim().isNotEmpty)
                    TenturaStatusText(
                      effectiveRelevance,
                      tone: TenturaTone.info,
                    ),
                  if (matchesLine != null) ...[
                    if (effectiveRelevance != null &&
                        effectiveRelevance.trim().isNotEmpty)
                      SizedBox(height: tt.tightGap),
                    Text(
                      matchesLine,
                      style: TenturaText.bodySmall(tt.text),
                    ),
                  ],
                ],
                if (profile.description.trim().isNotEmpty) ...[
                  SizedBox(height: tt.sectionGap),
                  Text(
                    l10n.forwardCandidateAboutHeading,
                    style: TenturaText.titleSmall(tt.text),
                  ),
                  SizedBox(height: tt.tightGap),
                  TenturaSelectionArea(
                    child: ShowMoreText(
                      profile.description.trim(),
                      style: TenturaText.body(tt.text),
                      colorClickableText: theme.colorScheme.primary,
                      annotations: buildUrlAnnotations(linkColor: tt.info),
                    ),
                  ),
                ],
                if (dismissedHint != null) ...[
                  SizedBox(height: tt.rowGap),
                  TenturaStatusText(
                    dismissedHint!,
                    tone: TenturaTone.warn,
                    maxLines: null,
                    overflow: TextOverflow.clip,
                  ),
                ],
                if (availability != null) ...[
                  SizedBox(height: tt.sectionGap),
                  TenturaStatusText(availability, tone: TenturaTone.neutral),
                ],
                SizedBox(height: tt.sectionGap),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        windowClassForWidth(constraints.maxWidth) ==
                        WindowClass.compact;
                    final primary = FilledButton(
                      onPressed: selectionEnabled ? onToggleSelection : null,
                      child: Text(
                        selected
                            ? l10n.forwardCandidateRemove
                            : l10n.forwardCandidateSelect,
                      ),
                    );
                    final secondary = OutlinedButton(
                      onPressed: onViewProfile,
                      child: Text(l10n.forwardCandidateViewProfile),
                    );
                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          primary,
                          SizedBox(height: tt.rowGap),
                          secondary,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: primary),
                        SizedBox(width: tt.rowGap),
                        Expanded(child: secondary),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ConnectionSection extends StatefulWidget {
  const _ConnectionSection({required this.candidate});

  final ForwardCandidate candidate;

  @override
  State<_ConnectionSection> createState() => _ConnectionSectionState();
}

class _ConnectionSectionState extends State<_ConnectionSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<
      ForwardCandidateContextCubit,
      ForwardCandidateContextState
    >(
      builder: (context, state) {
        final l10n = L10n.of(context)!;
        final tt = context.tt;
        final wider = forwardCandidateShowsWiderPath(widget.candidate);
        final children = <Widget>[
          ..._instantHowYouKnowLines(
            context: context,
            candidate: widget.candidate,
            phase: state.phase,
          ),
        ];

        switch (state.phase) {
          case ForwardCandidateContextPhase.direct:
            break;
          case ForwardCandidateContextPhase.loading:
            children.addAll([
              if (children.isNotEmpty) SizedBox(height: tt.rowGap),
              Row(
                children: [
                  SizedBox(
                    width: tt.iconSize,
                    height: tt.iconSize,
                    child: const TenturaCircularProgress(),
                  ),
                  SizedBox(width: tt.iconTextGap),
                  Expanded(
                    child: Text(
                      l10n.forwardCandidateFindingPath,
                      style: TenturaText.bodySmall(tt.textMuted),
                    ),
                  ),
                ],
              ),
            ]);
          case ForwardCandidateContextPhase.path:
            if (wider) {
              children.addAll([
                if (children.isNotEmpty) SizedBox(height: tt.rowGap),
                TenturaStatusText(
                  l10n.forwardCandidateDistantSteps,
                  tone: TenturaTone.neutral,
                ),
                SizedBox(height: tt.tightGap),
                _PathAvatarChain(
                  nodes: state.connectionContext?.nodes ?? const [],
                  expanded: _expanded,
                  onToggleExpanded: () =>
                      setState(() => _expanded = !_expanded),
                ),
                SizedBox(height: tt.tightGap),
                Text(
                  l10n.forwardCandidateNoDirectVouch,
                  style: TenturaText.bodySmall(tt.textMuted),
                ),
              ]);
            }
          case ForwardCandidateContextPhase.longPath:
            if (wider) {
              children.addAll([
                if (children.isNotEmpty) SizedBox(height: tt.rowGap),
                TenturaStatusText(
                  l10n.forwardCandidateLongPathTitle,
                  tone: TenturaTone.neutral,
                ),
              ]);
            }
          case ForwardCandidateContextPhase.unavailable:
            children.addAll([
              if (children.isNotEmpty) SizedBox(height: tt.rowGap),
              Text(
                l10n.forwardCandidateContextUnavailable,
                style: TenturaText.bodySmall(tt.textMuted),
              ),
            ]);
          case ForwardCandidateContextPhase.transportError:
            children.addAll([
              if (children.isNotEmpty) SizedBox(height: tt.rowGap),
              Text(
                l10n.forwardCandidateContextUnavailable,
                style: TenturaText.bodySmall(tt.textMuted),
              ),
              SizedBox(height: tt.tightGap),
              TextButton(
                onPressed: context.read<ForwardCandidateContextCubit>().retry,
                child: Text(l10n.forwardCandidateRetry),
              ),
            ]);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        );
      },
    );
  }
}

List<Widget> _instantHowYouKnowLines({
  required BuildContext context,
  required ForwardCandidate candidate,
  required ForwardCandidateContextPhase phase,
}) {
  final l10n = L10n.of(context)!;
  final tt = context.tt;
  final reach = candidate.reach;
  final lines = <Widget>[];

  if (phase == ForwardCandidateContextPhase.direct ||
      reach?.kind == ForwardReachKind.direct ||
      candidate.profile.isFriend) {
    lines.add(
      TenturaStatusText(
        l10n.forwardCandidateDirectConnection,
        tone: TenturaTone.good,
      ),
    );
  }

  if (reach?.kind == ForwardReachKind.viaConnection) {
    lines.add(
      Padding(
        padding: EdgeInsets.only(top: lines.isEmpty ? 0 : tt.rowGap),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (candidate.reachViaProfiles.isNotEmpty) ...[
              TenturaAvatarStack(
                profiles: candidate.reachViaProfiles,
                max: 2,
                size: tt.iconSize * 1.35,
                overlap: tt.tightGap,
              ),
              SizedBox(width: tt.iconTextGap),
            ],
            Expanded(
              child: Text(
                forwardReachVouchedLabel(l10n, candidate),
                style: TenturaText.bodySmall(tt.text),
              ),
            ),
          ],
        ),
      ),
    );
  }

  final shared = reach?.sharedRequest;
  if (shared != null && shared.title.trim().isNotEmpty) {
    lines.add(
      Padding(
        padding: EdgeInsets.only(top: lines.isEmpty ? 0 : tt.rowGap),
        child: TenturaStatusText(
          l10n.forwardCandidateBothInRequest(shared.title.trim()),
          tone: TenturaTone.info,
        ),
      ),
    );
  }

  return lines;
}

class _PathAvatarChain extends StatelessWidget {
  const _PathAvatarChain({
    required this.nodes,
    required this.expanded,
    required this.onToggleExpanded,
  });

  final List<CandidateConnectionNode> nodes;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    if (nodes.isEmpty) return const SizedBox.shrink();

    final collapsed = nodes.length > 4 && !expanded;
    final visibleNodes = collapsed
        ? <CandidateConnectionNode?>[nodes.first, nodes[1], null, nodes.last]
        : nodes.cast<CandidateConnectionNode?>();

    final pieces = <Widget>[];
    for (var index = 0; index < visibleNodes.length; index++) {
      if (index > 0) {
        pieces.add(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tt.tightGap),
            child: Text('→', style: TenturaText.bodySmall(tt.textMuted)),
          ),
        );
      }
      final node = visibleNodes[index];
      if (node == null) {
        pieces.add(Text('…', style: TenturaText.bodySmall(tt.textMuted)));
      } else if (node.kind == CandidateConnectionNodeKind.unavailable) {
        pieces.add(
          Text(
            l10n.forwardCandidateUnavailablePerson,
            style: TenturaText.bodySmall(tt.textMuted),
          ),
        );
      } else {
        pieces.add(
          TenturaAvatar.small(
            profile: profileFromConnectionNode(node),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: tt.iconTextGap,
          runSpacing: tt.tightGap,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: pieces,
        ),
        if (nodes.length > 4) ...[
          SizedBox(height: tt.tightGap),
          TextButton(
            onPressed: onToggleExpanded,
            child: Text(
              expanded
                  ? l10n.forwardCandidateShowLess
                  : l10n.forwardCandidateShowFullPath,
            ),
          ),
        ],
      ],
    );
  }
}
