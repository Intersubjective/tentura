import 'dart:math';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/room_baton.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/baton_pair_policy.dart';
import 'package:tentura_server/domain/policy/baton_selection_policy.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/use_case/room_write_guard.dart';
import 'package:tentura_server/domain/use_case/room_message_rate_limit.dart';
import 'package:tentura_server/domain/policy/room_access_policy.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/post_lock_port.dart';
import 'package:tentura_server/domain/port/room_baton_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '_use_case_base.dart';

/// «Who'll take it?» (baton) — plan §2.2/B4
/// (`docs/plans/baton-who-takes-it-plan.md`): `create` + `respond`.
/// `select` + `cancel` (B5).
@Singleton(order: 2)
class RoomBatonCase extends UseCaseBase {
  RoomBatonCase(
    this._repo,
    this._room,
    this._hierarchyRepository,
    this._postLock,
    this._attention,
    this._attentionIntents, {
    Random? random,
    required super.env,
    required super.logger,
  }) : _random = random ?? Random.secure();

  final RoomBatonRepositoryPort _repo;
  final BeaconRoomRepositoryPort _room;
  final BeaconHierarchyRepositoryPort _hierarchyRepository;
  final PostLockPort _postLock;
  final TransactionalAttentionCase _attention;
  final AttentionIntentCase _attentionIntents;
  final Random _random;

  Future<void> _rejectIfRoomNotWritable(String beaconId) =>
      _hierarchyRepository.rejectIfRoomReadOnly(beaconId);

  Future<Set<String>> _admittedIds(String beaconId) async {
    final admitted = await _room.listAdmittedMentionParticipants(beaconId);
    return {for (final p in admitted) p.userId};
  }

  /// [RoomAccessPolicy.canUseRoom] without the Post-author block step: the
  /// author and stewards always have room access regardless of their
  /// `beacon_participant` row, which an admitted-only check (the baton's
  /// actual candidate-eligibility rule) would wrongly reject them for.
  Future<bool> _isAdmitted({
    required String beaconId,
    required String userId,
  }) => RoomAccessPolicy.canUseRoom(
    isAuthor: () => _room.isBeaconAuthor(beaconId: beaconId, userId: userId),
    isBlockedFromPost: () async => false,
    isSteward: () => _room.isBeaconSteward(beaconId: beaconId, userId: userId),
    roomAccess: () async => (await _room.findParticipant(
      beaconId: beaconId,
      userId: userId,
    ))?.roomAccess,
  );

  /// Posts a new «Who'll take it?» message ([text], optionally replying to
  /// [replyToMessageId]) at the end of the room and asks [candidates] on it.
  /// [text] may be empty only when the baton replies to a message, which then
  /// supplies the context.
  Future<RoomBaton> create({
    required String actorId,
    required String beaconId,
    required String text,
    required List<({String userId, int tier})> candidates,
    String? replyToMessageId,
  }) => _attention.runAction(
    actorUserId: actorId,
    action: (transaction) async {
      final body = text.trim();
      if (body.length > kMaxRoomMessageBodyLength) {
        throw const BeaconCreateException(description: 'Message is too long');
      }
      final replyTo = replyToMessageId == null
          ? null
          : await _room.getRoomMessageById(replyToMessageId);
      if (replyToMessageId != null &&
          (replyTo == null ||
              replyTo.beaconId != beaconId ||
              replyTo.threadItemId != null)) {
        throw const BatonMessageNotEligibleException();
      }
      if (body.isEmpty && replyTo == null) {
        throw const BatonMessageNotEligibleException();
      }
      await _postLock.lockForPostMutation(beaconId);

      await _rejectIfRoomNotWritable(beaconId);
      if (!await _isAdmitted(beaconId: beaconId, userId: actorId)) {
        throw const UnauthorizedException(
          description: 'Room access required',
        );
      }
      await _room.enforceMessageRateLimit(userId: actorId, env: env);

      final admittedIds = await _admittedIds(beaconId);
      BatonSelectionPolicy.validateCandidates(
        authorId: actorId,
        candidates: candidates,
        admittedIds: admittedIds,
      );

      final message = await _room.insertRoomMessage(
        beaconId: beaconId,
        authorId: actorId,
        body: body,
        replyToMessageId: replyTo?.id,
        semanticMarker: BeaconRoomSemanticMarker.baton,
      );
      final messageId = message.id;
      final excerpt = body.isNotEmpty ? body : replyTo!.body.trim();
      final id = RoomBaton.newId;
      final baton = await _repo.create(
        id: id,
        messageId: messageId,
        beaconId: beaconId,
        authorId: actorId,
        candidates: candidates,
      );
      for (final candidate in candidates) {
        await transaction.record(
          await _attentionIntents.batonAsked(
            beaconId: beaconId,
            messageId: messageId,
            actorUserId: actorId,
            recipientId: candidate.userId,
            excerpt: excerpt,
            sourceEventKey: 'baton_asked:$id:${candidate.userId}',
          ),
        );
      }
      return baton;
    },
  );

