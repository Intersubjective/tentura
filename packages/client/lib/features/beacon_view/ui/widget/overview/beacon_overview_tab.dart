import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_info.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

import '../../bloc/beacon_view_state.dart';
import '../../util/beacon_chip_derivation.dart';

const double _kOverviewSectionGap = 12;

BeaconOverviewSectionCard? _roomCueSectionCard(
  String beaconId,
  ColorScheme scheme,
  BeaconRoomState? cue,
  L10n l10n,
) {
  if (cue == null) return null;
  final lm = cue.lastRoomMeaningfulChange?.trim();
  final cueBody = (lm != null && lm.isNotEmpty)
      ? lm
      : cue.currentPlan.trim();
  if (cueBody.isEmpty) return null;
  return BeaconOverviewSectionCard(
    storageId: 'ov-$beaconId-roomCue',
    title: l10n.beaconOverviewRoomCueCardTitle,
    summary: '',
    icon: Icons.meeting_room_outlined,
    defaultOpen: true,
    expanded: Align(
      alignment: Alignment.centerLeft,
      child: SelectableText(
        cueBody,
        style: TenturaText.body(scheme.onSurfaceVariant),
      ),
    ),
  );
}

String _publicStatusLine(L10n l10n, int s) => switch (s) {
  0 => l10n.beaconPublicStatusOpen,
  1 => l10n.beaconPublicStatusCoordinating,
  2 => l10n.beaconPublicStatusMoreHelp,
  3 => l10n.beaconPublicStatusEnoughHelp,
  4 => l10n.beaconPublicStatusClosed,
  _ => l10n.beaconPublicStatusOpen,
};

/// Foldable overview section: icon, title, summary, optional meta, chevron, expanded body.
/// When [collapsible] is false, the body is always visible (no chevron / tap-to-toggle).
class BeaconOverviewSectionCard extends StatefulWidget {
  const BeaconOverviewSectionCard({
    required this.storageId,
    required this.title,
    required this.summary,
    required this.icon,
    required this.expanded,
    this.meta,
    this.defaultOpen = false,
    this.summaryColor,
    this.collapsible = true,
    super.key,
  });

  final String storageId;
  final String title;
  final String summary;
  final String? meta;
  final IconData icon;
  final Widget expanded;
  final bool defaultOpen;
  final Color? summaryColor;

  /// When false, header is static and [expanded] is always shown (need-first primary card).
  final bool collapsible;

  @override
  State<BeaconOverviewSectionCard> createState() =>
      _BeaconOverviewSectionCardState();
}

