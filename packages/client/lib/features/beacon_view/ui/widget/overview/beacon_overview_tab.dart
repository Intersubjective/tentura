import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_info.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_pinned_fact_carousel.dart';

import '../../bloc/beacon_view_state.dart';
import '../../util/beacon_chip_derivation.dart';
import '../../util/beacon_closure_readiness.dart';
import '../../util/beacon_hud_derivation.dart';

const double _kOverviewSectionGap = 12;

Widget _closureEvidenceRow(
  ColorScheme scheme,
  String text, {
  required bool ok,
}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.info_outline,
            size: 18,
            color: ok ? scheme.primary : scheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TenturaText.body(scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );

String _publicStatusLine(L10n l10n, int s) => switch (s) {
  0 => l10n.beaconPublicStatusOpen,
  1 => l10n.beaconPublicStatusCoordinating,
  2 => l10n.beaconPublicStatusMoreHelp,
  3 => l10n.beaconPublicStatusEnoughHelp,
  4 => l10n.beaconPublicStatusClosed,
  _ => l10n.beaconPublicStatusOpen,
};

Widget _situationLabeledRow(
  BuildContext context, {
  required String label,
  required String value,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          flex: 2,
          child: Text(
            label,
            style: TenturaText.typeLabel(scheme.onSurface),
          ),
        ),
        SizedBox(width: context.tt.iconTextGap),
        Expanded(
          flex: 5,
          child: SelectableText(
            value,
            style: TenturaText.body(scheme.onSurfaceVariant),
          ),
        ),
      ],
    ),
  );
}

class _SituationPanelBody extends StatelessWidget {
  const _SituationPanelBody({
    required this.l10n,
    required this.state,
    this.onOpenRoom,
  });

  final L10n l10n;
  final BeaconViewState state;
  final VoidCallback? onOpenRoom;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final beacon = state.beacon;
    final cue = state.beaconRoomCue;

    if (beacon.lifecycle == BeaconLifecycle.deleted) {
      return SelectableText(
        l10n.beaconHudBeaconUnavailable,
        style: TenturaText.body(scheme.onSurfaceVariant),
      );
    }

    if (beacon.lifecycle != BeaconLifecycle.open) {
      return SelectableText(
        beaconHudNowLine(l10n, state),
        style: TenturaText.body(scheme.onSurfaceVariant),
      );
    }

    final currentLine = cue?.currentLine.trim() ?? '';
    final blockerTitle = cue?.openBlockerTitle?.trim();
    final roomLast = cue?.lastRoomMeaningfulChange?.trim();
    final pubLast = beacon.lastPublicMeaningfulChange?.trim();

    String? lastText;
    if (roomLast != null && roomLast.isNotEmpty) {
      lastText = roomLast;
    } else if (pubLast != null && pubLast.isNotEmpty) {
      lastText = pubLast;
    }

    final rows = <Widget>[
      _situationLabeledRow(
        context,
        label: l10n.beaconSituationStateLabel,
        value: _publicStatusLine(l10n, beacon.publicStatus),
      ),
    ];

    if (currentLine.isNotEmpty) {
      rows.add(
        _situationLabeledRow(
          context,
          label: l10n.beaconSituationCurrentLineLabel,
          value: currentLine,
        ),
      );
    }

    if (blockerTitle != null && blockerTitle.isNotEmpty) {
      rows.add(
        _situationLabeledRow(
          context,
          label: l10n.beaconSituationBlockerLabel,
          value: blockerTitle,
        ),
      );
    }

    if (lastText != null) {
      rows.add(
        _situationLabeledRow(
          context,
          label: l10n.beaconSituationLastChangeLabel,
          value: lastText,
        ),
      );
    }

    final hasRoomSignal = cue != null &&
        (currentLine.isNotEmpty ||
            (blockerTitle != null && blockerTitle.isNotEmpty) ||
            (roomLast != null && roomLast.isNotEmpty));
    final showOpenRoom =
        onOpenRoom != null && state.canNavigateBeaconRoom && hasRoomSignal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...rows,
        if (showOpenRoom)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onOpenRoom,
              child: Text(l10n.beaconSituationOpenRoom),
            ),
          ),
      ],
    );
  }
}

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