  /// A candidate answers. With [partnerUserId] (only with [canHelp]) they
  /// ask that admitted person to take it on together with them
  /// (`docs/plans/baton-together-plan.md` §2.4).
  Future<void> respond({
    required String actorId,
    required String batonId,
    required bool canHelp,
    String? partnerUserId,
  }) => _attention.runAction(
    actorUserId: actorId,
    action: (transaction) async {
      final baton = await _lockedBaton(batonId);

      final candidates = await _repo.getCandidates(batonId);
      final isCandidate = candidates.any((c) => c.userId == actorId);
      if (!isCandidate) {
        throw const BatonNotCandidateException();
      }
      if (baton.status != BatonStatus.collecting) {
        throw const BatonNotCollectingException();
      }
      if (!await _isAdmitted(beaconId: baton.beaconId, userId: actorId)) {
        throw const BatonNotCandidateException();
      }
      if (partnerUserId != null &&
          (!canHelp ||
              partnerUserId == baton.authorId ||
              !await _canPair(baton, actorId, partnerUserId))) {
        throw const BatonPartnerInvalidException();
      }

      final now = DateTime.timestamp();
      await _apply(
        transaction,
        baton: baton,
        actorId: actorId,
        before: candidates,
        result: BatonPairPolicy.respond(
          rows: candidates,
          actorId: actorId,
          canHelp: canHelp,
          now: now,
          partnerUserId: partnerUserId,
        ),
        now: now,
      );
    },
  );

  /// The person [inviterUserId] named answers: [accept] joins the pair,
  /// otherwise declines (or withdraws after joining).
  Future<void> partnerRespond({
    required String actorId,
    required String batonId,
    required String inviterUserId,
    required bool accept,
  }) => _attention.runAction(
    actorUserId: actorId,
    action: (transaction) async {
      final baton = await _lockedBaton(batonId);
      if (baton.status != BatonStatus.collecting) {
        throw const BatonNotCollectingException();
      }
      final candidates = await _repo.getCandidates(batonId);
      final now = DateTime.timestamp();
      final result = BatonPairPolicy.partnerRespond(
        rows: candidates,
        actorId: actorId,
        inviterId: inviterUserId,
        accept: accept,
        now: now,
      );
      if (!await _canPair(baton, inviterUserId, actorId)) {
        throw const BatonPartnerInvalidException();
      }
      await _apply(
        transaction,
        baton: baton,
        actorId: actorId,
        before: candidates,
        result: result,
        now: now,
      );
    },
  );

  Future<RoomBaton> _lockedBaton(String batonId) async {
    final found = await _repo.getById(batonId);
    if (found == null) {
      throw const BatonNotFoundException();
    }
    await _postLock.lockForPostMutation(found.beaconId);
    await _rejectIfRoomNotWritable(found.beaconId);
    return (await _repo.getById(batonId))!;
  }

  /// [partnerId] is admitted to the room like candidates are, is not
  /// [actorId], and neither has blocked the other.
  Future<bool> _canPair(
    RoomBaton baton,
    String actorId,
    String partnerId,
  ) async =>
      partnerId != actorId &&
      (await _admittedIds(baton.beaconId)).contains(partnerId) &&
      !await _repo.isPairBlocked(a: actorId, b: partnerId);

