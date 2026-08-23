import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/capability/capability_group.dart';
import 'package:tentura/domain/contacts/contact_name_overlay.dart';
import 'package:tentura/domain/util/availability_presets.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

import '../../domain/entity/candidate_involvement.dart';
import '../../domain/entity/forward_candidate.dart';
import '../../domain/entity/lineage_suggestion_group.dart';
import '../model/forward_recipient_row_host.dart';
import 'lineage_forward_section.dart';

class ForwardRecipientRow extends StatelessWidget {
  const ForwardRecipientRow({
    required this.candidate,
    required this.host,
    required this.isSelected,
    required this.onToggle,
    this.onOpenDetails,
    this.isPersonalNoteSkipped = false,
    this.onSkipPersonalNote,
    this.onRestorePersonalNote,
    this.reasonSlugs = const [],
    this.onEditReasons,
    this.onEditForward,
    this.onCancelForward,
    this.tierEvidenceLabel,
    this.tierEvidenceTone,
    this.showPresenceLine = true,
    this.requiredCapabilitySlugs = const {},
    this.todayUtc,
    super.key,
  });

  final ForwardCandidate candidate;
  final ForwardRecipientRowHost host;
  final bool isSelected;
  final VoidCallback? onToggle;
  final VoidCallback? onOpenDetails;
  final bool isPersonalNoteSkipped;
  final VoidCallback? onSkipPersonalNote;
  final VoidCallback? onRestorePersonalNote;

  /// Capability reason slugs currently selected for this recipient.
  final List<String> reasonSlugs;

  /// Called when the user taps the Why? button; opens reason picker.
  final VoidCallback? onEditReasons;

  /// Called when the user wants to edit an existing forward (note / reasons).
  final VoidCallback? onEditForward;

  /// Called when the user wants to cancel an existing forward.
  final VoidCallback? onCancelForward;

  /// When set, replaces the involvement / presence status line (band evidence).
  final String? tierEvidenceLabel;

  /// Tone for [tierEvidenceLabel]; defaults to info.
  final TenturaTone? tierEvidenceTone;

  /// When false, hides presence and default relation line (band exploration rows).
  final bool showPresenceLine;

  /// Beacon [`Beacon.needs`] slugs; chips that match are emphasized.
  final Set<String> requiredCapabilitySlugs;

  /// UTC calendar date for availability; defaults to [availabilityTodayUtc].
  final DateTime? todayUtc;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final effectiveTodayUtc = todayUtc ?? availabilityTodayUtc();
    final canSelectNew = candidate.canForwardToOn(effectiveTodayUtc);
    final checkboxEnabled = forwardRecipientCheckboxEnabled(
      candidate: candidate,
      todayUtc: effectiveTodayUtc,
      isSelected: isSelected,
    );
    final line2 = computeForwardRecipientLine2(
      candidate: candidate,
      host: host,
      todayUtc: effectiveTodayUtc,
      l10n: l10n,
      locale: Localizations.localeOf(context),
      tierEvidenceLabel: tierEvidenceLabel,
      tierEvidenceTone: tierEvidenceTone,
      showPresenceLine: showPresenceLine,
    );
    final nameBaseStyle = TenturaText.titleSmall(
      canSelectNew ? tt.text : tt.textMuted,
    );
    final requiredSet = {
      for (final s in requiredCapabilitySlugs)
        if (s.trim().isNotEmpty) s.trim(),
    };