class _BeaconOverviewSectionCardState extends State<BeaconOverviewSectionCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    if (widget.collapsible) {
      _expanded = widget.defaultOpen;
    } else {
      _expanded = true;
    }
  }

  void _toggle() {
    if (!widget.collapsible) return;
    setState(() {
      _expanded = !_expanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = context.tt;
    final sectionTitleStyle = theme.textTheme.titleSmall!.copyWith(
      color: tt.text,
    );
    // Collapsed summary: status-scale (13) for coordination status line; body for other previews.
    final summaryStyle = widget.summaryColor != null
        ? TenturaText.status(widget.summaryColor!)
        : TenturaText.body(tt.textMuted);
    final metaStyle = theme.textTheme.bodySmall!.copyWith(color: tt.textFaint);
    final effectiveExpanded = !widget.collapsible || _expanded;

    final headerChild = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tt.screenHPadding,
        vertical: tt.cardPadding.top,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: tt.borderSubtle,
              borderRadius: BorderRadius.circular(
                TenturaRadii.cardDense,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: 20,
              color: tt.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  style: sectionTitleStyle,
                ),
                if (widget.summary.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.summary,
                    style: summaryStyle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (widget.meta != null && widget.meta!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.meta!,
                    style: metaStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (widget.collapsible) ...[
            const SizedBox(width: 4),
            Icon(
              effectiveExpanded ? Icons.expand_less : Icons.expand_more,
              color: tt.textMuted,
            ),
          ],
        ],
      ),
    );

    return Material(
      key: PageStorageKey<String>(widget.storageId),
      color: tt.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tt.cardRadius),
        side: BorderSide(color: tt.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.collapsible)
            InkWell(
              onTap: _toggle,
              child: headerChild,
            )
          else
            headerChild,
          if (effectiveExpanded) const TenturaHairlineDivider(),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: effectiveExpanded
                ? Padding(
                    padding: EdgeInsets.fromLTRB(
                      tt.screenHPadding,
                      0,
                      tt.screenHPadding,
                      tt.screenHPadding,
                    ),
                    child: widget.expanded,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class BeaconOverviewTab extends StatelessWidget {
  const BeaconOverviewTab({
    required this.state,
    required this.onViewAllCommitments,
    required this.onEditTimelineUpdate,
    super.key,
  });

  final BeaconViewState state;
  final VoidCallback onViewAllCommitments;
  final Future<void> Function(TimelineUpdate u) onEditTimelineUpdate;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final beacon = state.beacon;
    final coordinationAccent = coordinationContextOnSurfaceColor(
      scheme,
      beaconStatus: beacon.coordinationStatus,
      dominantResponse: _dominantDiagnosisType(state),
    );
    final latest = latestTimelineUpdate(state.timeline);
    final active = activeCommitmentCount(state.commitments);
    final needCoord = _needCoordinationCount(state.commitments);
    final useful = usefulCommitmentCount(state.commitments);
    final contextSummary = _contextAttachmentsSummaryLine(l10n, beacon);

    final publicFacts = state.factCards
        .where(
          (f) =>
              f.visibility == BeaconFactCardVisibilityBits.public &&
              f.status != BeaconFactCardStatusBits.removed,
        )
        .toList();

    final factsCard = publicFacts.isEmpty
        ? null
        : BeaconOverviewSectionCard(
            storageId: 'ov-${beacon.id}-facts',
            title: l10n.beaconOverviewPublicFactsTitle,
            summary: l10n.beaconOverviewPublicFactsCount(publicFacts.length),
            icon: Icons.fact_check_outlined,
            expanded: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final f in publicFacts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: kSpacingSmall),
                    child: SelectableText(
                      f.factText,
                      style: TenturaText.body(scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          );

    final publicRoomCard = BeaconOverviewSectionCard(
      storageId: 'ov-${beacon.id}-pub',
      title: l10n.beaconPublicStatusCardTitle,
      summary: _publicStatusLine(l10n, beacon.publicStatus),
      meta: beacon.lastPublicMeaningfulChange?.trim().isNotEmpty ?? false
          ? beacon.lastPublicMeaningfulChange
          : null,
      icon: Icons.public_outlined,
      expanded: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          (beacon.lastPublicMeaningfulChange?.trim().isNotEmpty ?? false)
              ? beacon.lastPublicMeaningfulChange!.trim()
              : l10n.beaconPublicStatusNoNote,
          style: TenturaText.body(scheme.onSurfaceVariant),
        ),
      ),
    );

    final coordinationCard = BeaconOverviewSectionCard(
      storageId: 'ov-${beacon.id}-coord',
      defaultOpen: true,
      title: l10n.beaconCoordinationCardTitle,
      summary: _coordinationHeaderSummary(l10n, state),
      summaryColor: coordinationAccent,
      meta: l10n.beaconOverviewActiveCommitments(active),
      icon: Icons.groups_outlined,
      expanded: _CoordinationBody(
        l10n: l10n,
        state: state,
        onViewAllCommitments: onViewAllCommitments,
        useful: useful,
        needCoordination: needCoord,
        active: active,
        diagnosisTitleColor: coordinationAccent,
        latest: latest,
        onEditTimelineUpdate: onEditTimelineUpdate,
      ),
    );

    final contextCard = BeaconOverviewSectionCard(
      storageId: 'ov-${beacon.id}-ctx',
      title: l10n.beaconContextAttachmentsTitle,
      summary: contextSummary,
      icon: Icons.attach_file,
      expanded: BeaconInfo(
        key: ValueKey('overview-ctx-${beacon.id}'),
        beacon: beacon,
        isShowBeaconEnabled: false,
        isShowMoreEnabled: false,
        showTitle: false,
        descriptionBeforeMedia: true,
        mediaMaxHeight: 180,
        compactImageGallery: true,
      ),
    );

    final roomCueOverviewCard =
        _roomCueSectionCard(beacon.id, scheme, state.beaconRoomCue, l10n);

    if (beacon.hasNeedSummary) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          publicRoomCard,
          if (roomCueOverviewCard != null) ...[
            const SizedBox(height: _kOverviewSectionGap),
            roomCueOverviewCard,
          ],
          if (factsCard != null) ...[
            const SizedBox(height: _kOverviewSectionGap),
            factsCard,
          ],
          const SizedBox(height: _kOverviewSectionGap),
          BeaconOverviewSectionCard(
            storageId: 'ov-${beacon.id}-need',
            collapsible: false,
            defaultOpen: true,
            title: l10n.beaconNeedCardTitle,
            summary: '',
            icon: Icons.track_changes_outlined,
            expanded: _NeedSectionBody(l10n: l10n, beacon: beacon),
          ),
          const SizedBox(height: _kOverviewSectionGap),
          coordinationCard,
          const SizedBox(height: _kOverviewSectionGap),
          contextCard,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        publicRoomCard,
        if (roomCueOverviewCard != null) ...[
          const SizedBox(height: _kOverviewSectionGap),
          roomCueOverviewCard,
        ],
        if (factsCard != null) ...[
          const SizedBox(height: _kOverviewSectionGap),
          factsCard,
        ],
        const SizedBox(height: _kOverviewSectionGap),
        BeaconOverviewSectionCard(
          storageId: 'ov-${beacon.id}-legacy-need-ctx',
          collapsible: false,
          defaultOpen: true,
          title: l10n.beaconNeedAndContextTitle,
          summary: contextSummary,
          icon: Icons.article_outlined,
          expanded: BeaconInfo(
            key: ValueKey('overview-legacy-${beacon.id}'),
            beacon: beacon,
            isShowBeaconEnabled: false,
            isShowMoreEnabled: false,
            showTitle: false,
            descriptionBeforeMedia: true,
            mediaMaxHeight: 180,
            compactImageGallery: true,
          ),
        ),
        const SizedBox(height: _kOverviewSectionGap),
        coordinationCard,
      ],
    );
  }
}

