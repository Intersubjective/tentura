import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/offer_accepted_dismissals.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// B077 — «Your help was accepted · `author`» as an event sub-card, shown to
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
        final name = author.shownName.trim();
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
              actorUserId: author.id,
              presentationKey: presentationKey,
              surface: AttentionSurface.myWork,
            ),
            actor: author,
            requestTitle: requestTitle,
            eventLine: l10n.attentionCardOfferAccepted(name),
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
