import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/offer_accepted_dismissals.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// B077 — «Your help was accepted · `acceptor`» as an event sub-card, shown to
/// the helper inside the Request card on the Requests tab and on the Request
/// screen's People tab until they dismiss it with ×.
///
/// It is the house event sub-card ([AttentionMiniCard]): author avatar, the
/// event line, its age, and the ×. The dismissal lives in
/// [OfferAcceptedDismissals], so dismissing it in one place dismisses it in
/// both and on every device of the account, and it stays dismissed.
class OfferAcceptedEventSubcard extends StatelessWidget {
  const OfferAcceptedEventSubcard({
    required this.beaconId,
    required this.viewerId,
    required this.author,
    required this.acceptedAt,
    this.acceptorId,
    this.acceptor,
    this.requestTitle,
    this.onDismissed,
    this.padding = EdgeInsets.zero,
    this.store,
    super.key,
  });

  /// The presentation key the server gives the matching attention receipt.
  static const presentationKey = 'offer_accepted';

  final String beaconId;
  final String viewerId;
  final Profile author;
  final DateTime acceptedAt;

  /// Who accepted the offer, when known (#507: the author or a steward).
  /// Unknown or the author's id: the sub-card names the [author].
  final String? acceptorId;

  /// [acceptorId]'s profile when the caller has it. Someone other than the
  /// author with no profile at hand is not named (never the author instead).
  final Profile? acceptor;

  final String? requestTitle;

  /// Runs after the dismissal is recorded (e.g. to clear the matching
  /// server receipt as well).
  final VoidCallback? onDismissed;

  final EdgeInsetsGeometry padding;

  /// Test seam; defaults to [OfferAcceptedDismissals.instance].
  final OfferAcceptedDismissals? store;

  @override
  Widget build(BuildContext context) {
    final dismissals = store ?? OfferAcceptedDismissals.instance;
    final l10n = L10n.of(context)!;
    unawaited(dismissals.ensureLoadedFor(viewerId));
    return ListenableBuilder(
      listenable: dismissals,
      builder: (context, _) {
        if (!dismissals.shouldShow(viewerId: viewerId, beaconId: beaconId)) {
          return const SizedBox.shrink();
        }
        final id = acceptorId?.trim() ?? '';
        final byAuthor = id.isEmpty || id == author.id;
        final actor = byAuthor ? author : acceptor;
        final name = actor?.shownName.trim() ?? '';
        return Padding(
          padding: padding,
          child: AttentionMiniCard(
            receipt: AttentionReceipt(
              id: 'offer-accepted:$beaconId',
              category: 'asksOfMe',
              kind: 'offerAccepted',
              priority: 'normal',
              title: '',
              body: '',
              actionUrl: '',
              createdAt: acceptedAt,
              collapsedCount: 1,
              presentationPayloadJson: '{}',
              beaconId: beaconId,
              actorUserId: actor?.id ?? id,
              presentationKey: presentationKey,
              surface: AttentionSurface.myWork,
            ),
            actor: actor,
            requestTitle: requestTitle,
            eventLine: byAuthor || name.isNotEmpty
                ? l10n.attentionCardOfferAccepted(name)
                : l10n.activityForwardOutcomeAcceptedNoAuthor,
            onDismiss: () {
              unawaited(
                dismissals.dismiss(viewerId: viewerId, beaconId: beaconId),
              );
              onDismissed?.call();
            },
          ),
        );
      },
    );
  }
}