class _NeedSectionBody extends StatelessWidget {
  const _NeedSectionBody({
    required this.l10n,
    required this.beacon,
  });

  final L10n l10n;
  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodyMedium!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final ns = beacon.needSummary?.trim() ?? '';
    final sc = beacon.successCriteria?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(ns, style: bodyStyle),
        if (sc != null && sc.isNotEmpty) ...[
          SizedBox(height: context.tt.rowGap),
          Text(
            l10n.beaconDoneWhenTitle,
            style: theme.textTheme.titleSmall!.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(sc, style: bodyStyle),
        ],
      ],
    );
  }
}

class _CoordinationBody extends StatelessWidget {
  const _CoordinationBody({
    required this.l10n,
    required this.state,
    required this.onViewAllCommitments,
    required this.useful,
    required this.needCoordination,
    required this.active,
    required this.diagnosisTitleColor,
    required this.latest,
    required this.onEditTimelineUpdate,
  });

  final L10n l10n;
  final BeaconViewState state;
  final VoidCallback onViewAllCommitments;
  final int useful;
  final int needCoordination;
  final int active;
  final Color diagnosisTitleColor;
  final TimelineUpdate? latest;
  final Future<void> Function(TimelineUpdate u) onEditTimelineUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sectionHeaderStyle = theme.textTheme.titleSmall!.copyWith(
      color: theme.colorScheme.onSurface,
    );
    final bodyStyle = theme.textTheme.bodyMedium!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final metaStyle = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final diagnosis = _coordinationDiagnosis(l10n, state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          diagnosis.title,
          style: TenturaText.typeLabel(diagnosisTitleColor),
        ),
        const SizedBox(height: 4),
        Text(
          diagnosis.body,
          style: bodyStyle,
        ),
        const SizedBox(height: 14),
        Text(
          l10n.beaconLatestUpdateTitle,
          style: sectionHeaderStyle,
        ),
        const SizedBox(height: 6),
        _CoordinationAuthorUpdateBlock(
          l10n: l10n,
          state: state,
          latest: latest,
          onEditTimelineUpdate: onEditTimelineUpdate,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.beaconOverviewActiveCommitments(active),
                    style: sectionHeaderStyle,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.beaconOverviewUsefulAndCoord(
                      useful,
                      needCoordination,
                    ),
                    style: metaStyle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            for (final u in state.commitments
                .where((c) => !c.isWithdrawn)
                .take(3))
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: TenturaAvatar(
                  profile: u.user,
                  size: 24,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TenturaCommandButton(
            label: l10n.beaconViewAndCoordinateCommitments,
            onPressed: onViewAllCommitments,
          ),
        ),
      ],
    );
  }
}

class _CoordinationAuthorUpdateBlock extends StatelessWidget {
  const _CoordinationAuthorUpdateBlock({
    required this.l10n,
    required this.state,
    required this.latest,
    required this.onEditTimelineUpdate,
  });

