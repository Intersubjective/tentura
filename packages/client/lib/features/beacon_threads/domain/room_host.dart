import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/profile.dart';

/// Which strip is pinned above the room messages.
enum RoomPinnedStrip {
  /// Request rooms: the NOW line (and an open blocker under it).
  requestNow,

  /// Request rooms beside the Now pane (wide split): the pane already shows
  /// the NOW line, so the chat pins only an open blocker (#451).
  requestBlocker,

  /// Post rooms: the root message.
  postRoot,
}

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
    this.childPromotionOwnOnly = false,
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
      pinnedStrip = RoomPinnedStrip.requestNow,
      childPromotionOwnOnly = false;

  /// Every Request-only feature off.
  const RoomCapabilities.post()
    : facts = false,
      blocker = false,
      plan = false,
      coordinationItems = false,
      childPromotion = false,
      commitmentSheet = false,
      closure = false,
      pinnedStrip = RoomPinnedStrip.postRoot,
      childPromotionOwnOnly = true;

  final bool facts;
  final bool blocker;
  final bool plan;
  final bool coordinationItems;
  final bool childPromotion;
  final bool commitmentSheet;
  final bool closure;
  final RoomPinnedStrip pinnedStrip;

  /// A Request may be budded from the viewer's own messages only (Post rooms,
  /// «Оформить запрос»). The message actions evaluate ownership; the client
  /// gate `kPostBuddingEnabled` still decides whether the action shows.
  final bool childPromotionOwnOnly;

  /// The same features with another pinned strip.
  RoomCapabilities withPinnedStrip(RoomPinnedStrip strip) =>
      strip == pinnedStrip
      ? this
      : RoomCapabilities(
          facts: facts,
          blocker: blocker,
          plan: plan,
          coordinationItems: coordinationItems,
          childPromotion: childPromotion,
          commitmentSheet: commitmentSheet,
          closure: closure,
          pinnedStrip: strip,
          childPromotionOwnOnly: childPromotionOwnOnly,
        );

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
          pinnedStrip == other.pinnedStrip &&
          childPromotionOwnOnly == other.childPromotionOwnOnly;

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
    childPromotionOwnOnly,
  );
}

/// What the pinned strip of a Post room shows: the root message and, for a
/// recipient the Post was forwarded to, who forwarded it and their note.
@immutable
class RoomPostRootPin {
  const RoomPostRootPin({
    required this.messageId,
    required this.excerpt,
    this.forwardedBy = '',
    this.forwardNote = '',
  });

  final String messageId;
  final String excerpt;
  final String forwardedBy;
  final String forwardNote;

  bool get hasStrip => excerpt.isNotEmpty || forwardedBy.isNotEmpty;
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
