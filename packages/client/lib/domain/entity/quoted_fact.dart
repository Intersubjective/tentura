import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';

/// A room message's snapshot of a pinned fact at the moment it was quoted
/// (issue #181 plan §14.2): compares that snapshot against the fact's
/// current head to flag drift since the message was sent.
final class QuotedFact {
  const QuotedFact({
    required this.factCardId,
    required this.seq,
    required this.currentSeq,
    required this.status,
    required this.factText,
    this.pinnedById,
    this.pinnedByTitle = '',
    this.visibility = 0,
    this.attachments = const [],
  });

  final String factCardId;

  /// The revision seq quoted by the message.
  final int seq;

  /// The fact's current revision seq.
  final int currentSeq;

  /// The fact's current status ([BeaconFactCardStatusBits]).
  final int status;

  final String factText;

  final String? pinnedById;

  final String pinnedByTitle;

  /// The fact's visibility ([BeaconFactCardVisibilityBits]).
  final int visibility;

  /// Attachments of the fact's source message.
  final List<RoomMessageAttachment> attachments;

  /// The fact has been edited or restored since this message quoted it.
  bool get isChangedSinceQuoted => currentSeq > seq;

  /// The fact has since been unpinned.
  bool get isUnpinned => status == BeaconFactCardStatusBits.removed;
}
