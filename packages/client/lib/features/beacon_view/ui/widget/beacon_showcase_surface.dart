import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_schedule.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_lineage_parent_link.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_trailing_meta_layout.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_request_modes.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_anchor_status.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_definition_body.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_helper_hud_actions.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_action_button.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_app_bar_overflow.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_forward_overflow.dart';
import 'package:tentura/features/beacon_view/ui/widget/closed_request_banner.dart';
import 'package:tentura/features/beacon_view/ui/widget/declined_offer_notice.dart';
import 'package:tentura/features/beacon_view/ui/widget/request_access_reason_banner.dart';
import 'package:tentura/features/capability/ui/widget/capability_requirement_tags.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_location_actions.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/tentura_selection_area.dart';
import 'package:tentura/ui/widget/url_link_annotations.dart';

/// Showcase face of the Request (#159, #104): for people who are not inside
/// yet. Content first (cover, title, who asks, how it reached you, the
/// pitch), with the team strip and the one big action pinned at the bottom.
/// No Now / Chat / People tabs: those come with the HUD once let in.
class BeaconShowcaseSurface extends StatelessWidget {
  const BeaconShowcaseSurface({
    required this.beaconViewCubit,
    required this.screenCubit,
    this.isPreview = false,
    super.key,
  });

  final BeaconViewCubit beaconViewCubit;
  final ScreenCubit screenCubit;

  /// The author previewing their own showcase: actions are inert.
  final bool isPreview;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BeaconViewCubit, BeaconViewState>(
      bloc: beaconViewCubit,
      builder: (context, state) {
        final tt = context.tt;
        final beacon = state.beacon;
        final lineageParent = beacon.lineageParentBeaconId;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  tt.screenHPadding,
                  tt.rowGap,
                  tt.screenHPadding,
                  tt.sectionGap,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (lineageParent != null && lineageParent.isNotEmpty)
                      BeaconLineageParentLink(parentBeaconId: lineageParent),
                    ClosedRequestBanner(beacon: beacon),
                    if (beacon.hasPicture) ...[
                      BeaconDefinitionMediaBand(beacon: beacon),
                      SizedBox(height: tt.rowGap),
                    ],
                    Text(
                      beacon.title,
                      style: TenturaText.titleLarge(tt.text),
                    ),
                    SizedBox(height: tt.tightGap),
                    _AuthorAndStatus(
                      state: state,
                      onAuthorTap: isPreview
                          ? null
                          : () => screenCubit.showProfile(beacon.author.id),
                    ),
                    _ViaLine(
                      provenance: state.forwardProvenance.withoutViewer(
                        state.myProfile.id,
                      ),
                    ),
                    RequestAccessReasonBanner(beacon: beacon),
                    SizedBox(height: tt.rowGap),
                    BeaconShowcaseDescription(text: beacon.description),
                    _ShowcaseFacts(beacon: beacon),
                    if (state.myDeclinedHelpOffer case final declined?) ...[
                      SizedBox(height: tt.cardGap),
                      DeclinedOfferNotice(
                        reason: declined.lastDeclineReason,
                        canOfferAgain:
                            beacon.status.isOpenFamily &&
                            beacon.allowsNewHelpOfferAsNonAuthor,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _ShowcaseBottomPanel(
              state: state,
              beaconViewCubit: beaconViewCubit,
              screenCubit: screenCubit,
              isPreview: isPreview,
            ),
          ],
        );
      },
    );
  }
}

class _AuthorAndStatus extends StatelessWidget {
  const _AuthorAndStatus({required this.state, this.onAuthorTap});

