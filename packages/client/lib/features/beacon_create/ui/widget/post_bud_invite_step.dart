import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/post_bud_invite_candidate.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/beacon_create_cubit.dart';

/// Second step of budding a Request from a Post (plan D1): which Post members
/// to invite, a note for each, and whether to close the Post.
///
/// Only members the budder can invite now are listed (writers first); the
/// server's pre-tick is applied by the cubit.
class PostBudInviteStep extends StatelessWidget {
  const PostBudInviteStep({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return BlocSelector<BeaconCreateCubit, BeaconCreateState, PostBudForm?>(
      selector: (s) => s.postBud,
      builder: (context, bud) {
        if (bud == null) return const SizedBox.shrink();
        final cubit = context.read<BeaconCreateCubit>();
        final invitable = bud.invitable;
        return ListView(
          key: const Key('PostBud.InviteStep'),
          children: [
            Text(
              l10n.postBudInviteExplanation,
              style: TenturaText.bodySmall(tt.textMuted),
            ),
            SizedBox(height: tt.rowGap),
            if (bud.showsManyInvitesWarning)
              _Notice(
                key: const Key('PostBud.ManyWarning'),
                icon: Icons.warning_amber_rounded,
                iconColor: tt.warn,
                text: l10n.postBudInviteManyWarning(bud.selectedIds.length),
              ),
            if (bud.candidatesFailed)
              Padding(
                padding: EdgeInsets.symmetric(vertical: tt.sectionGap),
                child: Column(
                  children: [
                    Text(
                      l10n.postBudInviteLoadFailed,
                      textAlign: TextAlign.center,
                      style: TenturaText.bodySmall(tt.text),
                    ),
                    SizedBox(height: tt.rowGap),
                    OutlinedButton(
                      key: const Key('PostBud.RetryCandidates'),
                      onPressed: () =>
                          unawaited(cubit.loadBudInviteCandidates()),
                      child: Text(l10n.postBudInviteRetry),
                    ),
                  ],
                ),
              )
            else if (!bud.candidatesLoaded)
              Padding(
                padding: EdgeInsets.symmetric(vertical: tt.sectionGap),
                child: const Center(
                  child: CircularProgressIndicator.adaptive(),
                ),
              ),
            for (final candidate in invitable)
              _InviteeRow(
                key: ValueKey('PostBud.Invitee.${candidate.userId}'),
                candidate: candidate,
                profile: bud.profiles[candidate.userId],
                viaName: candidate.viaUserId == null
                    ? null
                    : bud.nameOf(candidate.viaUserId!),
                selected: bud.selectedIds.contains(candidate.userId),
                note: bud.notes[candidate.userId] ?? '',
                onSelected: (value) => cubit.setBudInviteeSelected(
                  candidate.userId,
                  selected: value,
                ),
                onNoteChanged: (value) =>
                    cubit.setBudInviteeNote(candidate.userId, value),
              ),
            if (invitable.isNotEmpty) const TenturaHairlineDivider(),
            CheckboxListTile(
              key: const Key('PostBud.ClosePost'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: bud.closePost,
              onChanged: (value) => cubit.setBudClosePost(value ?? false),
              title: Text(
                l10n.postBudClosePost,
                style: TenturaText.bodyMedium(tt.text),
              ),
            ),
            SizedBox(height: tt.sectionGap),
          ],
        );
      },
    );
  }
}

class _InviteeRow extends StatelessWidget {
  const _InviteeRow({
    required this.candidate,
    required this.profile,
    required this.viaName,
    required this.selected,
    required this.note,
    required this.onSelected,
    required this.onNoteChanged,
    super.key,
  });

  final PostBudInviteCandidate candidate;
  final Profile? profile;

  /// «через X»; null when the budder is expected to know the member.
  final String? viaName;
  final bool selected;
  final String note;
  final ValueChanged<bool> onSelected;
  final ValueChanged<String> onNoteChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final shown = profile?.shownName ?? '';
    final name = shown.isEmpty ? l10n.unknownPerson : shown;
    final via = viaName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: selected,
          onChanged: (value) => onSelected(value ?? false),
          secondary: TenturaAvatar(
            profile: profile ?? Profile(id: candidate.userId),
            sizeBucket: TenturaAvatarSize.small,
          ),
          title: Text(name, style: TenturaText.bodyMedium(tt.text)),
          subtitle: via == null || via.isEmpty
              ? null
              : Text(
                  l10n.postBudInviteVia(via),
                  style: TenturaText.bodySmall(tt.textMuted),
                ),
        ),
        if (selected)
          Padding(
            padding: EdgeInsets.only(bottom: tt.rowGap),
            child: TextFormField(
              key: ValueKey('PostBud.Note.${candidate.userId}'),
              initialValue: note,
              maxLines: null,
              onChanged: onNoteChanged,
              style: tenturaFormFieldTextStyle(context),
              decoration: tenturaFormFieldDecoration(
                context,
                labelText: l10n.postBudInviteNoteHint,
              ),
            ),
          ),
      ],
    );
  }
}

/// The bud form's warnings under the discoverability control: the Post was
/// seen by its members only, and its forwarding was off.
class PostBudFormWarnings extends StatelessWidget {
  const PostBudFormWarnings({
    required this.showDiscoverable,
    required this.showForwarding,
    super.key,
  });

  final bool showDiscoverable;
  final bool showForwarding;

  @override
  Widget build(BuildContext context) {
    if (!showDiscoverable && !showForwarding) return const SizedBox.shrink();
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.only(
        left: tt.cardPadding.left,
        right: tt.rowGap,
        bottom: tt.cardPadding.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showDiscoverable)
            _Notice(
              key: const Key('PostBud.DiscoverableWarning'),
              icon: Icons.visibility_outlined,
              iconColor: tt.warn,
              text: l10n.postBudDiscoverableWarning,
            ),
          if (showForwarding)
            _Notice(
              key: const Key('PostBud.ForwardingWarning'),
              icon: Icons.north_east,
              iconColor: tt.textMuted,
              text: l10n.postBudForwardingWarning,
            ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.iconColor,
    required this.text,
    super.key,
  });

  final IconData icon;
  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.only(bottom: tt.rowGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: tt.iconSize, color: iconColor),
          SizedBox(width: tt.avatarTextGap),
          Expanded(
            child: Text(text, style: TenturaText.bodySmall(tt.text)),
          ),
        ],
      ),
    );
  }
}
