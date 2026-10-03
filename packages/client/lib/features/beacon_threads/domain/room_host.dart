import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/profile.dart';

/// Which strip is pinned above the room messages.
enum RoomPinnedStrip { requestNow, postRoot }

/// Request-only room features a [RoomHost] turns on or off.
@immutable
class RoomCapabilities {
  const RoomCapabilities({
    required this.facts,
    required this.blocker,
    required this.plan,
    required this.coordinationItems,
    required this.childPromotion,
    required this.commitmentSheet,
    required this.closure,
    required this.pinnedStrip,
  });

  /// Every Request feature on.
  const RoomCapabilities.request()
    : facts = true,
      blocker = true,
      plan = true,
      coordinationItems = true,
      childPromotion = true,
      commitmentSheet = true,
      closure = true,
      pinnedStrip = RoomPinnedStrip.requestNow;

  /// Every Request-only feature off.
  const RoomCapabilities.post()
    : facts = false,
      blocker = false,
      plan = false,
      coordinationItems = false,
      childPromotion = false,
      commitmentSheet = false,
      closure = false,
      pinnedStrip = RoomPinnedStrip.postRoot;

  final bool facts;
  final bool blocker;
  final bool plan;
  final bool coordinationItems;
  final bool childPromotion;
  final bool commitmentSheet;
  final bool closure;
  final RoomPinnedStrip pinnedStrip;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomCapabilities &&
          facts == other.facts &&
          blocker == other.blocker &&
          plan == other.plan &&
          coordinationItems == other.coordinationItems &&
          childPromotion == other.childPromotion &&
          commitmentSheet == other.commitmentSheet &&
          closure == other.closure &&
          pinnedStrip == other.pinnedStrip;

  @override
  int get hashCode => Object.hash(
    facts,
    blocker,
    plan,
    coordinationItems,
    childPromotion,
    commitmentSheet,
    closure,
    pinnedStrip,
  );
}

/// What the room surface reads from the screen that hosts it.
abstract interface class RoomHost {
  String get beaconId;

  Profile get author;

  BeaconStatus get status;

  bool get isAdmissionBlocked;

  bool get coordinationDeniesAdmission;

  RoomCapabilities get capabilities;

  Stream<void> get changes;
}
