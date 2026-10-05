import 'dart:math';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/room_baton.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/baton_selection_policy.dart';
import 'package:tentura_server/domain/policy/beacon_room_lifecycle_write_policy.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
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

  Future<void> _rejectIfRoomNotWritable(String beaconId) async {
    final status = await _hierarchyRepository.loadBeaconStatus(beaconId);
    if (status != null &&
        BeaconRoomLifecycleWritePolicy.blocksOrdinaryUserWrites(status)) {
      throw const BeaconCreateException(
        description: 'Discussion is read-only for this request',
      );
    }
  }

  Future<Set<String>> _admittedIds(String beaconId) async {
    final admitted = await _room.listAdmittedMentionParticipants(beaconId);
    return {for (final p in admitted) p.userId};
  }

  /// Mirrors `BeaconRoomCase._canUseRoom`: the author and stewards always
  /// have room access regardless of their `beacon_participant` row, which an
  /// admitted-only check (the baton's actual candidate-eligibility rule)
  /// would wrongly reject the author/steward for.
  Future<bool> _isAdmitted({
    required String beaconId,
    required String userId,
  }) async {
    if (await _room.isBeaconAuthor(beaconId: beaconId, userId: userId)) {
      return true;
    }
    if (await _room.isBeaconSteward(beaconId: beaconId, userId: userId)) {
      return true;
    }
    final participant = await _room.findParticipant(
      beaconId: beaconId,
      userId: userId,
    );
    return participant?.roomAccess == RoomAccessBits.admitted;
  }

  Future<RoomBaton> create({
    required String actorId,
    required String messageId,
    required List<({String userId, int tier})> candidates,
  }) => _attention.runAction(
    actorUserId: actorId,
    action: (transaction) async {
      final message = await _room.getRoomMessageById(messageId);
      if (message == null ||
          message.threadItemId != null ||
          message.authorId != actorId ||
          message.semanticMarker != null ||
          message.systemMessageKind != null ||
          message.linkedPollingId != null) {
        throw const BatonMessageNotEligibleException();
      }
      final beaconId = message.beaconId;
      await _postLock.lockForPostMutation(beaconId);

      await _rejectIfRoomNotWritable(beaconId);
      if (!await _isAdmitted(beaconId: beaconId, userId: actorId)) {
        throw const UnauthorizedException(
          description: 'Room access required',
        );
      }

      final admittedIds = await _admittedIds(beaconId);
      BatonSelectionPolicy.validateCandidates(
        authorId: actorId,
        candidates: candidates,
        admittedIds: admittedIds,
      );

      if (await _repo.getLiveBatonForMessage(messageId) != null) {
        throw const BatonAlreadyActiveException();
      }

      final excerpt = message.body.trim();
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

  Future<void> respond({
    required String actorId,
    required String batonId,
    required bool canHelp,
  }) => _attention.runAction(
    actorUserId: actorId,
    action: (transaction) async {
      final baton = await _repo.getById(batonId);
      if (baton == null) {
        throw const BatonNotFoundException();
      }
      await _postLock.lockForPostMutation(baton.beaconId);

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

      final respondedAt = DateTime.timestamp();
      await _repo.updateCandidateResponse(
        batonId: batonId,
        userId: actorId,
        response: canHelp ? BatonResponse.canHelp : BatonResponse.cantHelp,
        respondedAt: respondedAt,
      );
      if (await _repo.hasWaitingCandidate(batonId)) {
        return;
      }
      final notifyAuthor = await _repo.markAllAnsweredNotifiedIfUnset(
        batonId: batonId,
        at: respondedAt,
      );
      if (!notifyAuthor) {
        return;
      }
      final message = await _room.getRoomMessageById(baton.messageId);
      await transaction.record(
        await _attentionIntents.batonAllAnswered(
          beaconId: baton.beaconId,
          messageId: baton.messageId,
          actorUserId: actorId,
          recipientId: baton.authorId,
          excerpt: message?.body.trim() ?? '',
          sourceEventKey: 'baton_all_answered:$batonId',
        ),
      );
    },
  );

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
      final baton = (await _repo.getById(batonId))!;
      if (baton.authorId != actorId) {
        throw const BatonNotAuthorException();
      }
      if (baton.status != BatonStatus.collecting) {
        throw const BatonNotCollectingException();
      }

      final candidates = await _repo.getCandidates(batonId);
      final admittedIds = await _admittedIds(baton.beaconId);
      final present = candidates
          .where((c) => admittedIds.contains(c.userId))
          .toList(growable: false);
      final taker = userId == null
          ? BatonSelectionPolicy.pick(present, random: _random)
          : BatonSelectionPolicy.pickManual(present, userId);

      await _repo.select(
        batonId: batonId,
        takerId: taker.userId,
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
          'takerUserId': taker.userId,
        },
      );
      final message = await _room.getRoomMessageById(baton.messageId);
      await transaction.record(
        await _attentionIntents.batonTaken(
          beaconId: baton.beaconId,
          messageId: baton.messageId,
          actorUserId: actorId,
          recipientId: taker.userId,
          excerpt: message?.body.trim() ?? '',
          sourceEventKey: 'baton_taken:$batonId',
        ),
      );
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
