import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:auto_route/auto_route.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/contacts/contact_name_overlay.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/updates/domain/entity/prompt_projection.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/features/updates/ui/widget/invite_accepted_receipt_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../domain/entity/inbox_item.dart';
import '../../domain/entity/inbox_provenance.dart';
import '../bloc/inbox_cubit.dart';
import 'activity_offer_bounded_shell.dart';
import 'inbox_card_actions.dart';
import 'inbox_forward_attribution_copy.dart';
import 'rejection_dialog.dart';

/// Bounded «Для вас» offer card (design §5.1): forward or invite prompt.
class ActivityOfferCard extends StatelessWidget {
  const ActivityOfferCard.forward({
    required this.item,
    required this.inboxCubit,
    required this.showUnseenDot,
    super.key,
  })  : _variant = _Variant.forward,
        receipt = null,
        onTap = null,
        onMarkSeen = _noopMarkSeen,
        onMarkUnseen = _noopMarkUnseen,
        promptProjection = null,
        onRetryPromptFetch = null,
        onPromptSettled = null,
        setupCase = null;

  const ActivityOfferCard.prompt({
    required this.receipt,
    required this.onTap,
    required this.onMarkSeen,
    required this.onMarkUnseen,
    this.promptProjection = const PromptProjection.unknown(),
    this.onRetryPromptFetch,
    this.onPromptSettled,
    this.setupCase,
    super.key,
  })  : _variant = _Variant.prompt,
        item = null,
        inboxCubit = null,
        showUnseenDot = false;

  final _Variant _variant;
  final InboxItem? item;
  final InboxCubit? inboxCubit;
  final bool showUnseenDot;
  final AttentionReceipt? receipt;
  final VoidCallback? onTap;
  final Future<void> Function() onMarkSeen;
  final VoidCallback onMarkUnseen;
  final PromptProjection? promptProjection;
  final Future<void> Function(String subjectId)? onRetryPromptFetch;
  final void Function(String subjectId, InviteSeedPromptState state)?
      onPromptSettled;
  final InviteAcceptedSetupPort? setupCase;

  @override
  Widget build(BuildContext context) {
    return switch (_variant) {
      _Variant.forward => _ForwardOfferCard(
        key: key,
        item: item!,
        inboxCubit: inboxCubit!,
        showUnseenDot: showUnseenDot,
      ),
      _Variant.prompt => KeyedSubtree(
        key: TestIds.key(TestIds.activityPromptPin(receipt!.id)),
        child: InviteAcceptedReceiptCard(
          receipt: receipt!,
          onTap: onTap!,
          onMarkSeen: onMarkSeen,
          onMarkUnseen: onMarkUnseen,
          promptProjection: promptProjection!,
          onRetryPromptFetch: onRetryPromptFetch,
          onPromptSettled: onPromptSettled,
          setupCase: setupCase,
          activityOfferBoundedShell: true,
        ),
      ),
    };
  }
}

enum _Variant { forward, prompt }

Future<void> _noopMarkSeen() async {}

void _noopMarkUnseen() {}

class _ForwardOfferCard extends StatelessWidget {
  const _ForwardOfferCard({
    required this.item,
    required this.inboxCubit,
    required this.showUnseenDot,
    super.key,
  });

  final InboxItem item;
  final InboxCubit inboxCubit;
  final bool showUnseenDot;

  Future<void> _openBeacon(BuildContext context) async {
    final beaconId = item.beaconId;
    await GetIt.I<AttentionCase>().markSeenForBeacon(beaconId);
    if (!context.mounted) return;
    await context.router.push(
      BeaconViewRoute(id: beaconId, entry: kBeaconEntryInbox),
    );
  }

  Future<void> _dismiss(BuildContext context) async {
    final msg = await showInboxDismissDialog(context);
    if (!context.mounted || msg == null) return;
    await inboxCubit.reject(item.beaconId, message: msg);
  }

  Profile? _leadingProfile(InboxProvenance provenance) {
    final sender = provenance.senders.isNotEmpty ? provenance.senders.first : null;
    if (sender == null) return null;
    return Profile(
      id: sender.id,
      displayName: sender.displayName,
      contactName: contactNameOf(sender.id),
      image: sender.imageId != null &&
              sender.imageId!.isNotEmpty &&
              sender.imageId != 'null'
          ? ImageEntity(id: sender.imageId!, authorId: sender.id)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final beacon = item.beacon;
    if (beacon == null) return const SizedBox.shrink();

    final provenance = item.provenance;
    final profile = _leadingProfile(provenance);
    final whyLine = inboxForwardWhyLine(provenance, l10n);
    final showOfferHelp = inboxCardAllowsOfferHelp(item);
    final allowsForward = beacon.allowsForward;

    final footer = Padding(
      padding: EdgeInsets.only(left: tt.tightGap),
      child: Wrap(
        spacing: tt.rowGap,
        runSpacing: tt.tightGap,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (showOfferHelp)
            FilledButton.tonal(
              key: TestIds.key(TestIds.inboxOfferHelp),
              onPressed: () => unawaited(inboxOfferHelp(context, beacon)),
              style: FilledButton.styleFrom(
                minimumSize: Size(0, tt.buttonHeight),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.symmetric(
                  horizontal: tt.rowGap,
                  vertical: tt.tightGap,
                ),
              ),
              child: Text(l10n.labelOfferHelp),
            ),
          if (allowsForward)
            TenturaTextAction(
              label: l10n.labelForward,
              semanticsIdentifier: TestIds.inboxForward,
              onPressed: () => unawaited(inboxForwardItem(context, item)),
            ),
          TenturaTextAction(
            label: l10n.beaconHeaderWatch,
            onPressed: () => unawaited(inboxCubit.setWatching(item.beaconId)),
          ),
        ],
      ),
    );

    return Semantics(
      identifier: TestIds.activityOffer(item.beaconId),
      child: ActivityOfferBoundedShell(
        leading: profile != null
            ? TenturaAvatar(
                profile: profile,
                sizeBucket: TenturaAvatarSize.medium,
              )
            : SizedBox.square(dimension: tt.avatarSize),
        headline: beacon.title,
        whyLine: whyLine,
        createdAt: item.latestForwardAt,
        showUnseenDot: showUnseenDot,
        onBodyTap: () => unawaited(_openBeacon(context)),
        onDismiss: () => unawaited(_dismiss(context)),
        footer: footer,
      ),
    );
  }
}
