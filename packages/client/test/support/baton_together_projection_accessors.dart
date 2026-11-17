import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';

/// Reads partner projection fields when present on a dynamic projection map.
T? _tryDynamicField<T>(Object target, String name) {
  try {
    return switch (name) {
      'myPartner' => (target as dynamic).myPartner as T?,
      'coTaker' => (target as dynamic).coTaker as T?,
      'pairs' => (target as dynamic).pairs as T?,
      'partnerInvites' => (target as dynamic).partnerInvites as T?,
      'partner' => (target as dynamic).partner as T?,
      _ => null,
    };
  } on Object {
    return null;
  }
}

String? candidatePartnerStatus(RoomBatonData? baton) {
  if (baton is! RoomBatonCandidateData) return null;
  final partner = _tryDynamicField<Object>(baton, 'myPartner');
  if (partner == null) return null;
  try {
    final status = (partner as dynamic).status;
    return status is String ? status : null;
  } on Object {
    return null;
  }
}

int? authorConfirmedPairCount(RoomBatonData? baton) {
  if (baton is! RoomBatonAuthorData) return null;
  final pairs = _tryDynamicField<List<Object>>(baton, 'pairs');
  return pairs?.length;
}

RoomBatonTaker? observerCoTaker(RoomBatonData? baton) {
  if (baton is! RoomBatonObserverData) return null;
  return _tryDynamicField<RoomBatonTaker>(baton, 'coTaker');
}

int? partnerInviteCount(RoomBatonData? baton) {
  if (baton == null) return null;
  final invites = _tryDynamicField<List<Object>>(baton, 'partnerInvites');
  return invites?.length;
}

int? candidatePartnerInvitesCount(RoomBatonData? baton) {
  if (baton is! RoomBatonCandidateData) return null;
  return partnerInviteCount(baton);
}

String? partnerRoleOutcome(RoomBatonData? baton) {
  if (baton == null) return null;
  try {
    final outcome = (baton as dynamic).outcome;
    if (outcome is RoomBatonOutcome) {
      return switch (outcome) {
        RoomBatonOutcome.you => 'you',
        RoomBatonOutcome.someoneElse => 'someoneElse',
        RoomBatonOutcome.closed => 'closed',
      };
    }
    final wire = (baton as dynamic).outcome;
    return wire is String ? wire : null;
  } on Object {
    return null;
  }
}

String? partnerInviteFromTitle(RoomBatonData? baton, String fromUserId) {
  if (baton == null) return null;
  final invites = _tryDynamicField<List<Object>>(baton, 'partnerInvites');
  if (invites == null) return null;
  for (final raw in invites) {
    if (raw is RoomBatonPartnerInvite) {
      if (raw.fromUserId != fromUserId) continue;
      return raw.title;
    }
    if (raw is! Map) continue;
    if (raw['fromUserId'] != fromUserId) continue;
    final title = raw['title'];
    return title is String ? title : null;
  }
  return null;
}

String? batonCoTakerUserId(RoomMessage message) =>
    RoomMessageTile.batonCoTakerUserId(message);

RoomBatonTaker? authorCoTaker(RoomBatonData? baton) {
  if (baton is! RoomBatonAuthorData) return null;
  return _tryDynamicField<RoomBatonTaker>(baton, 'coTaker');
}

RoomBatonTaker? candidateCoTaker(RoomBatonData? baton) {
  if (baton is! RoomBatonCandidateData) return null;
  return _tryDynamicField<RoomBatonTaker>(baton, 'coTaker');
}

Matcher isRoomBatonPartnerData() => isA<RoomBatonPartnerData>();

String? authorCandidatePartnerId(RoomBatonCandidate candidate) {
  final partner = candidate.partner;
  if (partner != null) return partner.id;
  final dynamicPartner = _tryDynamicField<Object>(candidate, 'partner');
  if (dynamicPartner == null) return null;
  try {
    final id = (dynamicPartner as dynamic).id;
    return id is String ? id : null;
  } on Object {
    return null;
  }
}