class BeaconStatusDashboard extends StatelessWidget {
  const BeaconStatusDashboard({
    required this.state,
    required this.onViewAllHelpOffers,
    this.onOpenRoom,
    this.onClosureCloseBeacon,
    this.onClosureForward,
    this.onClosureOpenPeople,
    this.onClosureResolveRoom,
    super.key,
  });

  final BeaconViewState state;
  final VoidCallback onViewAllHelpOffers;

  /// Opens Room surface when viewer has room access (AppBar toggle target).
  final VoidCallback? onOpenRoom;

  final VoidCallback? onClosureCloseBeacon;
  final VoidCallback? onClosureForward;
  final VoidCallback? onClosureOpenPeople;
  final VoidCallback? onClosureResolveRoom;

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
    final active = activeHelpOfferCount(state.helpOffers);
    final needCoord = _needCoordinationCount(state.helpOffers);
    final useful = usefulHelpOfferCount(state.helpOffers);
    final contextSummary = _contextAttachmentsSummaryLine(l10n, beacon);

    final publicFacts = state.factCards
        .where(
          (f) =>
              f.visibility == BeaconFactCardVisibilityBits.public &&
              f.status != BeaconFactCardStatusBits.removed,
        )
        .toList()
      ..sort(
        (a, b) {
          final ta = a.updatedAt ?? a.createdAt;
          final tb = b.updatedAt ?? b.createdAt;
          return tb.compareTo(ta);
        },
      );

    final factsCard = publicFacts.isEmpty
        ? null
        : BeaconOverviewSectionCard(
            storageId: 'ov-${beacon.id}-facts',
            defaultOpen: true,
            title: l10n.beaconOverviewPublicFactsTitle,
            summary: l10n.beaconOverviewPublicFactsCount(publicFacts.length),
            icon: Icons.fact_check_outlined,
            expanded: BeaconPinnedFactCarousel(
              facts: publicFacts,
              factTextStyle: TenturaText.body(scheme.onSurfaceVariant),
            ),
          );

    final coordinationCard = BeaconOverviewSectionCard(
      storageId: 'ov-${beacon.id}-coord',
      defaultOpen: true,
      title: l10n.beaconCoordinationCardTitle,
      summary: _coordinationHeaderSummary(l10n, state),
      summaryColor: coordinationAccent,
      meta: l10n.beaconOverviewActiveHelpOffers(active),
      icon: Icons.groups_outlined,
      expanded: _CoordinationBody(
        l10n: l10n,
        state: state,
        onViewAllHelpOffers: onViewAllHelpOffers,
        useful: useful,
        needCoordination: needCoord,
        active: active,
        diagnosisTitleColor: coordinationAccent,
      ),
    );

