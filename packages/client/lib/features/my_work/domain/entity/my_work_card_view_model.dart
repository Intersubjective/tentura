import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';

part 'my_work_card_view_model.freezed.dart';

/// Activity lines for the per-card NewStuff dot (see [MyWorkCardViewModel.newStuffReasons]).
enum MyWorkNewStuffReason {
  newBeacon,
  authorResponseChanged,
  commitmentUpdated,
  coordinationStatusChanged,
  beaconUpdated,
}

enum MyWorkCardRole { authored, committed }

enum MyWorkCardKind {
  authoredActive,
  authoredDraft,
  committedActive,
  authoredClosed,
  committedClosed,
}

enum MyWorkAttentionChip {
  /// Author: commitments waiting for review (beacon-level signal).
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
    @Default('') String commitMessage,
    CoordinationResponseType? authorResponseType,
    @Default([]) List<Profile> forwarderSenders,
    @Default(false) bool showReviewCommitmentsCta,
    @Default(false) bool showReadyForReviewChip,
    @Default(false) bool showReviewCta,
    @Default(false) bool showArchiveAffordance,
    MyWorkAttentionChip? attentionChip,
    /// Author has forwarded this beacon at least once (authored active cards).
    @Default(false) bool authorHasForwardedOnce,

    /// Committed cards: `beacon_commitment.updated_at` from My Work fetch.
    DateTime? commitmentRowUpdatedAt,

    /// Committed cards: `beacon_commitment_coordination.updated_at`.
    DateTime? authorCoordinationUpdatedAt,
  }) = _MyWorkCardViewModel;

  const MyWorkCardViewModel._();

  bool get isArchived =>
      kind == MyWorkCardKind.authoredClosed ||
      kind == MyWorkCardKind.committedClosed;

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
    if (role == MyWorkCardRole.committed) {
      final cr = commitmentRowUpdatedAt?.millisecondsSinceEpoch;
      if (cr != null && cr > max) {
        max = cr;
      }
      final ar = authorCoordinationUpdatedAt?.millisecondsSinceEpoch;
      if (ar != null && ar > max) {
        max = ar;
      }
    }
    return max;
  }

  static const _myWorkReasonDisplayOrder = <MyWorkNewStuffReason>[
    MyWorkNewStuffReason.newBeacon,
    MyWorkNewStuffReason.authorResponseChanged,
    MyWorkNewStuffReason.commitmentUpdated,
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
    final cr = commitmentRowUpdatedAt?.millisecondsSinceEpoch;
    final ar = authorCoordinationUpdatedAt?.millisecondsSinceEpoch;

    if (role == MyWorkCardRole.committed) {
      if (ar != null && ar > seen) {
        raw.add(MyWorkNewStuffReason.authorResponseChanged);
      }
      if (cr != null && cr > seen && (ar == null || cr != ar)) {
        raw.add(MyWorkNewStuffReason.commitmentUpdated);
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
