import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/profile_presence_line.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

import '../../domain/entity/candidate_involvement.dart';
import '../../domain/entity/forward_candidate.dart';

class ForwardRecipientRow extends StatelessWidget {
  const ForwardRecipientRow({
    required this.candidate,
    required this.isSelected,
    required this.onToggle,
    this.personalizedNoteEditorOpen = false,
    this.onTogglePersonalizedNoteEditor,
    super.key,
  });

  final ForwardCandidate candidate;
  final bool isSelected;
  final VoidCallback? onToggle;
  final bool personalizedNoteEditorOpen;
  final VoidCallback? onTogglePersonalizedNoteEditor;

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

  Color _relationColor(TenturaTokens tt) {
    if (!candidate.isReachable) {
      return tt.textMuted;
    }
    if (candidate.involvement == CandidateInvolvement.declined ||
        candidate.involvement == CandidateInvolvement.author) {
      return tt.warn;
    }
    switch (candidate.involvement) {
      case CandidateInvolvement.unseen:
        return candidate.canForwardTo ? tt.good : tt.textMuted;
      case CandidateInvolvement.forwarded:
      case CandidateInvolvement.forwardedByMe:
      case CandidateInvolvement.watching:
      case CandidateInvolvement.committed:
      case CandidateInvolvement.withdrawn:
        return tt.warn;
      case CandidateInvolvement.declined:
      case CandidateInvolvement.author:
        return tt.warn;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    final canSelect = candidate.canForwardTo;
    final relationLabel = _relationLabel(l10n);
    final relationColor = _relationColor(tt);
    final presence = profilePresenceDisplayLine(
      l10n: l10n,
      locale: Localizations.localeOf(context),
      status: candidate.profile.presenceStatus,
      lastSeenAt: candidate.profile.presenceLastSeenAt,
    );

    return InkWell(
      onTap: canSelect ? onToggle : null,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: 8,
          horizontal: tt.screenHPadding,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelfAwareAvatar(
              profile: candidate.profile,
              size: 32,
            ),
            SizedBox(width: tt.avatarTextGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: BlocBuilder<ProfileCubit, ProfileState>(
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
                                Theme.of(context),
                                TenturaText.title(
                                  canSelect ? tt.text : tt.textMuted,
                                ),
                                SelfUserHighlight.profileIsSelf(
                                  candidate.profile,
                                  state.profile.id,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      if (isSelected &&
                          canSelect &&
                          onTogglePersonalizedNoteEditor != null)
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: onTogglePersonalizedNoteEditor,
                          child: Text(
                            personalizedNoteEditorOpen
                                ? l10n.forwardHidePersonalizedNote
                                : l10n.forwardAddPersonalizedNote,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TenturaText.command(tt.info),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (presence.isNotEmpty)
                        Text(
                          presence,
                          style: TenturaText.bodySmall(tt.textMuted),
                        ),
                      Text(
                        relationLabel,
                        style: TenturaText.bodySmall(relationColor).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
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
    return GestureDetector(
      onTap: enabled ? onTap : null,
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
    );
  }
}