    final contextCard = BeaconOverviewSectionCard(
      storageId: 'ov-${beacon.id}-ctx',
      defaultOpen: true,
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

    final nowPanel = BeaconOverviewSectionCard(
      storageId: 'ov-${beacon.id}-now',
      collapsible: false,
      title: l10n.beaconHudSituationPanelTitle,
      summary: '',
      icon: Icons.radar_outlined,
      expanded: _SituationPanelBody(
        l10n: l10n,
        state: state,
        onOpenRoom: onOpenRoom,
      ),
    );

    final youPanel = BeaconOverviewSectionCard(
      storageId: 'ov-${beacon.id}-you',
      collapsible: false,
      title: l10n.beaconHudYourRolePanelTitle,
      summary: '',
      icon: Icons.person_pin_outlined,
      expanded: Align(
        alignment: Alignment.centerLeft,
        child: SelectableText(
          beaconHudYouLine(l10n, state),
          style: TenturaText.body(scheme.onSurfaceVariant),
        ),
      ),
    );

    final hasOpenBlocker =
        state.beaconRoomCue?.openBlockerTitle?.trim().isNotEmpty ?? false;
    final hasNeedCoord = state.needCoordinationHelpOffersCount > 0;
    final blockersPanel = hasOpenBlocker || hasNeedCoord
        ? BeaconOverviewSectionCard(
            storageId: 'ov-${beacon.id}-blockers',
            collapsible: false,
            defaultOpen: true,
            title: l10n.beaconBlockersPanelTitle,
            summary: '',
            icon: Icons.warning_amber_rounded,
            expanded: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasOpenBlocker)
                  SelectableText(
                    state.beaconRoomCue!.openBlockerTitle!.trim(),
                    style: TenturaText.body(scheme.onSurfaceVariant),
                  ),
                if (hasNeedCoord) ...[
                  if (hasOpenBlocker) SizedBox(height: context.tt.rowGap),
                  Text(
                    l10n.beaconHudTokenNeedCoordCount(
                      state.needCoordinationHelpOffersCount,
                    ),
                    style: TenturaText.body(scheme.onSurfaceVariant),
                  ),
                ],
                SizedBox(height: context.tt.rowGap),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: onViewAllHelpOffers,
                      child: Text(l10n.beaconCloseSheetActionOpenPeople),
                    ),
                    if (onOpenRoom != null && state.canNavigateBeaconRoom)
                      OutlinedButton(
                        onPressed: onOpenRoom,
                        child: Text(l10n.beaconBlockersPanelAskInRoom),
                      ),
                    if (hasOpenBlocker &&
                        (onOpenRoom == null || !state.canNavigateBeaconRoom))
                      OutlinedButton(
                        onPressed: onViewAllHelpOffers,
                        child: Text(l10n.beaconHudResolveBlocker),
                      ),
                  ],
                ),
              ],
            ),
          )
        : null;

    BeaconOverviewSectionCard? closurePanel;
    if (state.isBeaconMine &&
        beacon.lifecycle == BeaconLifecycle.open &&
        state.closureReadiness != BeaconClosureReadiness.notCloseable) {
      final readiness = state.closureReadiness;
      final summary = buildClosureConfirmationSummary(state);
      final (title, body) = switch (readiness) {
        BeaconClosureReadiness.readyToClose => (
            l10n.beaconClosurePanelTitleReady,
            l10n.beaconClosurePanelBodyReady,
          ),
        BeaconClosureReadiness.waitingForReview => (
            l10n.beaconClosurePanelTitleReview,
            l10n.beaconClosurePanelBodyReview,
          ),
        BeaconClosureReadiness.premature => (
            l10n.beaconClosurePanelTitlePremature,
            l10n.beaconClosurePanelBodyPremature,
          ),
        BeaconClosureReadiness.blocked => (
            l10n.beaconClosurePanelTitleBlocked,
            l10n.beaconClosurePanelBodyBlocked,
          ),
        // Filtered by outer `closureReadiness != notCloseable`; kept for exhaustiveness.
        BeaconClosureReadiness.notCloseable => (
            l10n.beaconClosurePanelTitlePremature,
            l10n.beaconClosurePanelBodyPremature,
          ),
      };

      closurePanel = BeaconOverviewSectionCard(
        storageId: 'ov-${beacon.id}-closure',
        defaultOpen: true,
        title: title,
        summary: body,
        icon: Icons.flag_outlined,
        expanded: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.beaconClosurePanelEvidenceHeading,
              style: TenturaText.typeLabel(scheme.onSurface),
            ),
            const SizedBox(height: 8),
            _closureEvidenceRow(
              scheme,
              summary.hasOpenBlocker
                  ? l10n.beaconCloseSheetEvidenceOpenBlocker
                  : l10n.beaconCloseSheetEvidenceNoOpenBlocker,
              ok: !summary.hasOpenBlocker,
            ),
            if (summary.hasWholeBeaconDoneSignal)
              _closureEvidenceRow(
                scheme,
                l10n.beaconCloseSheetEvidenceWholeBeaconDone,
                ok: true,
              ),
            if (summary.enoughHelpOffered)
              _closureEvidenceRow(
                scheme,
                l10n.beaconCloseSheetEvidenceEnoughHelp,
                ok: true,
              ),
            if (summary.hasSuccessfulHelpOfferResult)
              _closureEvidenceRow(
                scheme,
                l10n.beaconCloseSheetEvidenceUsefulOrDone,
                ok: true,
              ),
            if (summary.unsettledRelevantCount > 0)
              _closureEvidenceRow(
                scheme,
                l10n.beaconCloseSheetEvidenceUnsettledCount(
                  summary.unsettledRelevantCount,
                ),
                ok: false,
              ),
            if (summary.unansweredHelpOffersCount > 0)
              _closureEvidenceRow(
                scheme,
                l10n.beaconCloseSheetEvidenceUnansweredCount(
                  summary.unansweredHelpOffersCount,
                ),
                ok: false,
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onClosureCloseBeacon != null)
                  FilledButton(
                    onPressed: onClosureCloseBeacon,
                    child: Text(l10n.beaconCloseSheetActionCloseBeacon),
                  ),
                if (onClosureForward != null)
                  OutlinedButton(
                    onPressed: onClosureForward,
                    child: Text(l10n.labelForward),
                  ),
                if (onClosureOpenPeople != null)
                  OutlinedButton(
                    onPressed: onClosureOpenPeople,
                    child: Text(l10n.beaconCloseSheetActionOpenPeople),
                  ),
                if (readiness == BeaconClosureReadiness.blocked &&
                    onClosureResolveRoom != null)
                  OutlinedButton(
                    onPressed: onClosureResolveRoom,
                    child: Text(l10n.beaconCloseSheetActionResolveRoom),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    final children = <Widget>[
      nowPanel,
      const SizedBox(height: _kOverviewSectionGap),
      youPanel,
      if (blockersPanel != null) ...[
        const SizedBox(height: _kOverviewSectionGap),
        blockersPanel,
      ],
      if (closurePanel != null) ...[
        const SizedBox(height: _kOverviewSectionGap),
        closurePanel,
      ],
      const SizedBox(height: _kOverviewSectionGap),
      if (beacon.hasNeedSummary) ...[
        BeaconOverviewSectionCard(
          storageId: 'ov-${beacon.id}-need',
          collapsible: false,
          defaultOpen: true,
          title: l10n.beaconNeedCardTitle,
          summary: '',
          icon: Icons.track_changes_outlined,
          expanded: BeaconNeedSectionBody(l10n: l10n, beacon: beacon),
        ),
        const SizedBox(height: _kOverviewSectionGap),
        coordinationCard,
        const SizedBox(height: _kOverviewSectionGap),
        contextCard,
      ] else ...[
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
        const SizedBox(height: _kOverviewSectionGap),
        contextCard,
      ],
      if (factsCard != null) ...[
        const SizedBox(height: _kOverviewSectionGap),
        factsCard,
      ],
    ];

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );

    // `BeaconStatusDashboard` is embedded into an outer scroll on the real screen,
    // but tests often mount it directly into a `Scaffold` body. In that case,
    // use an internal scroll view to avoid overflow errors.
    final isInsideScrollable = Scrollable.maybeOf(context) != null;
    if (isInsideScrollable) return content;

    return SingleChildScrollView(child: content);
  }
}

