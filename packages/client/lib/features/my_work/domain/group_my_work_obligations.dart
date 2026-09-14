import 'package:tentura/domain/attention/entity/attention_receipt.dart';

/// One desk sub-card after grouping live obligations (D-SC6 / D-SC7).
class MyWorkObligationGroup {
  const MyWorkObligationGroup({
    required this.receipts,
    required this.presentationKey,
    this.offererId,
  });

  /// Newest-first; first row drives copy / avatar.
  final List<AttentionReceipt> receipts;
  final String? presentationKey;

  /// Person key for `help_offer_submitted` groups; null for other kinds.
  final String? offererId;

  AttentionReceipt get primary => receipts.first;

  List<String> get receiptIds => [for (final r in receipts) r.id];

  bool get isHelpOffer => presentationKey == 'help_offer_submitted';

  bool get isReview => presentationKey == 'review_opened';
}

String? myWorkObligationOffererId(AttentionReceipt receipt) {
  final target = receipt.targetEntityId?.trim();
  if (target != null && target.isNotEmpty) return target;
  final actor = receipt.actorUserId?.trim();
  if (actor != null && actor.isNotEmpty) return actor;
  return null;
}

/// Groups live obligations for My Desk sub-cards.
///
/// `help_offer_submitted` rows share a person key; other kinds stay one
/// receipt per group. Order follows the input list (newest first from server).
List<MyWorkObligationGroup> groupMyWorkObligations(
  List<AttentionReceipt> obligations,
) {
  final groups = <MyWorkObligationGroup>[];
  final offerIndexByKey = <String, int>{};

  for (final receipt in obligations) {
    final key = receipt.presentationKey;
    if (key == 'help_offer_submitted') {
      final offererId = myWorkObligationOffererId(receipt);
      if (offererId != null) {
        final existing = offerIndexByKey[offererId];
        if (existing != null) {
          final prev = groups[existing];
          groups[existing] = MyWorkObligationGroup(
            receipts: [...prev.receipts, receipt],
            presentationKey: key,
            offererId: offererId,
          );
          continue;
        }
        offerIndexByKey[offererId] = groups.length;
        groups.add(
          MyWorkObligationGroup(
            receipts: [receipt],
            presentationKey: key,
            offererId: offererId,
          ),
        );
        continue;
      }
    }
    groups.add(
      MyWorkObligationGroup(
        receipts: [receipt],
        presentationKey: key,
        offererId: key == 'help_offer_submitted'
            ? myWorkObligationOffererId(receipt)
            : null,
      ),
    );
  }
  return groups;
}
