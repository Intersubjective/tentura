import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
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

/// Foldable overview section: icon, title, summary, optional meta, chevron, expanded body.
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

  @override
  State<BeaconOverviewSectionCard> createState() =>
      _BeaconOverviewSectionCardState();
}

class _BeaconOverviewSectionCardState extends State<BeaconOverviewSectionCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.defaultOpen;
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final summaryStyle = widget.summaryColor != null
        ? TenturaText.body(tt.textMuted).copyWith(color: widget.summaryColor)
        : TenturaText.body(tt.textMuted);
    final metaStyle = TenturaText.bodySmall(tt.textFaint);

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
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                          style: TenturaText.title(tt.text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.summary,
                          style: summaryStyle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: tt.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) const TenturaHairlineDivider(),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
    final needSummary = _needSummaryLine(beacon, l10n);
    final needMeta = _needMetaLine(l10n, beacon);
    final descSummary = _descriptionSummaryLine(l10n, beacon);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BeaconOverviewSectionCard(
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
        ),
        const SizedBox(height: _kOverviewSectionGap),
        BeaconOverviewSectionCard(
          storageId: 'ov-${beacon.id}-need',
          title: l10n.beaconNeedSummaryTitle,
          summary: needSummary,
          meta: needMeta,
          icon: Icons.track_changes_outlined,
          expanded: _NeedBody(
            l10n: l10n,
            beacon: beacon,
          ),
        ),
        const SizedBox(height: _kOverviewSectionGap),
        BeaconOverviewSectionCard(
          storageId: 'ov-${beacon.id}-desc',
          title: l10n.beaconDescriptionAttachmentsTitle,
          summary: descSummary,
          icon: Icons.attach_file,
          expanded: BeaconInfo(
            key: ValueKey('overview-${beacon.id}'),
            beacon: beacon,
            isShowBeaconEnabled: false,
            isShowMoreEnabled: false,
            showTitle: false,
            descriptionBeforeMedia: true,
            mediaMaxHeight: 180,
            compactImageGallery: true,
          ),
        ),
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
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12,
      height: 1.35,
    );
    final diagnosis = _coordinationDiagnosis(l10n, state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          diagnosis.title,
          style: titleStyle?.copyWith(color: diagnosisTitleColor),
        ),
        const SizedBox(height: 4),
        Text(
          diagnosis.body,
          style: bodyStyle?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          l10n.beaconLatestUpdateTitle,
          style: titleStyle,
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
                    style: titleStyle,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.beaconOverviewUsefulAndCoord(
                      useful,
                      needCoordination,
                    ),
                    style: bodyStyle?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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

class _NeedBody extends StatelessWidget {
  const _NeedBody({
    required this.l10n,
    required this.beacon,
  });

  final L10n l10n;
  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = beacon.description.trim();
    final first = d.isNotEmpty
        ? (d.contains('\n') ? d.split('\n').first.trim() : d)
        : l10n.beaconOverviewNeedEmpty;
    return Text(
      first,
      style: theme.textTheme.bodySmall?.copyWith(
        fontSize: 13,
        height: 1.35,
        color: theme.colorScheme.onSurfaceVariant,
      ),
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
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: 13,
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
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13,
                      height: 1.35,
                    ),
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
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 12,
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

String _needSummaryLine(Beacon beacon, L10n l10n) {
  return firstParagraphNeedLine(beacon) ??
      (beacon.title.trim().isNotEmpty
          ? beacon.title.trim()
          : l10n.beaconOverviewNeedEmpty);
}

String? _needMetaLine(L10n l10n, Beacon beacon) {
  final a = beacon.author.title.trim();
  final c = beacon.context.trim();
  if (a.isEmpty && c.isEmpty) {
    return null;
  }
  if (a.isNotEmpty && c.isNotEmpty) {
    return l10n.beaconOverviewNeedMeta(a, c);
  }
  if (a.isNotEmpty) {
    return l10n.beaconOverviewNeedMetaAuthorOnly(a);
  }
  return c;
}

String _descriptionSummaryLine(L10n l10n, Beacon beacon) {
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
