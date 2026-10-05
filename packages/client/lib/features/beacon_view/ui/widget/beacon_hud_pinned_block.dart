import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_view/domain/pinned_facts.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_request_modes.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/widget/beacon_hud_metadata_composer.dart';
import 'package:tentura/ui/widget/beacon_hud_metadata_table.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';
import 'package:tentura/ui/widget/hud_labeled_multiline.dart';

import 'beacon_hud_plan_rows.dart';

/// Pinned top of the Request HUD (#104): YOU, NEXT STEP and a counters
/// strip. Stays put while the rest of Now scrolls; empty rows drop out.
/// (Coordination items are retired, so there is no BLOCKER row or "my open
/// items" counter; participant scenarios will reuse that slot.)
class BeaconHudPinnedBlock extends StatelessWidget {
  const BeaconHudPinnedBlock({
    required this.state,
    this.onEditStep,
    this.onReviewAuthorOffers,
    this.onOpenTeam,
    this.onOpenSubrequests,
    this.onOpenFacts,
    this.subrequestCount = 0,
    this.now,
    this.plan,
    super.key,
  });

  final BeaconViewState state;

  /// Edit the shared next step; null hides the pencil.
  final VoidCallback? onEditStep;
  final VoidCallback? onReviewAuthorOffers;
  final VoidCallback? onOpenTeam;
  final VoidCallback? onOpenSubrequests;
  final VoidCallback? onOpenFacts;
  final int subrequestCount;

  /// Clock for "2 h ago"; tests pin it.
  final DateTime? now;

  /// The Request plan (#220) for insiders while `kPlanEnabled`; null hides
  /// every plan row, the plan NOW line and the plan counters.
  final BeaconHudPlanData? plan;

  BeaconHudPlanData? get _plan {
    final p = plan;
    return p != null && p.hasSteps ? p : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final closed = state.beacon.status == BeaconStatus.closed;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: tt.borderSubtle)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tt.screenHPadding,
          tt.rowGap,
          tt.screenHPadding,
          tt.tightGap,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!closed)
              BeaconHudMetadataTable(
                buildEntries: (rowWidth) => [
                  ...buildBeaconViewHudMetadataEntries(
                    context,
                    rowWidth: rowWidth,
                    state: state,
                    includeNow: false,
                    onReviewAuthorOffers: onReviewAuthorOffers,
                    planRows: _plan == null
                        ? null
                        : ({required systemOccupiesYou}) =>
                              buildBeaconHudPlanRows(
                                context,
                                _plan!,
                                systemOccupiesYou: systemOccupiesYou,
                                requestFinished:
                                    state.beacon.status.isFinished ||
                                    state.beacon.status == BeaconStatus.deleted,
                              ),
                  ),
                  ..._step(context, l10n),
                ],
              ),
            _HudCounters(
              state: state,
              plan: _plan,
              subrequestCount: subrequestCount,
              onOpenTeam: onOpenTeam,
              onOpenSubrequests: onOpenSubrequests,
              onOpenFacts: onOpenFacts,
            ),
          ],
        ),
      ),
    );
  }

  List<BeaconHudMetadataEntry> _step(
    BuildContext context,
    L10n l10n,
  ) {
    final tt = context.tt;
    final status = state.beacon.status;
    // Lifecycle summaries (deleted, cancelled, in review) stay on the app
    // bar status; the step row only carries the team's own plan.
    if (status == BeaconStatus.deleted ||
        status == BeaconStatus.cancelled ||
        status == BeaconStatus.reviewOpen) {
      return const [];
    }
    final cue = state.beaconRoomCue;
    final entries = <BeaconHudMetadataEntry>[];
    final plan = _plan;

    // The plan moves the NOW line by the clock; the manual line wins when it
    // was written after the step started (last writer wins, K8).
    final planNow = plan == null
        ? null
        : beaconHudPlanNowLine(
            data: plan,
            manualText: cue?.currentLine ?? '',
            manualSetAt: cue?.updatedAt,
            openFamily: status.isOpenFamily,
            l10n: l10n,
          );
    // With a plan the row is «СЕЙЧАС» (mockup §2); without one it keeps
    // the next-step label.
    final rowLabel = plan == null
        ? l10n.beaconHudStepLabel
        : l10n.beaconHudNowLabel;
    if (planNow != null) {
      entries.add(
        BeaconHudMetadataEntry(
          icon: BeaconHudRowIcons.now,
          semanticsLabel: rowLabel,
          trailing: onEditStep == null
              ? null
              : hudNowRowEditButton(
                  context: context,
                  onEdit: onEditStep!,
                  editSemanticLabel: l10n.beaconHudEditNowLine,
                ),
          body: KeyedSubtree(
            key: beaconHudPlanNowKey,
            child: _LabeledLine(
              label: rowLabel,
              text: planNow.text,
              color: tt.text,
              subline: planNow.subline,
            ),
          ),
        ),
      );
      return entries;
    }

    final step = cue?.currentLine.trim() ?? '';
    final editor = step.isEmpty ? null : beaconStepEditorName(state);
    final attribution = editor == null || cue == null
        ? null
        : l10n.beaconHudStepAttribution(
            editor,
            compactRelativeTimeAgo(
              when: cue.updatedAt,
              now: now ?? DateTime.now(),
              l10n: l10n,
            ),
          );
    entries.add(
      BeaconHudMetadataEntry(
        icon: BeaconHudRowIcons.now,
        semanticsLabel: rowLabel,
        trailing: onEditStep == null
            ? null
            : hudNowRowEditButton(
                context: context,
                onEdit: onEditStep!,
                editSemanticLabel: l10n.beaconHudEditNowLine,
              ),
        body: _LabeledLine(
          label: rowLabel,
          text: step.isNotEmpty
              ? step
              : onEditStep != null
              ? l10n.beaconHudStepEmptyEditable
              : l10n.beaconHudNoCurrentLine,
          color: step.isNotEmpty ? tt.text : tt.textMuted,
          subline: attribution,
        ),
      ),
    );
    return entries;
  }
}