  final L10n l10n;
  final BeaconViewState state;
  final TimelineUpdate? latest;
  final Future<void> Function(TimelineUpdate u) onEditTimelineUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = state.beacon;
    final u = latest;
    if (u == null) {
      return Text(
        l10n.beaconOverviewNoAuthorUpdate,
        style: theme.textTheme.bodySmall!.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: BlocBuilder<ProfileCubit, ProfileState>(
                buildWhen: (p, c) => p.profile.id != c.profile.id,
                builder: (context, ps) {
                  return Text(
                    '${SelfUserHighlight.displayName(l10n, u.author, ps.profile.id)} · ${u.content}',
                    style: theme.textTheme.bodyMedium,
                  );
                },
              ),
            ),
            if (state.isBeaconMine &&
                b.lifecycle == BeaconLifecycle.open &&
                _authorUpdateEditableNow(u.createdAt))
              IconButton(
                tooltip: l10n.editUpdateCTA,
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: () => unawaited(onEditTimelineUpdate(u)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${dateFormatYMD(u.createdAt.toLocal())} ${timeFormatHm(u.createdAt.toLocal())}',
          style: theme.textTheme.bodySmall!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

String _coordinationHeaderSummary(L10n l10n, BeaconViewState state) {
  return switch (state.beacon.coordinationStatus) {
    BeaconCoordinationStatus.moreOrDifferentHelpNeeded =>
      l10n.beaconOverviewCoordinationHeaderPair(
        l10n.beaconOverviewNeedsShortMoreHelp,
        l10n.coordinationNeedDifferentSkill,
      ),
    BeaconCoordinationStatus.noCommitmentsYet => l10n.coordinationNoCommitments,
    BeaconCoordinationStatus.commitmentsWaitingForReview =>
      l10n.coordinationWaitingForReview,
    BeaconCoordinationStatus.enoughHelpCommitted => l10n.coordinationEnoughHelp,
  };
}

({String title, String body}) _coordinationDiagnosis(
  L10n l10n,
  BeaconViewState state,
) {
  final t = _dominantDiagnosisType(state);
  if (t != null) {
    final title = coordinationResponseLabel(l10n, t) ?? '';
    final body = switch (t) {
      CoordinationResponseType.needDifferentSkill =>
        l10n.beaconOverviewDiagnosisNeedDifferentSkillBody,
      CoordinationResponseType.needCoordination =>
        l10n.beaconOverviewDiagnosisNeedCoordinationBody,
      _ => l10n.beaconOverviewDiagnosisGenericMoreHelpBody,
    };
    return (title: title, body: body);
  }
  final s = state.beacon.coordinationStatus;
  return (
    title: coordinationStatusLabel(l10n, s),
    body: l10n.beaconOverviewDiagnosisGenericMoreHelpBody,
  );
}

CoordinationResponseType? _dominantDiagnosisType(BeaconViewState state) {
  final active = state.commitments.where((c) => !c.isWithdrawn);
  for (final t in [
    CoordinationResponseType.needDifferentSkill,
    CoordinationResponseType.needCoordination,
    CoordinationResponseType.notSuitable,
    CoordinationResponseType.overlapping,
  ]) {
    if (active.any((c) => c.coordinationResponse == t)) {
      return t;
    }
  }
  if (state.beacon.coordinationStatus ==
      BeaconCoordinationStatus.moreOrDifferentHelpNeeded) {
    return CoordinationResponseType.needDifferentSkill;
  }
  return null;
}

int _needCoordinationCount(List<TimelineCommitment> commitments) => commitments
    .where(
      (c) =>
          !c.isWithdrawn &&
          c.coordinationResponse == CoordinationResponseType.needCoordination,
    )
    .length;

String _contextAttachmentsSummaryLine(L10n l10n, Beacon beacon) {
  if (beacon.hasPicture) {
    return l10n.beaconOverviewPhotosCount(beacon.images.length);
  }
  if (beacon.description.trim().isNotEmpty) {
    return l10n.beaconOverviewDescriptionTextOnly;
  }
  return l10n.beaconOverviewNeedEmpty;
}

const _beaconAuthorUpdateEditWindow = Duration(hours: 1);

bool _authorUpdateEditableNow(DateTime createdAt) =>
    DateTime.now().toUtc().difference(createdAt.toUtc()) <=
    _beaconAuthorUpdateEditWindow;
