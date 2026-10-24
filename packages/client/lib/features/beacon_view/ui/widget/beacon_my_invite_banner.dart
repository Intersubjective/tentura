import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/use_case/author_invite_case.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_my_invite_cubit.dart';
import 'package:tentura/features/inbox/ui/widget/rejection_dialog.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// The viewer's pending author invite on the Request page (#664): «‹inviter›
/// invites you to help», the note, and «Принять» / «Не смогу» — the choice
/// the Activity invite card offers, shown where the invitee actually lands.
///
/// Shows nothing when the viewer has no pending invite on [beaconId].
class BeaconMyInviteBanner extends StatelessWidget {
  const BeaconMyInviteBanner({
    required this.beaconId,
    this.onAnswered,
    super.key,
  });

  static const acceptKey = Key('BeaconMyInviteBanner.Accept');
  static const declineKey = Key('BeaconMyInviteBanner.Decline');

  final String beaconId;

  /// Reloads the Request once the server took the answer.
  final Future<void> Function()? onAnswered;

  @override
  Widget build(BuildContext context) =>
      // Not wired (isolated widget tests of the Request page): no banner.
      !GetIt.I.isRegistered<AuthorInviteCase>()
      ? const SizedBox.shrink()
      : BlocProvider(
          key: ValueKey(beaconId),
          create: (_) {
            final cubit = BeaconMyInviteCubit(
              beaconId: beaconId,
              onAnswered: onAnswered,
            );
            unawaited(cubit.load());
            return cubit;
          },
          child: const _Banner(),
        );
}

class _Banner extends StatelessWidget {
  const _Banner();

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<BeaconMyInviteCubit, BeaconMyInviteState>(
        builder: (context, state) {
          final invite = state.invite;
          if (invite == null) return const SizedBox.shrink();
          final l10n = L10n.of(context)!;
          final tt = context.tt;
          final cubit = context.read<BeaconMyInviteCubit>();
          final inviter = state.inviter;
          final name = inviter?.shownName.trim() ?? '';
          final note = invite.note?.trim() ?? '';

          Future<void> decline() async {
            final message = await showRejectionDialog(context);
            if (!context.mounted || message == null) return;
            await cubit.decline(message: message);
          }

          return Padding(
            padding: EdgeInsets.only(top: tt.rowGap),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (inviter != null) ...[
                      ExcludeSemantics(
                        child: TenturaAvatar.small(profile: inviter),
                      ),
                      SizedBox(width: tt.avatarTextGap),
                    ],
                    Expanded(
                      child: Text(
                        l10n.inviteCardTitle(
                          name.isNotEmpty ? name : l10n.unknownPerson,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TenturaText.titleSmall(tt.text),
                      ),
                    ),
                  ],
                ),
                if (note.isNotEmpty) ...[
                  SizedBox(height: tt.tightGap),
                  Text(
                    note,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TenturaText.bodySmall(tt.textMuted),
                  ),
                ],
                SizedBox(height: tt.tightGap),
                // Wraps on narrow widths and large text instead of
                // overflowing.
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: tt.tightGap,
                  overflowSpacing: tt.tightGap,
                  children: [
                    TextButton(
                      key: BeaconMyInviteBanner.declineKey,
                      onPressed: state.busy ? null : () => unawaited(decline()),
                      child: Text(l10n.inviteDecline),
                    ),
                    FilledButton(
                      key: BeaconMyInviteBanner.acceptKey,
                      onPressed: state.busy
                          ? null
                          : () => unawaited(cubit.accept()),
                      child: Text(l10n.inviteAccept),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
}