/// The NOW row body when the plan set it (tests).
const beaconHudPlanNowKey = Key('hud-plan-now');

/// `LABEL  text` on one line, with an optional muted second line.
class _LabeledLine extends StatelessWidget {
  const _LabeledLine({
    required this.label,
    required this.text,
    required this.color,
    this.subline,
  });

  final String label;
  final String text;
  final Color color;
  final String? subline;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label  ',
                style: TenturaText.typeLabel(tt.textMuted),
              ),
              TextSpan(
                text: text,
                style: TenturaText.hudBodySmall(color),
              ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (subline != null)
          Text(
            subline!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TenturaText.bodySmall(tt.textMuted),
          ),
      ],
    );
  }
}

class _HudCounters extends StatelessWidget {
  const _HudCounters({
    required this.state,
    required this.subrequestCount,
    this.plan,
    this.onOpenTeam,
    this.onOpenSubrequests,
    this.onOpenFacts,
  });

  final BeaconViewState state;
  final BeaconHudPlanData? plan;
  final int subrequestCount;
  final VoidCallback? onOpenTeam;
  final VoidCallback? onOpenSubrequests;
  final VoidCallback? onOpenFacts;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final plan = this.plan;
    final planDone = plan?.plan.doneCount ?? 0;
    final planTotal = plan?.plan.steps.length ?? 0;
    final planOverdue =
        plan?.plan.viewerOverdueCount(now: plan.now, viewerId: plan.viewerId) ??
        0;
    final team = 1 + state.beacon.admittedHelperCount;
    final facts = activePinnedFacts(state.factCards).length;
    final newFacts = pinnedFactsNewCount(
      facts: state.factCards,
      seenAt: state.pinnedFactsSeenAt,
      viewerUserId: state.myProfile.id,
    );
    // An empty board is still the way in for people who may pin facts.
    final showFacts = facts > 0 || state.canCoordinateInBeaconRoom;
    // Offers waiting on the author are the team's open door: flag it.
    final pending = state.isAuthorOrSteward
        ? state.unansweredHelpOffersCount
        : 0;

