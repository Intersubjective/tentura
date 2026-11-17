import 'package:tentura_server/domain/entity/room_baton.dart';
import 'package:tentura_server/domain/exception.dart';

enum BatonPairReceiptKind { partnerAsked, partnerAnswered }

/// A notification the caller should record for [recipientId].
class BatonPairReceipt {
  const BatonPairReceipt({
    required this.kind,
    required this.recipientId,
    required this.fromUserId,
    required this.key,
    this.accepted,
  });

  final BatonPairReceiptKind kind;
  final String recipientId;

  /// Who the receipt is from: the asker of [BatonPairReceiptKind.partnerAsked],
  /// the person who answered for [BatonPairReceiptKind.partnerAnswered].
  final String fromUserId;
  final String key;

  /// Set for [BatonPairReceiptKind.partnerAnswered] only.
  final bool? accepted;
}

/// The baton's candidate rows after an action, plus the receipts it produced.
class BatonPairResult {
  const BatonPairResult({required this.rows, required this.receipts});

  final List<RoomBatonCandidate> rows;
  final List<BatonPairReceipt> receipts;
}

/// «Take it on together» rules (`docs/plans/baton-together-plan.md` §2.4):
/// pure row mutations plus receipt intents; the use case loads, locks,
/// applies and records.
abstract final class BatonPairPolicy {
  BatonPairPolicy._();

  static const maxDistinctPartners = 3;

  static BatonPairResult respond({
    required List<RoomBatonCandidate> rows,
    required String actorId,
    required bool canHelp,
    required DateTime now,
    String? partnerUserId,
  }) {
    if (partnerUserId != null && (!canHelp || partnerUserId == actorId)) {
      throw const BatonPartnerInvalidException();
    }
    final actor =
        _rowOf(rows, actorId) ?? (throw const BatonNotCandidateException());
    final response = canHelp ? BatonResponse.canHelp : BatonResponse.cantHelp;
    final current = actor.partnerUserId;
    final receipts = <BatonPairReceipt>[];

    if (partnerUserId == null) {
      final next = _replace(
        rows,
        _row(actor, response: response, respondedAt: now),
      );
      return BatonPairResult(
        rows: _releaseBroken(next, actorId, now, receipts),
        receipts: receipts,
      );
    }

    final isNew = partnerUserId != current;
    if (isNew && actor.partnerInvites >= maxDistinctPartners) {
      throw const BatonPartnerInvalidException(
        description: 'Too many partners named',
      );
    }
    final invites = actor.partnerInvites + (isNew ? 1 : 0);
    final other = _rowOf(rows, partnerUserId);
    final namedBack =
        other != null &&
        other.response == BatonResponse.canHelp &&
        other.partnerUserId == actorId &&
        other.partnerResponse != null &&
        other.partnerResponse != BatonPartnerResponse.declined;

    var next = rows;
    if (namedBack) {
      final wasPending = other.partnerResponse == BatonPartnerResponse.pending;
      next = _replace(
        next,
        _row(
          actor,
          response: response,
          respondedAt: now,
          partner: partnerUserId,
          partnerResponse: BatonPartnerResponse.accepted,
          invites: invites,
        ),
      );
      next = _replace(
        next,
        _row(
          other,
          response: other.response,
          respondedAt: other.respondedAt,
          partner: actorId,
          partnerResponse: BatonPartnerResponse.accepted,
          invites: other.partnerInvites,
        ),
      );
      if (wasPending) {
        receipts.add(
          _answered(actor.batonId, actorId, partnerUserId, now, accepted: true),
        );
      }
      next = _releaseBroken(next, actorId, now, receipts);
      return BatonPairResult(
        rows: _settle(next, actorId, partnerUserId, now, receipts),
        receipts: receipts,
      );
    }

    final keepsAnswer =
        !isNew &&
        current != null &&
        actor.partnerResponse == BatonPartnerResponse.accepted;
    next = _replace(
      next,
      _row(
        actor,
        response: response,
        respondedAt: now,
        partner: partnerUserId,
        partnerResponse: keepsAnswer
            ? BatonPartnerResponse.accepted
            : BatonPartnerResponse.pending,
        invites: invites,
      ),
    );
    if (isNew) {
      receipts.add(
        BatonPairReceipt(
          kind: BatonPairReceiptKind.partnerAsked,
          recipientId: partnerUserId,
          fromUserId: actorId,
          key: 'baton_partner_asked:${actor.batonId}:$actorId:$partnerUserId',
        ),
      );
    }
    return BatonPairResult(
      rows: _releaseBroken(next, actorId, now, receipts),
      receipts: receipts,
    );
  }

