import 'package:meta/meta.dart';

import 'package:tentura_server/utils/id.dart';

enum HelpOfferAdmissionAction {
  autoAdmit(0),
  accept(1),
  decline(2),
  remove(3);

  const HelpOfferAdmissionAction(this.smallintValue);

  final int smallintValue;

  static HelpOfferAdmissionAction? tryFromInt(int? value) {
    if (value == null) return null;
    return switch (value) {
      0 => autoAdmit,
      1 => accept,
      2 => decline,
      3 => remove,
      _ => null,
    };
  }
}

@immutable
class HelpOfferAdmissionEvent {
  const HelpOfferAdmissionEvent({
    required this.id,
    required this.seq,
    required this.beaconId,
    required this.offerUserId,
    required this.actorUserId,
    required this.action,
    required this.createdAt,
    this.reason,
  });

  static String get newId => generateId('HA');

  final String id;
  final int seq;
  final String beaconId;
  final String offerUserId;
  final String actorUserId;
  final HelpOfferAdmissionAction action;
  final String? reason;
  final DateTime createdAt;
}
