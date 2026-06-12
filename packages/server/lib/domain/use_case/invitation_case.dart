import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/entity/invitation_entity.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/invite_preview_result.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';

import '../exception.dart';
import '_use_case_base.dart';
import 'contact_case.dart';

@Injectable(order: 2)
final class InvitationCase extends UseCaseBase {
  InvitationCase(
    this._invitationRepository,
    this._userRepository,
    this._beaconRepository,
    this._friendshipLookup,
    this._contactRepository, {
    required super.env,
    required super.logger,
  });

  final InvitationRepositoryPort _invitationRepository;

  final UserRepositoryPort _userRepository;

  final BeaconRepositoryPort _beaconRepository;

  final VoteUserFriendshipLookup _friendshipLookup;

  final UserContactRepositoryPort _contactRepository;

  Future<InvitationEntity> create({
    required String userId,
    required String addresseeName,
    String? beaconId,
  }) async => _invitationRepository.create(
    issuerId: userId,
    addresseeName: ContactCase.normalizeName(addresseeName),
    beaconId: beaconId,
  );

  /// Renames the addressee of the caller's own, still unconsumed invite.
  Future<InvitationEntity> update({
    required String invitationId,
    required String userId,
    required String addresseeName,
  }) async => _invitationRepository.updateAddresseeName(
    invitationId: invitationId,
    userId: userId,
    addresseeName: ContactCase.normalizeName(addresseeName),
  );

  Future<InvitationEntity> fetchById({
    required String invitationId,
  }) async {
    final invitation = await _invitationRepository.getById(
      invitationId: invitationId,
    );
    if (invitation == null || invitation.isAccepted || invitation.isExpired) {
      throw IdNotFoundException(id: invitationId);
    }
    return invitation;
  }

  /// Read-only preview of what [code] means for [callerUserId] (null =
  /// anonymous). Unlike [fetchById] this never throws on a consumed/expired
  /// code — it reports the state so the landing can render before any UI.
  Future<InvitePreviewResult> preview({
    required String code,
    String? callerUserId,
  }) async {
    final invitation = await _invitationRepository.getById(invitationId: code);
    if (invitation == null) {
      return const InvitePreviewResult(
        codeStatus: InviteCodeStatus.invalid,
        callerStatus: InviteCallerStatus.anonymous,
      );
    }

    final codeStatus = invitation.isAccepted
        ? InviteCodeStatus.consumed
        : invitation.isExpired
        ? InviteCodeStatus.expired
        : InviteCodeStatus.available;

    final InviteCallerStatus callerStatus;
    if (callerUserId == null) {
      callerStatus = InviteCallerStatus.anonymous;
    } else if (callerUserId == invitation.issuer.id) {
      callerStatus = InviteCallerStatus.isInviter;
    } else if (await _friendshipLookup.isReciprocalSubscribe(
      viewerId: callerUserId,
      peerId: invitation.issuer.id,
    )) {
      callerStatus = InviteCallerStatus.alreadyFriends;
    } else {
      callerStatus = InviteCallerStatus.existingUser;
    }

    BeaconEntity? beacon;
    if (invitation.beaconId != null) {
      try {
        beacon = await _beaconRepository.getBeaconById(
          beaconId: invitation.beaconId!,
        );
      } catch (_) {
        beacon = null; // beacon removed since the invite was minted
      }
    }

    // Subjective profiles: a signed-in caller sees the inviter under their
    // own contact name. Resolved server-side because the static landing
    // cannot apply the client-side overlay. The invite's addressee_name must
    // never reach this result — it is the issuer's private data.
    var inviter = invitation.issuer;
    if (callerUserId != null && callerUserId != inviter.id) {
      final contactName = await _contactRepository.getName(
        viewerId: callerUserId,
        subjectId: inviter.id,
      );
      if (contactName != null) {
        inviter = inviter.copyWith(displayName: contactName);
      }
    }

    return InvitePreviewResult(
      codeStatus: codeStatus,
      callerStatus: callerStatus,
      inviter: inviter,
      beacon: beacon,
    );
  }

  Future<bool> accept({
    required String invitationId,
    required String userId,
  }) => _userRepository.bindMutual(
    invitationId: invitationId,
    userId: userId,
  );

  /// Befriend the issuer of [code] as an already-authenticated [userId] (the
  /// landing `accept-as-existing` endpoint). Single-use semantics — `bindMutual`
  /// consumes (deletes) the invite row. Behaviour:
  /// - self-invite -> rejected (`InvitationWrongException`);
  /// - caller already connected to the issuer (invite still present) -> ok,
  ///   no re-bind;
  /// - invite missing / consumed / expired for a non-friend -> `IdNotFoundException`
  ///   (404). Note this includes a *repeat* of a befriend that already
  ///   succeeded: `bindMutual` deleted the row, so the issuer is unknown and we
  ///   cannot re-check friendship — the caller treats 404 as "nothing left to
  ///   do". True idempotent re-submit needs the deferred non-deleting slot model;
  /// - otherwise -> befriend, forwarding the beacon when present.
  Future<bool> acceptAsExisting({
    required String code,
    required String userId,
  }) async {
    final invitation = await _invitationRepository.getById(invitationId: code);
    if (invitation == null) {
      throw IdNotFoundException(id: code);
    }
    if (invitation.issuer.id == userId) {
      throw const InvitationWrongException(
        description: 'Cannot accept your own invite',
      );
    }
    if (await _friendshipLookup.isReciprocalSubscribe(
      viewerId: userId,
      peerId: invitation.issuer.id,
    )) {
      return true;
    }
    if (invitation.isAccepted || invitation.isExpired) {
      throw IdNotFoundException(id: code);
    }
    return accept(invitationId: code, userId: userId);
  }

  Future<bool> delete({
    required String invitationId,
    required String userId,
  }) => _invitationRepository.deleteById(
    invitationId: invitationId,
    userId: userId,
  );
}
