import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';

import 'my_work_last_event.dart';

part 'my_work_card_view_model.freezed.dart';

/// Activity lines for the per-card NewStuff dot (see [MyWorkCardViewModel.newStuffReasons]).
enum MyWorkNewStuffReason {
  newBeacon,
  authorResponseChanged,
  helpOfferUpdated,
  coordinationStatusChanged,
  beaconUpdated,
}

enum MyWorkCardRole { authored, helpOffered }

enum MyWorkCardKind {
  authoredActive,
  authoredDraft,
  helpOfferedActive,
  authoredClosed,
  helpOfferedClosed,
}

enum MyWorkAttentionChip {
  /// Author: help offers waiting for review (beacon-level signal).
  reviewPending,

  /// Author: beacon in closed-review-open (evaluation window).
  reviewWindowOpen,

  /// Author: beacon-level "more help needed".
  moreHelpNeeded,
}

@freezed
abstract class MyWorkCardViewModel with _$MyWorkCardViewModel {
  const factory MyWorkCardViewModel({
    required String beaconId,
    required MyWorkCardRole role,
    required MyWorkCardKind kind,
    required Beacon beacon,
    @Default('') String offerHelpMessage,
    CoordinationResponseType? authorResponseType,
    @Default([]) List<Profile> forwarderSenders,
    @Default(false) bool showReviewHelpOffersCta,
    @Default(false) bool showReadyForReviewChip,
    @Default(false) bool showReviewCta,
    @Default(false) bool showArchiveAffordance,
    MyWorkAttentionChip? attentionChip,
    /// Author has forwarded this beacon at least once (authored active cards).
    @Default(false) bool authorHasForwardedOnce,

    /// Admitted room coordination summary line (Phase 6).
    @Default('') String roomInboxSubtitle,

    /// Help-offered cards: `beacon_help_offers.updated_at` from My Work fetch.
    DateTime? helpOfferRowUpdatedAt,

    /// Help-offered cards: `beacon_help_offer_coordinations.updated_at`.
    DateTime? authorCoordinationUpdatedAt,

    /// Latest message on an active item discussion thread for this beacon.
    DateTime? lastCoordinationItemMessageAt,

    /// Latest meaningful coordination-log event (V2 batch).
    MyWorkLastEvent? lastActivityEvent,
  }) = _MyWorkCardViewModel;

  const MyWorkCardViewModel._();

  bool get isArchived =>
      kind == MyWorkCardKind.authoredClosed ||
      kind == MyWorkCardKind.helpOfferedClosed;

  /// Max relevant backend activity for NewStuff (tab dot + row dot), in epoch ms.
  int get newStuffActivityEpochMs {
    final b = beacon;
    var max = b.createdAt.millisecondsSinceEpoch;
    if (b.updatedAt.millisecondsSinceEpoch > max) {
      max = b.updatedAt.millisecondsSinceEpoch;
    }
    final cs = b.coordinationStatusUpdatedAt?.millisecondsSinceEpoch;
    if (cs != null && cs > max) {
      max = cs;
    }
    if (role == MyWorkCardRole.helpOffered) {
      final cr = helpOfferRowUpdatedAt?.millisecondsSinceEpoch;
      if (cr != null && cr > max) {
        max = cr;
      }
      final ar = authorCoordinationUpdatedAt?.millisecondsSinceEpoch;
      if (ar != null && ar > max) {
        max = ar;
      }
    }
    final itemMsg = lastCoordinationItemMessageAt?.millisecondsSinceEpoch;
    if (itemMsg != null && itemMsg > max) {
      max = itemMsg;
    }
    return max;
  }

  static const _myWorkReasonDisplayOrder = <MyWorkNewStuffReason>[
    MyWorkNewStuffReason.newBeacon,
    MyWorkNewStuffReason.authorResponseChanged,
    MyWorkNewStuffReason.helpOfferUpdated,
    MyWorkNewStuffReason.coordinationStatusChanged,
    MyWorkNewStuffReason.beaconUpdated,
  ];

  /// All distinct reasons for the dot when [lastSeenMs] matches the My Work last-seen cursor.
  List<MyWorkNewStuffReason> newStuffReasons(int? lastSeenMs) {
    if (lastSeenMs == null) return [];
    final b = beacon;
    final seen = lastSeenMs;
    final raw = <MyWorkNewStuffReason>[];

    if (b.createdAt.millisecondsSinceEpoch > seen) {
      raw.add(MyWorkNewStuffReason.newBeacon);
    }
    if (newStuffActivityEpochMs <= seen) {
      return _orderMyWorkReasons(raw);
    }

    final u = b.updatedAt.millisecondsSinceEpoch;
    final cs = b.coordinationStatusUpdatedAt?.millisecondsSinceEpoch;
    final cr = helpOfferRowUpdatedAt?.millisecondsSinceEpoch;
    final ar = authorCoordinationUpdatedAt?.millisecondsSinceEpoch;

    if (role == MyWorkCardRole.helpOffered) {
      if (ar != null && ar > seen) {
        raw.add(MyWorkNewStuffReason.authorResponseChanged);
      }
      if (cr != null && cr > seen && (ar == null || cr != ar)) {
        raw.add(MyWorkNewStuffReason.helpOfferUpdated);
      }
    }
    if (cs != null && cs > seen) {
      raw.add(MyWorkNewStuffReason.coordinationStatusChanged);
    }
    if (u > seen && (cs == null || u != cs)) {
      raw.add(MyWorkNewStuffReason.beaconUpdated);
    }
    return _orderMyWorkReasons(raw);
  }

  static List<MyWorkNewStuffReason> _orderMyWorkReasons(
    List<MyWorkNewStuffReason> raw,
  ) {
    final out = <MyWorkNewStuffReason>[];
    for (final r in _myWorkReasonDisplayOrder) {
      if (raw.contains(r)) {
        out.add(r);
      }
    }
    return out;
  }
}
