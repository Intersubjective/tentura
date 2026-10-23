import 'dart:convert';

import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_message.dart';

/// Which Request text a `requestEdited` line is about.
enum RoomRequestEditField { nextStep, title }

/// What a `requestEdited` system line says (server contract, #528): payload
/// `{version: 1, field, from, to, edits?}`. The actor is the line's author;
/// a null author is an account deleted since (`ON DELETE SET NULL`). One
/// person's run of edits of one field is one line: [to] is the latest
/// value and [edits] how many edits the line stands for.
class RoomRequestEdit {
  const RoomRequestEdit({
    required this.field,
    required this.from,
    required this.to,
    this.edits = 1,
  });

  /// Null for any other row or an unreadable payload.
  static RoomRequestEdit? fromMessage(RoomMessage m) {
    if (m.systemMessageKind != BeaconRoomSystemMessageKind.requestEdited) {
      return null;
    }
    final raw = m.systemPayloadJson;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['version'] != 1) return null;
      final field = switch (decoded['field']) {
        RequestEditField.nextStep => RoomRequestEditField.nextStep,
        RequestEditField.title => RoomRequestEditField.title,
        _ => null,
      };
      final from = decoded['from'];
      final to = decoded['to'];
      if (field == null || from is! String || to is! String) return null;
      final edits = decoded['edits'];
      return RoomRequestEdit(
        field: field,
        from: from.trim(),
        to: to.trim(),
        edits: edits is int && edits > 1 ? edits : 1,
      );
    } on Object {
      return null;
    }
  }

  final RoomRequestEditField field;
  final String from;
  final String to;
  final int edits;
}
