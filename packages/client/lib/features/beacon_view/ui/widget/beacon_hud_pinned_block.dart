import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_view/domain/pinned_facts.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_request_modes.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/widget/beacon_hud_metadata_composer.dart';
import 'package:tentura/ui/widget/beacon_hud_metadata_table.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';
import 'package:tentura/ui/widget/hud_labeled_multiline.dart';

/// Pinned top of the Request HUD (#104): YOU, BLOCKER, NEXT STEP and a
/// counters strip. Stays put while the rest of Now scrolls; empty rows drop
/// out (no blocker, no row).
class BeaconHudPinnedBlock extends StatelessWidget {
  const BeaconHudPinnedBlock({
    required this.state,
    this.onEditStep,
    this.onReviewAuthorOffers,
    this.onOpenTeam,
    this.onOpenMyItems,
    this.onOpenSubrequests,
    this.onOpenFacts,
    this.subrequestCount = 0,
    this.now,
    super.key,
  });

  final BeaconViewState state;

  /// Edit the shared next step; null hides the pencil.
  final VoidCallback? onEditStep;
  final VoidCallback? onReviewAuthorOffers;
  final VoidCallback? onOpenTeam;
  final VoidCallback? onOpenMyItems;
  final VoidCallback? onOpenSubrequests;
  final VoidCallback? onOpenFacts;
  final int subrequestCount;

  /// Clock for "2 h ago"; tests pin it.
  final DateTime? now;

  static const blockerIcon = Icons.block_outlined;

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
                  ),
                  ..._blockerAndStep(context, l10n),
                ],
              ),
            _HudCounters(
              state: state,
              subrequestCount: subrequestCount,
              onOpenTeam: onOpenTeam,
              onOpenMyItems: onOpenMyItems,
              onOpenSubrequests: onOpenSubrequests,
              onOpenFacts: onOpenFacts,
            ),
          ],
        ),
      ),
    );
  }

  List<BeaconHudMetadataEntry> _blockerAndStep(
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

    final blocker =
        cue?.openBlockerTitle?.trim() ??
        state.openCoordinationBlocker?.title.trim() ??
        '';
    if (blocker.isNotEmpty) {
      entries.add(
        BeaconHudMetadataEntry(
          icon: blockerIcon,
          semanticsLabel: l10n.beaconHudBlockerLabel,
          body: _LabeledLine(
            label: l10n.beaconHudBlockerLabel,
            text: blocker,
            color: tt.danger,
          ),
        ),
      );
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
        semanticsLabel: l10n.beaconHudStepLabel,
        trailing: onEditStep == null
            ? null
            : hudNowRowEditButton(
                context: context,
                onEdit: onEditStep!,
                editSemanticLabel: l10n.beaconHudEditNowLine,
              ),
        body: _LabeledLine(
          label: l10n.beaconHudStepLabel,
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
                style: TenturaText.typeLabel(
                  color == tt.danger ? tt.danger : tt.textMuted,
                ),
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
    this.onOpenTeam,
    this.onOpenMyItems,
    this.onOpenSubrequests,
    this.onOpenFacts,
  });

  final BeaconViewState state;
  final int subrequestCount;
  final VoidCallback? onOpenTeam;
  final VoidCallback? onOpenMyItems;
  final VoidCallback? onOpenSubrequests;
  final VoidCallback? onOpenFacts;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final team = 1 + state.beacon.admittedHelperCount;
    final you = state.youResponsibility;
    final myItems = you == null
        ? 0
        : you.askOpen + you.promiseOpen + you.blockerOpen;
    final facts = activePinnedFacts(state.factCards).length;
    // Offers waiting on the author are the team's open door: flag it.
    final pending = state.isAuthorOrSteward
        ? state.unansweredHelpOffersCount
        : 0;

    final counters = <Widget>[
      _HudCounter(
        icon: BeaconHudRowIcons.people,
        value: '$team',
        semanticsLabel: l10n.beaconHudCounterTeam(team),
        onTap: onOpenTeam,
        attention: pending > 0,
      ),
      if (myItems > 0)
        _HudCounter(
          icon: Icons.check_box_outline_blank,
          value: '$myItems',
          semanticsLabel: l10n.beaconHudCounterMyItems(myItems),
          onTap: onOpenMyItems,
        ),
      if (subrequestCount > 0)
        _HudCounter(
          icon: Icons.subdirectory_arrow_right,
          value: '$subrequestCount',
          semanticsLabel: l10n.beaconHudCounterSubrequests(subrequestCount),
          onTap: onOpenSubrequests,
        ),
      if (facts > 0)
        _HudCounter(
          icon: Icons.push_pin_outlined,
          value: '$facts',
          semanticsLabel: l10n.beaconHudCounterFacts(facts),
          onTap: onOpenFacts,
        ),
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
    required this.icon,
    required this.value,
    required this.semanticsLabel,
    this.onTap,
    this.attention = false,
  });

  final IconData icon;
  final String value;
  final String semanticsLabel;
  final VoidCallback? onTap;
  final bool attention;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final color = attention ? tt.warn : tt.textMuted;
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
                Icon(icon, size: kBeaconHudRowIconSize, color: color),
                SizedBox(width: tt.tightGap),
                Text(
                  value,
                  style: TenturaText.withTabular(TenturaText.status(tt.text)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