class BeaconNeedSectionBody extends StatelessWidget {
  const BeaconNeedSectionBody({
    required this.l10n,
    required this.beacon,
    super.key,
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

    final requirementTags = <CapabilityTag>[];
    for (final slug in beacon.needs) {
      final tag = CapabilityTag.fromSlug(slug);
      if (tag != null) {
        requirementTags.add(tag);
      }
    }
    requirementTags.sort((a, b) => a.slug.compareTo(b.slug));

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
        if (requirementTags.isNotEmpty) ...[
          SizedBox(height: context.tt.rowGap),
          Text(
            l10n.beaconRequirementsSubheading,
            style: theme.textTheme.titleSmall!.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final tag in requirementTags)
                Chip(
                  avatar: Icon(tag.icon, size: 18),
                  label: Text(tag.labelOf(l10n)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CoordinationBody extends StatelessWidget {
  const _CoordinationBody({
    required this.l10n,
    required this.state,
    required this.onViewAllHelpOffers,
    required this.useful,
    required this.needCoordination,
    required this.active,
    required this.diagnosisTitleColor,
  });

  final L10n l10n;
  final BeaconViewState state;
  final VoidCallback onViewAllHelpOffers;
  final int useful;
  final int needCoordination;
  final int active;
  final Color diagnosisTitleColor;

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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.beaconOverviewActiveHelpOffers(active),
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
            for (final u in state.helpOffers
                .where((c) => !c.isWithdrawn)
                .take(3))
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: TenturaAvatar.small(
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
            label: l10n.beaconViewAndCoordinateHelpOffers,
            onPressed: onViewAllHelpOffers,
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
    BeaconCoordinationStatus.neutral => l10n.coordinationNeutral,
    BeaconCoordinationStatus.enoughHelpOffered => l10n.coordinationEnoughHelp,
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
  final active = state.helpOffers.where((c) => !c.isWithdrawn);
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

int _needCoordinationCount(List<TimelineHelpOffer> helpOffers) => helpOffers
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
