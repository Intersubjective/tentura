import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/forward/domain/forward_target_profile.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/beacon_create_cubit.dart';

/// Second step of budding a Request from a Post (plan D1): the shared Forward
/// recipient picker over the Post's members (the [ForwardCubit] above this
/// widget), headed by the explanation and the many-invites warning, and
/// «Close the post» for the Post's author.
class PostBudInviteStep extends StatelessWidget {
  const PostBudInviteStep({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Column(
      key: const Key('PostBud.InviteStep'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ForwardRecipientPicker(
            beaconId: '',
            embedded: true,
            copyProfile: ForwardTargetProfile.postBudInvite,
            recipientNoteHint: l10n.postBudInviteNoteHint,
            header: BlocSelector<ForwardCubit, ForwardState, int>(
              selector: (s) => s.selectedIds.length,
              builder: (context, ticked) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.postBudInviteExplanation,
                    style: TenturaText.bodySmall(tt.textMuted),
                  ),
                  SizedBox(height: tt.rowGap),
                  if (ticked > kPostBudInviteWarningAbove)
                    _Notice(
                      key: const Key('PostBud.ManyWarning'),
                      icon: Icons.warning_amber_rounded,
                      iconColor: tt.warn,
                      text: l10n.postBudInviteManyWarning(ticked),
                    ),
                ],
              ),
            ),
          ),
        ),
        // Only the Post's author may close it (#666).
        BlocBuilder<ForwardCubit, ForwardState>(
          builder: (context, invite) =>
              BlocSelector<BeaconCreateCubit, BeaconCreateState, PostBudForm?>(
                selector: (s) => s.postBud,
                builder: (context, bud) {
                  if (bud == null || !bud.canClosePost(invite)) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const TenturaHairlineDivider(),
                      CheckboxListTile(
                        key: const Key('PostBud.ClosePost'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: bud.closePost(invite),
                        onChanged: (value) => context
                            .read<BeaconCreateCubit>()
                            .setBudClosePost(value ?? false),
                        title: Text(
                          l10n.postBudClosePost,
                          style: TenturaText.bodyMedium(tt.text),
                        ),
                      ),
                    ],
                  );
                },
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