  final BeaconViewState state;
  final VoidCallback? onAuthorTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final author = state.beacon.author;
    final status = beaconViewStatusSlots(l10n, state).presentation;
    return InkWell(
      onTap: onAuthorTap,
      borderRadius: BorderRadius.circular(tt.buttonRadius),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        child: Row(
          children: [
            TenturaAvatar(profile: author, sizeBucket: TenturaAvatarSize.small),
            SizedBox(width: tt.avatarTextGap),
            Flexible(
              child: Text(
                author.shownName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TenturaText.bodySmall(tt.text),
              ),
            ),
            Text(' · ', style: TenturaText.bodySmall(tt.textMuted)),
            Flexible(
              child: TenturaStatusLine(
                slot1: status.slot1,
                slot2: status.slot2,
                slot1Tone: status.slot1Tone,
                slot2Tone: status.slot2Tone,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "↪ via Ivan: «you're good with carpentry»" — how the Request reached the
/// viewer, the social reason to care.
class _ViaLine extends StatelessWidget {
  const _ViaLine({required this.provenance});

  final InboxProvenance provenance;

  @override
  Widget build(BuildContext context) {
    if (provenance.senders.isEmpty) return const SizedBox.shrink();
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final first = provenance.senders.first.displayName.trim();
    if (first.isEmpty) return const SizedBox.shrink();
    final more = provenance.totalDistinctSenders - 1;
    final via = more > 0
        ? l10n.beaconShowcaseViaMore(first, more)
        : l10n.beaconShowcaseVia(first);
    final note = provenance.senders.first.notePreview.trim().isNotEmpty
        ? provenance.senders.first.notePreview.trim()
        : provenance.strongestNotePreview.trim();
    return Padding(
      padding: EdgeInsets.only(top: tt.tightGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.subdirectory_arrow_right, size: 16, color: tt.textMuted),
          SizedBox(width: tt.tightGap),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: via,
                    style: TenturaText.bodySmall(tt.textMuted),
                  ),
                  if (note.isNotEmpty)
                    TextSpan(
                      text: ': «$note»',
                      style: TenturaText.bodySmall(tt.text),
                    ),
                ],
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Description with a "Read more" fold once it runs past [collapsedLines].
class BeaconShowcaseDescription extends StatefulWidget {
  const BeaconShowcaseDescription({
    required this.text,
    this.collapsedLines = 6,
    super.key,
  });

  final String text;
  final int collapsedLines;

  @override
  State<BeaconShowcaseDescription> createState() =>
      _BeaconShowcaseDescriptionState();
}

class _BeaconShowcaseDescriptionState extends State<BeaconShowcaseDescription> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.text.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final style = TenturaText.body(tt.text);
    final span = buildRoomMessageAnnotatedBodySpan(
      data: text,
      textStyle: style,
      annotations: buildUrlAnnotations(linkColor: tt.info),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: span,
          maxLines: widget.collapsedLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TenturaSelectionArea(
              child: Text.rich(
                span,
                maxLines: _expanded ? null : widget.collapsedLines,
                overflow: _expanded ? null : TextOverflow.ellipsis,
              ),
            ),
            if (overflows || _expanded)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded
                      ? l10n.beaconShowcaseShowLess
                      : l10n.beaconShowcaseReadMore,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Needs, schedule and place: what helping would actually involve.
class _ShowcaseFacts extends StatelessWidget {
  const _ShowcaseFacts({required this.beacon});

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final tags = resolveCapabilityRequirementTags(beacon.needs);
    final hasPlace = beacon.coordinates?.isNotEmpty ?? false;
    if (tags.isEmpty && !beacon.hasScheduleDates && !hasPlace) {
      return const SizedBox.shrink();
    }
    final muted = TenturaText.bodySmall(tt.textMuted);
    return Padding(
      padding: EdgeInsets.only(top: tt.rowGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tags.isNotEmpty)
            CapabilityRequirementTags(
              tags: tags,
              showHeading: false,
              labelStyle: muted,
            ),
          if (beacon.hasScheduleDates)
            _FactRow(
              icon: Icons.event_outlined,
              text:
                  '${dateFormatYMD(beacon.startAt)} - '
                  '${dateFormatYMD(beacon.endAt)}',
            ),
          if (hasPlace)
            _FactRow(
              icon: Icons.location_on_outlined,
              text: beaconHudLocationDisplayLabel(beacon, l10n),
              onTap: () =>
                  unawaited(showBeaconLocationActions(context, beacon)),
            ),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tt.buttonRadius),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: tt.tightGap),
        child: Row(
          children: [
            Icon(icon, size: tt.iconSize, color: tt.textMuted),
            SizedBox(width: tt.iconTextGap),
            Expanded(
              child: Text(text, style: TenturaText.bodySmall(tt.textMuted)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pinned bottom: "In on it" strip, then the one big action and the
/// secondary row.
class _ShowcaseBottomPanel extends StatelessWidget {
  const _ShowcaseBottomPanel({
    required this.state,
    required this.beaconViewCubit,
    required this.screenCubit,
    required this.isPreview,
  });

  final BeaconViewState state;
  final BeaconViewCubit beaconViewCubit;
  final ScreenCubit screenCubit;
  final bool isPreview;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final beacon = state.beacon;
    final team = beaconShowcaseTeamFromState(state);

    VoidCallback? live(VoidCallback? action) => isPreview ? null : action;

    final actions = isPreview
        ? _previewActions(l10n)
        : buildBeaconHelperHudActions(
            l10n: l10n,
            state: state,
            onOfferHelp: () => unawaited(
              beaconViewRunInitialHelpOfferDialog(
                context,
                beaconViewCubit,
                l10n,
              ),
            ),
            onEditHelpOffer: () => unawaited(
              beaconViewRunEditHelpOfferDialog(context, beaconViewCubit, l10n),
            ),
            onWatch: () => unawaited(beaconViewCubit.moveToWatching()),
            onStopWatching: () => unawaited(beaconViewCubit.stopWatching()),
          ).primary;
    final primary = actions.where((a) => a.filled).toList();
    final secondary = [
      ...actions.where((a) => !a.filled),
      if (beacon.viewerCanForward || isPreview)
        BeaconHudActionSpec(
          icon: Icons.send,
          label: l10n.labelForward,
          onPressed: live(
            () => unawaited(
              beaconViewOpenForwardThenMaybeNudgeOfferHelp(
                context,
                beaconViewCubit,
                l10n,
              ),
            ),
          ),
          filled: primary.isEmpty,
        ),
    ];
    final offerPending =
        !isPreview &&
        state.isRoomAdmissionBlocked &&
        !state.coordinationDeniesRoomAdmission;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: tt.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            tt.screenHPadding,
            tt.rowGap,
            tt.screenHPadding,
            tt.rowGap,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BeaconShowcaseTeamStrip(
                team: team,
                onTap: team.isEmpty
                    ? null
                    : () => unawaited(
                        showBeaconShowcaseTeamSheet(
                          context,
                          team: team,
                          onOpenProfile: isPreview
                              ? null
                              : screenCubit.showProfile,
                        ),
                      ),
              ),
              if (offerPending) ...[
                SizedBox(height: tt.tightGap),
                Text(
                  l10n.beaconShowcaseOfferPending,
                  style: TenturaText.bodySmall(tt.info),
                ),
              ],
              if (primary.isNotEmpty) ...[
                SizedBox(height: tt.rowGap),
                for (final a in primary)
                  BeaconHudActionButton(
                    icon: a.icon,
                    label: a.label,
                    onPressed: a.onPressed,
                    filled: true,
                  ),
              ],
              if (secondary.isNotEmpty) ...[
                SizedBox(height: tt.tightGap),
                Row(
                  children: [
                    for (var i = 0; i < secondary.length; i++) ...[
                      if (i > 0) SizedBox(width: tt.rowGap),
                      Expanded(
                        child: BeaconHudActionButton(
                          icon: secondary[i].icon,
                          label: secondary[i].label,
                          onPressed: secondary[i].onPressed,
                          filled: secondary[i].filled,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// What an outsider would be offered, shown inert to the previewing author.
  List<BeaconHudActionSpec> _previewActions(L10n l10n) => [
    if (state.beacon.allowsNewHelpOfferAsNonAuthor)
      BeaconHudActionSpec(
        icon: Icons.volunteer_activism_outlined,
        label: l10n.labelOfferHelp,
        onPressed: null,
        filled: true,
      ),
    BeaconHudActionSpec(
      icon: Icons.visibility_outlined,
      label: l10n.beaconHeaderWatch,
      onPressed: null,
      filled: false,
    ),
  ];
}

/// "IN ON IT (IV)(OL)(+2)" with a caption naming the people the viewer
/// knows.
class BeaconShowcaseTeamStrip extends StatelessWidget {
  const BeaconShowcaseTeamStrip({
    required this.team,
    this.onTap,
    this.maxFaces = 5,
    super.key,
  });

  final BeaconShowcaseTeam team;
  final VoidCallback? onTap;
  final int maxFaces;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final faces = team.visible.take(maxFaces).toList();
    final extra = team.total - faces.length;
    final caption = beaconShowcaseTeamCaption(l10n, team);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tt.buttonRadius),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  l10n.beaconShowcaseTeamLabel,
                  style: TenturaText.typeLabel(tt.textMuted),
                ),
                SizedBox(width: tt.rowGap),
                if (faces.isNotEmpty)
                  TenturaAvatarStack(
                    profiles: faces,
                    max: maxFaces,
                  ),
                if (extra > 0) ...[
                  SizedBox(width: tt.tightGap),
                  Text(
                    '+$extra',
                    style: TenturaText.status(tt.textMuted),
                  ),
                ],
              ],
            ),
            SizedBox(height: tt.tightGap),
            Text(
              caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TenturaText.bodySmall(
                team.acquaintances.isNotEmpty ? tt.text : tt.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Caption under the strip: known people by name first, else a head count,
/// else an invitation to be first.
String beaconShowcaseTeamCaption(L10n l10n, BeaconShowcaseTeam team) {
  if (team.isEmpty) return l10n.beaconShowcaseTeamEmpty;
  final known = team.acquaintances;
  if (known.isEmpty) return l10n.beaconShowcaseTeamNoAcquaintances(team.total);
  const named = 2;
  final names = known.take(named).map((p) => p.shownName).join(', ');
  final rest = known.length - named;
  return rest > 0
      ? l10n.beaconShowcaseAcquaintancesMore(names, rest)
      : l10n.beaconShowcaseAcquaintances(names);
}

/// The full team list behind the strip: acquaintances first and marked.
Future<void> showBeaconShowcaseTeamSheet(
  BuildContext context, {
  required BeaconShowcaseTeam team,
  ValueChanged<String>? onOpenProfile,
}) {
  final l10n = L10n.of(context)!;
  final known = {for (final p in team.acquaintances) p.id};
  return showTenturaAdaptiveSheet<void>(
    context: context,
    builder: (ctx) {
      final tt = ctx.tt;
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.symmetric(vertical: tt.rowGap),
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
              child: Text(
                l10n.beaconShowcaseTeamSheetTitle,
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
            ),
            for (final p in team.visible)
              ListTile(
                leading: TenturaAvatar(
                  profile: p,
                  sizeBucket: TenturaAvatarSize.small,
                ),
                title: Text(p.shownName),
                subtitle: known.contains(p.id)
                    ? Text(l10n.beaconShowcaseAcquaintanceTag)
                    : null,
                onTap: onOpenProfile == null
                    ? null
                    : () {
                        Navigator.of(ctx).pop();
                        onOpenProfile(p.id);
                      },
              ),
            if (team.hiddenCount > 0)
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: tt.screenHPadding,
                  vertical: tt.rowGap,
                ),
                child: Text(
                  l10n.beaconShowcaseTeamHidden(team.hiddenCount),
                  style: TenturaText.bodySmall(tt.textMuted),
                ),
              ),
          ],
        ),
      );
    },
  );
}