    final counters = <Widget>[
      _HudCounter(
        icon: BeaconHudRowIcons.people,
        label: l10n.beaconHudCounterTeamShort(team),
        semanticsLabel: l10n.beaconHudCounterTeam(team),
        onTap: onOpenTeam,
        attention: pending > 0,
      ),
      if (subrequestCount > 0)
        _HudCounter(
          icon: Icons.subdirectory_arrow_right,
          label: l10n.beaconHudCounterSubrequests(subrequestCount),
          semanticsLabel: l10n.beaconHudCounterSubrequests(subrequestCount),
          onTap: onOpenSubrequests,
        ),
      if (showFacts)
        _HudCounter(
          key: TestIds.key(TestIds.beaconFactsOpen),
          icon: Icons.push_pin_outlined,
          label: facts > 0
              ? l10n.beaconHudCounterFactsShort(facts)
              : l10n.beaconFactsRowLabel,
          semanticsLabel: facts > 0
              ? l10n.beaconHudCounterFacts(facts)
              : l10n.beaconFactsRowLabel,
          onTap: onOpenFacts,
          note: newFacts > 0 ? l10n.beaconYouNewCount(newFacts) : null,
          attention: newFacts > 0,
          attentionTone: TenturaTone.info,
        ),
      if (plan != null) ...[
        _HudCounter(
          key: BeaconHudPlanKeys.counter,
          icon: BeaconHudRowIcons.plan,
          label: l10n.beaconHudPlanCounter(planDone, planTotal),
          semanticsLabel: l10n.beaconHudCounterPlan(planDone, planTotal),
          onTap: plan.onOpenPlan,
        ),
        if (planOverdue > 0)
          _HudCounter(
            key: BeaconHudPlanKeys.overdue,
            label: l10n.beaconHudPlanOverdueCounter(planOverdue),
            semanticsLabel: l10n.beaconHudCounterPlanOverdue(planOverdue),
            onTap: plan.onOpenPlan,
            attention: true,
            attentionTone: TenturaTone.danger,
          ),
      ],
    ];

    return Padding(
      padding: EdgeInsets.only(top: tt.tightGap),
      child: Wrap(
        spacing: tt.rowGap,
        children: counters,
      ),
    );
  }
}

class _HudCounter extends StatelessWidget {
  const _HudCounter({
    required this.label,
    required this.semanticsLabel,
    this.icon,
    this.onTap,
    this.note,
    this.attention = false,
    this.attentionTone = TenturaTone.warn,
    super.key,
  });

  /// Null when the label carries its own glyph (e.g. «⏰ 1»).
  final IconData? icon;
  final String label;
  final String semanticsLabel;
  final VoidCallback? onTap;

  /// Short tail after the label in the attention tone (e.g. "+1 new").
  final String? note;
  final bool attention;
  final TenturaTone attentionTone;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final color = attention
        ? tenturaToneColor(tt, attentionTone)
        : tt.textMuted;
    return Semantics(
      button: onTap != null,
      label: semanticsLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tt.buttonRadius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: kMinInteractiveDimension,
            minWidth: kMinInteractiveDimension,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tt.tightGap),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: kBeaconHudRowIconSize, color: color),
                  SizedBox(width: tt.tightGap),
                ],
                Text(
                  label,
                  style: TenturaText.withTabular(
                    TenturaText.status(
                      icon == null && attention ? color : tt.text,
                    ),
                  ),
                ),
                if (note != null) ...[
                  SizedBox(width: tt.tightGap),
                  Text(note!, style: TenturaText.status(color)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