  /// Writes the rows [result] changed, records its receipts, then runs the
  /// shared all-answered rule: an unanswered candidate opens a new round;
  /// the first time everyone has answered, the author is told once.
  Future<void> _apply(
    AttentionTransaction transaction, {
    required RoomBaton baton,
    required String actorId,
    required List<RoomBatonCandidate> before,
    required BatonPairResult result,
    required DateTime now,
  }) async {
    final previous = {for (final row in before) row.userId: row};
    // The accepted-partner unique index (m0316) is checked per statement, so
    // rows that stop being an accepted pair are saved before rows that
    // become one, whatever order the candidates come in.
    final changed = [
      for (final row in result.rows)
        if (!_sameAnswer(previous[row.userId], row)) row,
    ];
    bool becomesAccepted(RoomBatonCandidate row) =>
        row.partnerResponse == BatonPartnerResponse.accepted;
    for (final row in changed.where((r) => !becomesAccepted(r))) {
      await _repo.saveCandidate(row);
    }
    for (final row in changed.where(becomesAccepted)) {
      await _repo.saveCandidate(row);
    }
    final message = await _room.getRoomMessageById(baton.messageId);
    final body = message?.body.trim() ?? '';
    if (result.receipts.isNotEmpty) {
      final replyToId = message?.replyToMessageId;
      final excerpt = body.isEmpty && replyToId != null
          ? (await _room.getRoomMessageById(replyToId))?.body.trim() ?? ''
          : body;
      for (final receipt in result.receipts) {
        await transaction.record(switch (receipt.kind) {
          BatonPairReceiptKind.partnerAsked =>
            await _attentionIntents.batonPartnerAsked(
              beaconId: baton.beaconId,
              messageId: baton.messageId,
              actorUserId: receipt.fromUserId,
              recipientId: receipt.recipientId,
              excerpt: excerpt,
              sourceEventKey: receipt.key,
            ),
          BatonPairReceiptKind.partnerAnswered =>
            await _attentionIntents.batonPartnerAnswered(
              beaconId: baton.beaconId,
              messageId: baton.messageId,
              actorUserId: receipt.fromUserId,
              recipientId: receipt.recipientId,
              excerpt: excerpt,
              sourceEventKey: receipt.key,
              accepted: receipt.accepted ?? false,
            ),
        });
      }
    }

    if (await _repo.hasUnansweredCandidate(baton.id)) {
      await _repo.clearAllAnsweredNotified(baton.id);
      return;
    }
    final notifyAuthor = await _repo.markAllAnsweredNotifiedIfUnset(
      batonId: baton.id,
      at: now,
    );
    if (!notifyAuthor) {
      return;
    }
    await transaction.record(
      await _attentionIntents.batonAllAnswered(
        beaconId: baton.beaconId,
        messageId: baton.messageId,
        actorUserId: actorId,
        recipientId: baton.authorId,
        excerpt: body,
        // An edit that adds someone, or a partner who declines, opens a new
        // answering round (the stamp is cleared), so the key is per round.
        sourceEventKey:
            'baton_all_answered:${baton.id}:${now.microsecondsSinceEpoch}',
      ),
    );
  }

  static bool _sameAnswer(RoomBatonCandidate? a, RoomBatonCandidate b) =>
      a != null &&
      a.response == b.response &&
      a.respondedAt == b.respondedAt &&
      a.partnerUserId == b.partnerUserId &&
      a.partnerResponse == b.partnerResponse &&
      a.partnerInvites == b.partnerInvites;

  Future<void> select({
    required String actorId,
    required String batonId,
    String? userId,
  }) => _attention.runAction(
    actorUserId: actorId,
    action: (transaction) async {
      final found = await _repo.getById(batonId);
      if (found == null) {
        throw const BatonNotFoundException();
      }
      await _postLock.lockForPostMutation(found.beaconId);
      await _rejectIfRoomNotWritable(found.beaconId);
      final baton = (await _repo.getById(batonId))!;
      if (baton.authorId != actorId) {
        throw const BatonNotAuthorException();
      }
      if (baton.status != BatonStatus.collecting) {
        throw const BatonNotCollectingException();
      }

      final candidates = await _repo.getCandidates(batonId);
      final admittedIds = await _admittedIds(baton.beaconId);
      final present = <RoomBatonCandidate>[];
      for (final c in candidates) {
        final partnerId = c.partnerUserId;
        if (!admittedIds.contains(c.userId) ||
            (c.partnerResponse == BatonPartnerResponse.accepted &&
                partnerId != null &&
                !await _canPair(baton, c.userId, partnerId))) {
          continue;
        }
        present.add(c);
      }
      final taker = userId == null
          ? BatonSelectionPolicy.pick(present, random: _random)
          : BatonSelectionPolicy.pickManual(present, userId);

      await _repo.select(
        batonId: batonId,
        takerId: taker.takerId,
        coTakerId: taker.coTakerId,
        mode: userId == null
            ? BatonSelectionMode.auto
            : BatonSelectionMode.manual,
        resolvedAt: DateTime.timestamp(),
      );
      await _room.insertRoomMessage(
        beaconId: baton.beaconId,
        authorId: baton.authorId,
        body: '',
        semanticMarker: BeaconRoomSemanticMarker.batonTaken,
        systemPayload: {
          'batonId': batonId,
          'sourceMessageId': baton.messageId,
          'takerUserId': taker.takerId,
          'coTakerUserId': ?taker.coTakerId,
        },
      );
      final message = await _room.getRoomMessageById(baton.messageId);
      final coTakerId = taker.coTakerId;
      for (final (recipientId, withUserId, key) in [
        (taker.takerId, coTakerId, 'baton_taken:$batonId'),
        if (coTakerId != null)
          (coTakerId, taker.takerId, 'baton_taken:$batonId:$coTakerId'),
      ]) {
        await transaction.record(
          await _attentionIntents.batonTaken(
            beaconId: baton.beaconId,
            messageId: baton.messageId,
            actorUserId: actorId,
            recipientId: recipientId,
            excerpt: message?.body.trim() ?? '',
            sourceEventKey: key,
            withUserId: withUserId,
          ),
        );
      }
    },
  );