  static BatonPairResult partnerRespond({
    required List<RoomBatonCandidate> rows,
    required String actorId,
    required String inviterId,
    required bool accept,
    required DateTime now,
  }) {
    final inviter = _rowOf(rows, inviterId);
    if (inviter == null ||
        inviter.partnerUserId != actorId ||
        inviter.partnerResponse == null ||
        inviter.partnerResponse == BatonPartnerResponse.declined) {
      throw const BatonNotPartnerException();
    }
    final receipts = <BatonPairReceipt>[];
    final actor = _rowOf(rows, actorId);

    if (!accept) {
      var next = _replace(rows, _declined(inviter));
      if (actor != null && actor.partnerUserId == inviterId) {
        next = _replace(
          next,
          _row(
            actor,
            response: actor.response,
            respondedAt: actor.respondedAt,
            invites: actor.partnerInvites,
          ),
        );
      }
      receipts.add(
        _answered(inviter.batonId, inviterId, actorId, now, accepted: false),
      );
      return BatonPairResult(rows: next, receipts: receipts);
    }

    if (inviter.partnerResponse == BatonPartnerResponse.accepted) {
      return BatonPairResult(rows: rows, receipts: const []);
    }
    var next = _replace(
      rows,
      _row(
        inviter,
        response: inviter.response,
        respondedAt: inviter.respondedAt,
        partner: actorId,
        partnerResponse: BatonPartnerResponse.accepted,
        invites: inviter.partnerInvites,
      ),
    );
    if (actor != null) {
      next = _replace(
        next,
        _row(
          actor,
          response: BatonResponse.canHelp,
          respondedAt: actor.response == BatonResponse.canHelp
              ? actor.respondedAt
              : now,
          partner: inviterId,
          partnerResponse: BatonPartnerResponse.accepted,
          invites: actor.partnerInvites,
        ),
      );
    }
    receipts.add(
      _answered(inviter.batonId, inviterId, actorId, now, accepted: true),
    );
    next = _releaseBroken(next, actorId, now, receipts);
    return BatonPairResult(
      rows: _settle(next, inviterId, actorId, now, receipts),
      receipts: receipts,
    );
  }

  /// One accepted pair per person: every other accepted row that involves
  /// either member of the new pair goes back to waiting and is told.
  static List<RoomBatonCandidate> _settle(
    List<RoomBatonCandidate> rows,
    String a,
    String b,
    DateTime now,
    List<BatonPairReceipt> receipts,
  ) {
    var next = rows;
    for (final row in rows) {
      final inPair = {row.userId, row.partnerUserId}.difference({a, b}).isEmpty;
      final involves = {row.userId, row.partnerUserId}.any(
        (id) => id == a || id == b,
      );
      if (row.partnerResponse == BatonPartnerResponse.accepted &&
          involves &&
          !inPair) {
        next = _replace(next, _declined(row));
        receipts.add(
          _answered(
            row.batonId,
            row.userId,
            row.partnerUserId!,
            now,
            accepted: false,
          ),
        );
      }
    }
    return next;
  }

  /// When [actorId] changed away from a pair, whoever was accepted with them
  /// is released.
  static List<RoomBatonCandidate> _releaseBroken(
    List<RoomBatonCandidate> rows,
    String actorId,
    DateTime now,
    List<BatonPairReceipt> receipts,
  ) {
    final actor = _rowOf(rows, actorId);
    var next = rows;
    for (final row in rows) {
      if (row.userId != actorId &&
          row.partnerUserId == actorId &&
          row.partnerResponse == BatonPartnerResponse.accepted &&
          actor != null &&
          actor.partnerUserId != row.userId) {
        next = _replace(next, _declined(row));
        receipts.add(
          _answered(row.batonId, row.userId, actorId, now, accepted: false),
        );
      }
    }
    return next;
  }

  static RoomBatonCandidate? _rowOf(List<RoomBatonCandidate> rows, String id) {
    for (final row in rows) {
      if (row.userId == id) {
        return row;
      }
    }
    return null;
  }

  static List<RoomBatonCandidate> _replace(
    List<RoomBatonCandidate> rows,
    RoomBatonCandidate row,
  ) => [
    for (final r in rows)
      if (r.userId == row.userId) row else r,
  ];

  /// Back to waiting; the partner marker stays as «declined» without a name.
  static RoomBatonCandidate _declined(RoomBatonCandidate row) => _row(
    row,
    response: BatonResponse.waiting,
    partnerResponse: BatonPartnerResponse.declined,
    invites: row.partnerInvites,
  );

  static RoomBatonCandidate _row(
    RoomBatonCandidate base, {
    required BatonResponse response,
    DateTime? respondedAt,
    String? partner,
    BatonPartnerResponse? partnerResponse,
    int? invites,
  }) => RoomBatonCandidate(
    batonId: base.batonId,
    userId: base.userId,
    tier: base.tier,
    response: response,
    respondedAt: respondedAt,
    partnerUserId: partner,
    partnerResponse: partnerResponse,
    partnerInvites: invites ?? base.partnerInvites,
  );

  static BatonPairReceipt _answered(
    String batonId,
    String inviterId,
    String answererId,
    DateTime now, {
    required bool accepted,
  }) => BatonPairReceipt(
    kind: BatonPairReceiptKind.partnerAnswered,
    recipientId: inviterId,
    fromUserId: answererId,
    key:
        'baton_partner_answered:$batonId:$inviterId:$answererId:'
        '${now.microsecondsSinceEpoch}',
    accepted: accepted,
  );
}
