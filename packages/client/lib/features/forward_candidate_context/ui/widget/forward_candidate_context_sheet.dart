import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_overlay.dart';
import 'package:tentura/domain/util/availability_presets.dart';
import 'package:tentura/features/capability/ui/widget/forward_capability_chips.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_state.dart';
import 'package:tentura/features/forward/ui/widget/lineage_forward_section.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/availability_line.dart';

import '../../domain/entity/candidate_connection_context.dart';
import '../bloc/forward_candidate_context_cubit.dart';
import '../bloc/forward_candidate_context_state.dart';

enum _ForwardCandidateSheetResult { closed, unavailable }

Future<void> showForwardCandidateContextSheet({
  required BuildContext sourceContext,
  required ForwardCubit forwardCubit,
  required ForwardCandidate candidate,
  String? relevanceLabel,
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
      ),
    ),
  );

  if (result == _ForwardCandidateSheetResult.unavailable &&
      sourceContext.mounted) {
    ScaffoldMessenger.of(sourceContext).showSnackBar(
      SnackBar(
        content: Text(
          L10n.of(sourceContext)!.forwardCandidateUnavailableMessage,
        ),
      ),
    );
  }
  if (priorFocus?.context != null && priorFocus!.canRequestFocus) {
    priorFocus.requestFocus();
  }
}

class _ForwardCandidateContextSheet extends StatefulWidget {
  const _ForwardCandidateContextSheet({
    required this.candidate,
    this.relevanceLabel,
  });

  final ForwardCandidate candidate;
  final String? relevanceLabel;

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
    await context.router.root.push(ProfileViewRoute(id: id));
    if (!mounted || !_candidateUnavailable) return;
    Navigator.of(context, rootNavigator: true).pop(
      _ForwardCandidateSheetResult.unavailable,
    );
  }

  void _toggleSelection(BuildContext context, String id) {
    final cubit = context.read<ForwardCubit>();
    if (cubit.isClosed ||
        cubit.toggleSelection(id) == ForwardSelectionResult.unavailable) {
      Navigator.of(context, rootNavigator: true).pop(
        _ForwardCandidateSheetResult.unavailable,
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
          selected: state.selectedIds.contains(candidate.id),
          selectionEnabled: !context.read<ForwardCubit>().isClosed,
          onToggleSelection: () => _toggleSelection(context, candidate.id),
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
    required this.onToggleSelection,
    required this.onViewProfile,
    required this.onClose,
    this.relevanceLabel,
  });

  final ForwardCandidate candidate;
  final String? relevanceLabel;
  final bool selected;
  final bool selectionEnabled;
  final VoidCallback onToggleSelection;
  final VoidCallback onViewProfile;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;
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
                      if (profile.canonicalSecondaryLabel.isNotEmpty) ...[
                        SizedBox(height: tt.tightGap),
                        Text(
                          profile.canonicalSecondaryLabel,
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
            if (profile.description.trim().isNotEmpty) ...[
              SizedBox(height: tt.rowGap),
              Text(
                profile.description.trim(),
                style: TenturaText.body(tt.text),
              ),
            ],
            if (availability != null) ...[
              SizedBox(height: tt.rowGap),
              TenturaStatusText(availability, tone: TenturaTone.neutral),
            ],
            if (candidate.topCapabilities.isNotEmpty) ...[
              SizedBox(height: tt.rowGap),
              ForwardCapabilityChips(slugs: candidate.topCapabilities),
            ],
            if (effectiveRelevance != null &&
                effectiveRelevance.trim().isNotEmpty) ...[
              SizedBox(height: tt.sectionGap),
              Text(
                l10n.forwardCandidateRelevanceHeading,
                style: TenturaText.titleSmall(tt.text),
              ),
              SizedBox(height: tt.tightGap),
              TenturaStatusText(
                effectiveRelevance,
                tone: TenturaTone.info,
              ),
            ],
            SizedBox(height: tt.sectionGap),
            Text(
              l10n.forwardCandidateConnectionHeading,
              style: TenturaText.titleSmall(tt.text),
            ),
            SizedBox(height: tt.rowGap),
            const _ConnectionSection(),
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
  }
}

class _ConnectionSection extends StatefulWidget {
  const _ConnectionSection();

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
        return switch (state.phase) {
          ForwardCandidateContextPhase.direct => TenturaStatusText(
            l10n.forwardCandidateDirectConnection,
            tone: TenturaTone.good,
          ),
          ForwardCandidateContextPhase.loading => Row(
            children: [
              SizedBox(
                width: tt.iconSize,
                height: tt.iconSize,
                child: const CircularProgressIndicator(),
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
          ForwardCandidateContextPhase.path => _PathView(
            nodes: state.connectionContext?.nodes ?? const [],
            expanded: _expanded,
            onToggleExpanded: () => setState(() => _expanded = !_expanded),
          ),
          ForwardCandidateContextPhase.longPath => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TenturaStatusText(
                l10n.forwardCandidateLongPathTitle,
                tone: TenturaTone.neutral,
              ),
              SizedBox(height: tt.tightGap),
              Text(
                l10n.forwardCandidateLongPathBody,
                style: TenturaText.bodySmall(tt.textMuted),
              ),
            ],
          ),
          ForwardCandidateContextPhase.unavailable => Text(
            l10n.forwardCandidateContextUnavailable,
            style: TenturaText.bodySmall(tt.textMuted),
          ),
          ForwardCandidateContextPhase.transportError => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.forwardCandidateContextUnavailable,
                style: TenturaText.bodySmall(tt.textMuted),
              ),
              SizedBox(height: tt.tightGap),
              TextButton(
                onPressed: context.read<ForwardCandidateContextCubit>().retry,
                child: Text(l10n.forwardCandidateRetry),
              ),
            ],
          ),
        };
      },
    );
  }
}

class _PathView extends StatelessWidget {
  const _PathView({
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
    final collapsed = nodes.length > 4 && !expanded;
    final visibleNodes = collapsed
        ? <CandidateConnectionNode?>[nodes.first, nodes[1], null, nodes.last]
        : nodes.cast<CandidateConnectionNode?>();
    final pieces = <Widget>[];
    for (var index = 0; index < visibleNodes.length; index++) {
      if (index > 0) {
        pieces.add(Text('→', style: TenturaText.bodySmall(tt.textMuted)));
      }
      final node = visibleNodes[index];
      pieces.add(
        Text(
          node == null ? '…' : _nodeLabel(node, l10n),
          style: TenturaText.bodySmall(
            node?.kind == CandidateConnectionNodeKind.unavailable
                ? tt.textMuted
                : tt.text,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.forwardCandidateOnePath,
          style: TenturaText.bodySmall(tt.textMuted),
        ),
        SizedBox(height: tt.tightGap),
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

String _nodeLabel(CandidateConnectionNode node, L10n l10n) {
  if (node.kind == CandidateConnectionNodeKind.viewer) return l10n.labelYou;
  if (node.kind == CandidateConnectionNodeKind.unavailable) {
    return l10n.forwardCandidateUnavailablePerson;
  }
  final label = node.displayName?.trim() ?? '';
  return label.isEmpty ? l10n.forwardCandidateUnavailablePerson : label;
}