  /// The author edits a collecting baton: the ask ([text]; may be empty
  /// only on a baton that replies to a message) and who is asked
  /// ([candidates], same rules as [create]). People kept keep their answers;
  /// people added are asked (receipt), people removed simply stop seeing the
  /// card. Rewriting the message also fans the change out to the room.
  Future<void> update({
    required String actorId,
    required String batonId,
    required String text,
    required List<({String userId, int tier})> candidates,
  }) => _attention.runAction(
    actorUserId: actorId,
    action: (transaction) async {
      final found = await _repo.getById(batonId);
      if (found == null) {
        throw const BatonNotFoundException();
      }
      await _postLock.lockForPostMutation(found.beaconId);
      final baton = (await _repo.getById(batonId))!;
      if (baton.authorId != actorId) {
        throw const BatonNotAuthorException();
      }
      if (baton.status != BatonStatus.collecting) {
        throw const BatonNotCollectingException();
      }
      await _rejectIfRoomNotWritable(baton.beaconId);
      if (!await _isAdmitted(beaconId: baton.beaconId, userId: actorId)) {
        throw const UnauthorizedException(
          description: 'Room access required',
        );
      }

      final message = await _room.getRoomMessageById(baton.messageId);
      if (message == null) {
        throw const BatonNotFoundException();
      }
      final body = text.trim();
      if (body.length > kMaxRoomMessageBodyLength) {
        throw const BeaconCreateException(description: 'Message is too long');
      }
      final replyToId = message.replyToMessageId;
      if (body.isEmpty && replyToId == null) {
        throw const BatonMessageNotEligibleException();
      }

      BatonSelectionPolicy.validateCandidates(
        authorId: actorId,
        candidates: candidates,
        admittedIds: await _admittedIds(baton.beaconId),
      );
      final current = {
        for (final c in await _repo.getCandidates(batonId)) c.userId: c.tier,
      };
      final wanted = {for (final c in candidates) c.userId: c.tier};
      final add = [
        for (final c in candidates)
          if (!current.containsKey(c.userId)) c,
      ];
      await _repo.updateCandidates(
        batonId: batonId,
        add: add,
        remove: [
          for (final userId in current.keys)
            if (!wanted.containsKey(userId)) userId,
        ],
        retier: [
          for (final c in candidates)
            if (current[c.userId] case final int tier when tier != c.tier) c,
        ],
      );
      await _room.updateMessage(
        messageId: message.id,
        newBody: body,
        mentions: const [],
        mentionSpans: const [],
      );

      if (add.isEmpty) return;
      // Per edit: someone removed earlier and added back is asked again.
      final editedAt = DateTime.timestamp().microsecondsSinceEpoch;
      final replyTo = body.isEmpty && replyToId != null
          ? await _room.getRoomMessageById(replyToId)
          : null;
      final excerpt = body.isNotEmpty ? body : replyTo?.body.trim() ?? '';
      for (final candidate in add) {
        await transaction.record(
          await _attentionIntents.batonAsked(
            beaconId: baton.beaconId,
            messageId: message.id,
            actorUserId: actorId,
            recipientId: candidate.userId,
            excerpt: excerpt,
            sourceEventKey:
                'baton_asked:$batonId:${candidate.userId}:$editedAt',
          ),
        );
      }
    },
  );

  Future<void> cancel({
    required String actorId,
    required String batonId,
  }) => _attention.runAction(
    actorUserId: actorId,
    action: (transaction) async {
      final found = await _repo.getById(batonId);
      if (found == null) {
        throw const BatonNotFoundException();
      }
      await _postLock.lockForPostMutation(found.beaconId);
      await _rejectIfRoomNotWritable(found.beaconId);
      final baton = (await _repo.getById(batonId))!;
      if (baton.authorId != actorId) {
        throw const BatonNotAuthorException();
      }
      if (baton.status != BatonStatus.collecting) {
        throw const BatonNotCollectingException();
      }
      await _repo.cancel(batonId: batonId, resolvedAt: DateTime.timestamp());
    },
  );
}
