import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/author_invite.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_author_invites_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// The author's invites section on a budded Request's People tab (plan D4):
/// each snapshot observer or invitee with the invite status and note,
/// «Отозвать приглашение» on a pending invite and «Позвать» on an observer.
///
/// Renders nothing while loading or when the Request has neither observers
/// nor invites (an ordinary Request).
class BeaconAuthorInvitesSection extends StatelessWidget {
  const BeaconAuthorInvitesSection({
    this.excludedUserIds = const {},
    super.key,
  });

  /// People shown elsewhere on the tab (the admitted helpers).
  final Set<String> excludedUserIds;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return BlocConsumer<BeaconAuthorInvitesCubit, BeaconAuthorInvitesState>(
      listenWhen: (p, c) =>
          c.notInvited != null && p.notInvited != c.notInvited,
      listener: (context, state) {
        final refusal = state.notInvited!;
        final name = _name(l10n, state.profiles[refusal.userId]);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(l10n.postBudNotInvitedSnack(name))),
        );
      },
      builder: (context, state) {
        if (state.isLoading) return const SizedBox.shrink();
        final rows = state.rows(excludedUserIds: excludedUserIds);
        if (rows.isEmpty) return const SizedBox.shrink();
        final cubit = context.read<BeaconAuthorInvitesCubit>();
        return Padding(
          padding: EdgeInsets.only(bottom: tt.sectionGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.postBudInviteTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              SizedBox(height: tt.rowGap),
              for (var i = 0; i < rows.length; i++) ...[
                if (i != 0) const TenturaHairlineDivider(),
                _InviteRow(
                  row: rows[i],
                  busy: state.busyUserIds.contains(rows[i].userId),
                  onInvite: () => cubit.invite(rows[i].userId),
                  onWithdraw: () => cubit.withdraw(rows[i].invite!.id),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

String _name(L10n l10n, Profile? profile) {
  final name = profile?.shownName.trim() ?? '';
  return name.isNotEmpty ? name : l10n.unknownPerson;
}

class _InviteRow extends StatelessWidget {
  const _InviteRow({
    required this.row,
    required this.busy,
    required this.onInvite,
    required this.onWithdraw,
  });

  final BeaconAuthorInviteRow row;
  final bool busy;
  final VoidCallback onInvite;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final invite = row.invite;
    final note = invite?.note?.trim() ?? '';
    final status = switch (invite?.status) {
      AuthorInviteStatus.pending => l10n.inviteStatusPending,
      AuthorInviteStatus.declined => l10n.inviteStatusDeclined,
      _ => null,
    };
    final profile = row.profile;

    return Padding(
      key: ValueKey('BeaconAuthorInviteRow.${row.userId}'),
      padding: EdgeInsets.symmetric(vertical: tt.tightGap),
      child: Row(
        children: [
          if (profile != null) ...[
            ExcludeSemantics(child: TenturaAvatar.small(profile: profile)),
            SizedBox(width: tt.avatarTextGap),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _name(l10n, profile),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TenturaText.bodyMedium(tt.text),
                ),
                if (status != null)
                  TenturaStatusText(
                    status,
                    tone: invite!.status.isPending
                        ? TenturaTone.info
                        : TenturaTone.neutral,
                  ),
                if (note.isNotEmpty) TenturaMetaText(note, maxLines: 2),
              ],
            ),
          ),
          if (row.canWithdraw)
            TenturaTextAction(
              label: l10n.inviteWithdraw,
              tone: TenturaTone.danger,
              minInteractive: true,
              onPressed: busy ? null : onWithdraw,
            )
          else if (row.canInvite)
            TenturaTextAction(
              label: l10n.inviteAction,
              minInteractive: true,
              onPressed: busy ? null : onInvite,
            ),
        ],
      ),
    );
  }
}