    return Semantics(
      identifier: TestIds.forwardRecipient(candidate.id),
      button: onOpenDetails != null,
      child: InkWell(
        key: TestIds.key(TestIds.forwardRecipient(candidate.id)),
        onTap: onOpenDetails,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: tt.rowGap,
            horizontal: tt.screenHPadding,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelfAwareAvatar.medium(
                profile: candidate.profile,
                withContactBadge: true,
              ),
              SizedBox(width: tt.avatarTextGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BlocBuilder<ProfileCubit, ProfileState>(
                      buildWhen: (p, c) => p.profile.id != c.profile.id,
                      builder: (context, state) {
                        final displayProfile = profileWithContactOverlay(
                          candidate.profile,
                        );
                        return Text(
                          SelfUserHighlight.displayName(
                            l10n,
                            displayProfile,
                            state.profile.id,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SelfUserHighlight.nameStyle(
                            theme,
                            nameBaseStyle,
                            SelfUserHighlight.profileIsSelf(
                              candidate.profile,
                              state.profile.id,
                            ),
                          ),
                        );
                      },
                    ),
                    SizedBox(height: tt.tightGap),
                    if (!line2.suppressed)
                      _Line2Content(
                        line2: line2,
                        candidate: candidate,
                        l10n: l10n,
                        tt: tt,
                        theme: theme,
                      ),
                    if (showPresenceLine &&
                        candidate.topCapabilities.isNotEmpty) ...[
                      SizedBox(height: tt.tightGap),
                      Wrap(
                        spacing: tt.iconTextGap,
                        runSpacing: tt.tightGap,
                        children: [
                          for (final slug in candidate.topCapabilities)
                            if (CapabilityTag.fromSlug(slug.trim())
                                case final tag?)
                              _CapabilityHintChip(
                                label: tag.labelOf(l10n),
                                icon: tag.icon,
                                group: tag.group,
                                matchesNeed: requiredSet.contains(slug.trim()),
                                matchSemanticsLabel:
                                    l10n.forwardRecipientCapabilityMatchesNeed,
                                tt: tt,
                              ),
                        ],
                      ),
                    ],
                    if (candidate.lineageGroup != null) ...[
                      SizedBox(height: tt.tightGap * 2),
                      _LineageMemoryBadge(l10n: l10n, tt: tt),
                      TenturaStatusText(
                        lineageReasonLabel(
                          l10n,
                          candidate.lineageReasonCode ?? '',
                          arg: candidate.lineageReasonArg,
                        ),
                        tone:
                            candidate.lineageGroup ==
                                LineageSuggestionGroup.involved
                            ? TenturaTone.good
                            : TenturaTone.info,
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: tt.rowGap),
              if (candidate.involvement == CandidateInvolvement.forwardedByMe &&
                  onEditForward != null) ...[
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  tooltip: l10n.forwardEditAction,
                  icon: Icon(
                    Icons.edit_outlined,
                    size: tt.iconSize,
                    color: tt.textMuted,
                  ),
                  onPressed: onEditForward,
                ),
                SizedBox(width: tt.iconTextGap),
              ],
              if (candidate.involvement == CandidateInvolvement.forwardedByMe &&
                  onCancelForward != null) ...[
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  tooltip: l10n.forwardCancelAction,
                  style: IconButton.styleFrom(
                    foregroundColor: tt.warn,
                  ),
                  icon: Icon(
                    Icons.cancel_outlined,
                    size: tt.iconSize,
                  ),
                  onPressed: onCancelForward,
                ),
                SizedBox(width: tt.iconTextGap),
              ],
              if (isSelected && canSelectNew && onEditReasons != null) ...[
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  tooltip: l10n.forwardReasonPrompt,
                  icon: Icon(
                    Icons.label_outline,
                    size: tt.iconSize,
                    color: reasonSlugs.isNotEmpty ? tt.info : tt.textMuted,
                  ),
                  onPressed: onEditReasons,
                ),
                SizedBox(width: tt.iconTextGap),
              ],
              if (isSelected &&
                  canSelectNew &&
                  (isPersonalNoteSkipped
                      ? onRestorePersonalNote != null
                      : onSkipPersonalNote != null)) ...[
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  tooltip: isPersonalNoteSkipped
                      ? l10n.forwardRestorePersonalNote
                      : l10n.forwardSkipPersonalNote,
                  icon: Icon(
                    isPersonalNoteSkipped
                        ? Icons.add_comment_outlined
                        : Icons.do_not_disturb_on_outlined,
                    size: tt.iconSize,
                    color: tt.textMuted,
                  ),
                  onPressed: isPersonalNoteSkipped
                      ? onRestorePersonalNote
                      : onSkipPersonalNote,
                ),
                SizedBox(width: tt.iconTextGap),
              ],
              _ForwardRowCheckbox(
                isSelected: isSelected,
                enabled: checkboxEnabled,
                onTap: onToggle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Line2Content extends StatelessWidget {
  const _Line2Content({
    required this.line2,
    required this.candidate,
    required this.l10n,
    required this.tt,
    required this.theme,
  });

  final ForwardRecipientLine2 line2;
  final ForwardCandidate candidate;
  final L10n l10n;
  final TenturaTokens tt;
  final ThemeData theme;

  Color _toneColor(TenturaTone tone) => switch (tone) {
    TenturaTone.neutral => tt.textMuted,
    TenturaTone.info => tt.info,
    TenturaTone.good => tt.good,
    TenturaTone.warn => tt.warn,
    TenturaTone.danger => tt.danger,
  };

  @override
  Widget build(BuildContext context) {
    if (line2.tierEvidenceLabel != null) {
      return TenturaStatusText(
        line2.tierEvidenceLabel!,
        tone: line2.tierEvidenceTone ?? TenturaTone.info,
      );
    }

    return Wrap(
      spacing: tt.iconTextGap,
      runSpacing: tt.tightGap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (line2.presenceOrAvailabilityLine != null)
          if (line2.presenceOrAvailabilityUsesStatusText)
            TenturaStatusText(
              line2.presenceOrAvailabilityLine!,
              tone: line2.presenceOrAvailabilityTone ?? TenturaTone.neutral,
            )
          else
            Text(
              line2.presenceOrAvailabilityLine!,
              style: TenturaText.bodySmall(tt.textMuted),
            ),
        if (line2.relationLabel != null)
          if (line2.forwardedByMeWithNote)
            ShowMoreText(
              line2.relationLabel!,
              style: TenturaText.status(
                _toneColor(line2.relationTone ?? TenturaTone.neutral),
              ),
              colorClickableText: theme.colorScheme.primary,
              trimLines: 1,
              trimCollapsedText: l10n.forwardMyNoteViewMore,
              trimExpandedText: l10n.forwardMyNoteShowLess,
            )
          else
            TenturaStatusText(
              line2.relationLabel!,
              tone: line2.relationTone ?? TenturaTone.neutral,
            ),
        if (candidate.involvement == CandidateInvolvement.forwardedByMe)
          _ForwardReadReceipt(
            readAt: candidate.recipientReadAt,
            l10n: l10n,
            tt: tt,
          ),
      ],
    );
  }
}

class _ForwardReadReceipt extends StatelessWidget {
  const _ForwardReadReceipt({
    required this.readAt,
    required this.l10n,
    required this.tt,
  });

  final DateTime? readAt;
  final L10n l10n;
  final TenturaTokens tt;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isRead = readAt != null;
    final icon = Icon(
      isRead ? Icons.done_all : Icons.done,
      size: tt.iconSize * 0.65,
      color: isRead ? primary : tt.textMuted,
    );
    if (!isRead) {
      return Tooltip(
        message: l10n.forwardStatusNotYetSeen,
        child: icon,
      );
    }
    final locale = Localizations.localeOf(context);
    final formatted = DateFormat.yMMMd(
      locale.toString(),
    ).add_jm().format(readAt!.toLocal());
    return Tooltip(
      message: l10n.forwardStatusSeenAt(formatted),
      child: icon,
    );
  }
}

class _CapabilityHintChip extends StatelessWidget {
  const _CapabilityHintChip({
    required this.label,
    required this.icon,
    required this.group,
    required this.matchesNeed,
    required this.matchSemanticsLabel,
    required this.tt,
  });

