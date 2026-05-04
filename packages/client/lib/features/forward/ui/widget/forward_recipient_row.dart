import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/profile_presence_line.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

import '../../domain/entity/candidate_involvement.dart';
import '../../domain/entity/forward_candidate.dart';

class ForwardRecipientRow extends StatelessWidget {
  const ForwardRecipientRow({
    required this.candidate,
    required this.isSelected,
    required this.onToggle,
    this.personalizedNoteEditorOpen = false,
    this.onTogglePersonalizedNoteEditor,
    this.reasonSlugs = const [],
    this.onEditReasons,
    super.key,
  });

  final ForwardCandidate candidate;
  final bool isSelected;
  final VoidCallback? onToggle;
  final bool personalizedNoteEditorOpen;
  final VoidCallback? onTogglePersonalizedNoteEditor;
  /// Capability reason slugs currently selected for this recipient.
  final List<String> reasonSlugs;
  /// Called when the user taps the Why? button; opens reason picker.
  final VoidCallback? onEditReasons;


  /// Involvement / forward path line (independent of scope tab filter).
  String _relationLabel(L10n l10n) {
    if (candidate.involvement != CandidateInvolvement.declined &&
        candidate.involvement != CandidateInvolvement.author &&
        !candidate.isReachable) {
      return l10n.notReachable;
    }
    return switch (candidate.involvement) {
      CandidateInvolvement.declined => l10n.forwardDeclined,
      CandidateInvolvement.author => l10n.forwardAuthor,
      CandidateInvolvement.forwardedByMe =>
        candidate.myForwardNote != null &&
                candidate.myForwardNote!.isNotEmpty
            ? l10n.forwardedByMeWithNote(candidate.myForwardNote!)
            : l10n.forwardedByMe,
      CandidateInvolvement.forwarded => l10n.forwardAlreadyForwarded,
      CandidateInvolvement.watching => l10n.forwardWatching,
      CandidateInvolvement.committed => l10n.forwardCommitted,
      CandidateInvolvement.withdrawn => l10n.forwardWithdrawn,
      CandidateInvolvement.unseen => l10n.forwardFilterUnseen,
    };
  }

  TenturaTone _relationTone() {
    if (candidate.involvement != CandidateInvolvement.declined &&
        candidate.involvement != CandidateInvolvement.author &&
        !candidate.isReachable) {
      return TenturaTone.neutral;
    }
    if (candidate.involvement == CandidateInvolvement.declined ||
        candidate.involvement == CandidateInvolvement.author) {
      return TenturaTone.warn;
    }
    if (candidate.involvement == CandidateInvolvement.unseen) {
      return candidate.canForwardTo ? TenturaTone.good : TenturaTone.neutral;
    }
    return TenturaTone.warn;
  }

  Color _relationStatusColor(TenturaTokens tt) => switch (_relationTone()) {
        TenturaTone.neutral => tt.textMuted,
        TenturaTone.info => tt.info,
        TenturaTone.good => tt.good,
        TenturaTone.warn => tt.warn,
        TenturaTone.danger => tt.danger,
      };

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final canSelect = candidate.canForwardTo;
    final relationLabel = _relationLabel(l10n);
    final forwardedByMeWithNote =
        candidate.involvement == CandidateInvolvement.forwardedByMe &&
            candidate.myForwardNote != null &&
            candidate.myForwardNote!.isNotEmpty;
    final presence = profilePresenceDisplayLine(
      l10n: l10n,
      locale: Localizations.localeOf(context),
      status: candidate.profile.presenceStatus,
      lastSeenAt: candidate.profile.presenceLastSeenAt,
    );
    final nameBaseStyle = TenturaText.titleSmall(
      canSelect ? tt.text : tt.textMuted,
    );

    return InkWell(
      onTap: canSelect ? onToggle : null,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: tt.rowGap,
          horizontal: tt.screenHPadding,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelfAwareAvatar(
              profile: candidate.profile,
              size: tt.cardAvatarSize,
            ),
            SizedBox(width: tt.avatarTextGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BlocBuilder<ProfileCubit, ProfileState>(
                    buildWhen: (p, c) => p.profile.id != c.profile.id,
                    builder: (context, state) {
                      return Text(
                        SelfUserHighlight.displayName(
                          l10n,
                          candidate.profile,
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
                  // Tight before presence / relation (do not use rowGap: a 44px-tall
                  // name+checkbox row was forcing extra empty space under one-line names).
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: tt.iconTextGap,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (presence.isNotEmpty)
                        Text(
                          presence,
                          style: TenturaText.bodySmall(tt.textMuted),
                        ),
                      if (forwardedByMeWithNote)
                        ShowMoreText(
                          l10n.forwardedByMeWithNote(candidate.myForwardNote!),
                          style: TenturaText.status(
                            _relationStatusColor(tt),
                          ),
                          colorClickableText: theme.colorScheme.primary,
                          trimLines: 1,
                          trimCollapsedText: l10n.forwardMyNoteViewMore,
                          trimExpandedText: l10n.forwardMyNoteShowLess,
                        )
                      else
                        TenturaStatusText(
                          relationLabel,
                          tone: _relationTone(),
                        ),
                    ],
                  ),
                  if (candidate.topCapabilities.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: [
                        for (final slug
                            in candidate.topCapabilities.take(2))
                          if (CapabilityTag.fromSlug(slug) case final tag?)
                            _CapabilityHintChip(
                              label: tag.labelOf(l10n),
                              icon: tag.icon,
                              color: tt.textMuted,
                            ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: tt.rowGap),
            if (isSelected && canSelect && onEditReasons != null) ...[
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
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
                canSelect &&
                onTogglePersonalizedNoteEditor != null) ...[
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 44,
                  minHeight: 44,
                ),
                tooltip: personalizedNoteEditorOpen
                    ? l10n.forwardHidePersonalizedNote
                    : l10n.forwardAddPersonalizedNote,
                icon: Icon(
                  personalizedNoteEditorOpen
                      ? Icons.expand_less
                      : Icons.add_comment_outlined,
                  size: tt.iconSize,
                  color: personalizedNoteEditorOpen ? tt.info : tt.textMuted,
                ),
                onPressed: onTogglePersonalizedNoteEditor,
              ),
              SizedBox(width: tt.iconTextGap),
            ],
            _ForwardRowCheckbox(
              isSelected: isSelected,
              enabled: canSelect,
              onTap: onToggle,
            ),
          ],
        ),
      ),
    );
  }
}

class _CapabilityHintChip extends StatelessWidget {
  const _CapabilityHintChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 2),
        Text(label, style: TenturaText.bodySmall(color).copyWith(fontSize: 11)),
      ],
    );
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
                  borderRadius: BorderRadius.circular(4),
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
