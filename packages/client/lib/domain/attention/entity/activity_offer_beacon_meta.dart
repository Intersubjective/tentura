import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'attention_receipt.dart';

/// One Request's event preview and counts in the Activity pinned zone.
///
/// It lives in the domain, beside [AttentionReceipt], because §0.3 allows
/// exactly one owner of attention state. A screen may hold what the owner
/// handed it; it may not derive it, which is why nothing outside
/// `lib/domain/attention/` is allowed to construct this class
/// (`test/architecture/single_attention_owner_test.dart`).
@immutable
final class ActivityOfferBeaconMeta {
  const ActivityOfferBeaconMeta({
    required this.eventTotal,
    this.eventUnseenCount = 0,
    this.eventsPreview = const [],
    this.unseen = false,
  });

  final int eventTotal;
  final int eventUnseenCount;
  final List<AttentionReceipt> eventsPreview;
  final bool unseen;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityOfferBeaconMeta &&
          other.eventTotal == eventTotal &&
          other.eventUnseenCount == eventUnseenCount &&
          other.unseen == unseen &&
          const ListEquality<AttentionReceipt>().equals(
            other.eventsPreview,
            eventsPreview,
          );

  @override
  int get hashCode => Object.hash(
    eventTotal,
    eventUnseenCount,
    unseen,
    const ListEquality<AttentionReceipt>().hash(eventsPreview),
  );
}