  final String label;
  final IconData icon;
  final CapabilityGroup group;
  final bool matchesNeed;
  final String matchSemanticsLabel;
  final TenturaTokens tt;

  @override
  Widget build(BuildContext context) {
    final swatch = context.capabilityColors.swatchFor(group);
    final fg = matchesNeed ? tt.good : swatch.onContainer;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: tt.iconSize * 0.65, color: fg),
        SizedBox(width: tt.iconTextGap),
        Flexible(
          child: Text(
            matchesNeed ? '★ $label' : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TenturaText.labelSmall(fg),
          ),
        ),
      ],
    );

    Widget content = row;
    if (matchesNeed) {
      content = Container(
        padding: EdgeInsets.symmetric(
          horizontal: tt.iconTextGap,
          vertical: tt.tightGap,
        ),
        decoration: BoxDecoration(
          color: tt.good.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(TenturaRadii.avatar),
          border: Border.all(
            color: tt.good.withValues(alpha: 0.45),
          ),
        ),
        child: row,
      );
    }

    content = Semantics(
      container: true,
      label: matchesNeed ? '$matchSemanticsLabel: $label' : label,
      child: content,
    );

    if (matchesNeed) {
      return Tooltip(
        message: matchSemanticsLabel,
        child: content,
      );
    }
    return content;
  }
}

class _ForwardRowCheckbox extends StatelessWidget {
  const _ForwardRowCheckbox({
    required this.isSelected,
    required this.enabled,
    required this.onTap,
  });

  final bool isSelected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final borderColor = enabled
        ? (isSelected ? tt.info : tt.border)
        : tt.borderSubtle;
    return Semantics(
      label: isSelected
          ? L10n.of(context)!.forwardCandidateRemove
          : L10n.of(context)!.forwardCandidateSelect,
      button: true,
      checked: isSelected,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: isSelected && enabled ? tt.info : Colors.transparent,
                  borderRadius: BorderRadius.circular(TenturaRadii.accentBar),
                  border: Border.all(color: borderColor),
                ),
                child: isSelected && enabled
                    ? Icon(Icons.check, size: 14, color: tt.surface)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LineageMemoryBadge extends StatelessWidget {
  const _LineageMemoryBadge({required this.l10n, required this.tt});

  final L10n l10n;
  final TenturaTokens tt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tt.iconTextGap,
        vertical: tt.tightGap,
      ),
      decoration: BoxDecoration(
        color: tt.info.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(TenturaRadii.avatar),
        border: Border.all(color: tt.info.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: tt.iconSize * 0.65, color: tt.info),
          SizedBox(width: tt.iconTextGap),
          Flexible(
            child: Text(
              l10n.beaconLineageForwardBadge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TenturaText.labelSmall(tt.info),
            ),
          ),
        ],
      ),
    );
  }
}
