import 'dart:math' show min;

import 'package:injectable/injectable.dart';
import 'package:tentura_root/consts.dart' show kTitleMaxLength, kTitleMinLength;
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/entity/phantom_pending_forward.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/port/owner_graph_transaction_port.dart';
import 'package:tentura_server/domain/port/people_tags_repository_port.dart';
import 'package:tentura_server/domain/port/phantom_pending_forward_repository_port.dart';
import 'package:tentura_server/domain/port/phantom_repository_port.dart';
import 'package:tentura_server/domain/port/post_lock_port.dart';
import 'package:tentura_server/domain/util/email_auth_util.dart';
import 'package:tentura_server/utils/id.dart';

import 'contact_case.dart';
import 'contact_check_case.dart';
import 'forward_case.dart';

typedef PhantomImportContact = ({String name, String? email, String? phone});
typedef PhantomImportResult = ({
  List<({int rowIndex, String id, bool? alreadyOnTentura})> created,
  List<({int rowIndex, PhantomImportRefusal reason})> refused,
});

enum PhantomImportRefusal { shortName, capReached }

typedef _ImportRow = ({
  int index,
  String name,
  ({String normalized, bool keep})? email,
  String? keptPhone,
});

@lazySingleton
final class PhantomCase {
  const PhantomCase(
    this._ownerGraph,
    this._repository,
    this._anchors,
    this._postLock,
    this._forwardCase,
    this._pendingForwards,
    this._peopleTags,
    this._contactChecks,
  );

  final OwnerGraphTransactionPort _ownerGraph;
  final PhantomRepositoryPort _repository;
  final ScopedConstellationAnchorRepositoryPort _anchors;
  final PostLockPort _postLock;
  final ForwardCase _forwardCase;
  final PhantomPendingForwardRepositoryPort _pendingForwards;
  final ScopedPeopleTagsRepositoryPort _peopleTags;
  final ContactCheckCase _contactChecks;

  Future<String> create({
    required String ownerId,
    required String name,
    String? emoji,
    ConstellationAnchorPosition? position,
  }) {
    final displayName = ContactCase.normalizeName(name);
    _validateEmoji(emoji);
    final id = generateId('PH');
    return _ownerGraph.run({ownerId}, ownerId, (scope) async {
      await _repository.requireActiveCapacity(scope, ownerId);
      await _repository.insert(
        scope,
        ownerId: ownerId,
        id: id,
        name: displayName,
        emoji: emoji,
      );
      if (position != null) {
        await _anchors.upsertScoped(
          scope: scope,
          viewerId: ownerId,
          target: ConstellationAnchorPhantomTarget(id),
          position: position,
          additionalWatermarkTargets: const {},
        );
      }
      return id;
    });
  }

  /// Reusing a client operation ID with the same rows resumes after the last
  /// committed chunk. A call without an ID starts a new import.
  Future<PhantomImportResult> createBatch({
    required String ownerId,
    required List<PhantomImportContact> contacts,
    required bool keepContacts,
    required String? clientOpId,
  }) async {
    const chunkSize = 20;
    final rows = <_ImportRow>[];
    final refused = <({int rowIndex, PhantomImportRefusal reason})>[];
    for (final (index, contact) in contacts.indexed) {
      final name = String.fromCharCodes(
        contact.name.trim().runes.take(kTitleMaxLength),
      );
      if (name.runes.length < kTitleMinLength) {
        refused.add((rowIndex: index, reason: PhantomImportRefusal.shortName));
        continue;
      }
      final email = normalizeAuthEmail(contact.email ?? '');
      final phone = contact.phone;
      rows.add((
        index: index,
        name: name,
        email: email.isEmpty ? null : (normalized: email, keep: keepContacts),
        keptPhone: keepContacts && phone != null && phone.trim().isNotEmpty
            ? phone
            : null,
      ));
    }

    final created = <({int rowIndex, String id, bool? alreadyOnTentura})>[];
    for (var offset = 0; offset < rows.length; offset += chunkSize) {
      final chunk = rows.sublist(offset, min(offset + chunkSize, rows.length));
      final imported = await _importChunk(
        ownerId,
        chunk,
        clientOpId: clientOpId,
        chunkIndex: offset ~/ chunkSize,
      );
      created.addAll([
        for (final (index, row) in imported.indexed)
          (
            rowIndex: chunk[index].index,
            id: row.id,
            alreadyOnTentura: row.alreadyOnTentura,
          ),
      ]);
      if (imported.length < chunk.length) {
        refused.addAll([
          for (final row in rows.skip(offset + imported.length))
            (rowIndex: row.index, reason: PhantomImportRefusal.capReached),
        ]);
        break;
      }
    }
    refused.sort((a, b) => a.rowIndex.compareTo(b.rowIndex));
    return (created: created, refused: refused);
  }

  Future<List<PhantomImportedContact>> _importChunk(
    String ownerId,
    List<_ImportRow> rows, {
    required String? clientOpId,
    required int chunkIndex,
  }) async {
    final result = await _ownerGraph.run({ownerId}, ownerId, (scope) async {
      if (clientOpId != null) {
        final prior = await _repository.findImportedChunk(
          scope,
          ownerId,
          clientOpId,
          chunkIndex,
        );
        if (prior != null) {
          if (prior.length > rows.length) {
            throw const IdWrongException(
              description:
                  'Reuse the import operation ID only with the same rows.',
            );
          }
          return (created: prior, reachedDailyLimit: false);
        }
      }

      final remaining = await _repository.remainingActiveCapacity(
        scope,
        ownerId,
      );
      final created = <PhantomImportedContact>[];
      var reachedDailyLimit = false;
      for (final row in rows.take(remaining)) {
        final id = generateId('PH');
        await _repository.insert(
          scope,
          ownerId: ownerId,
          id: id,
          name: row.name,
          emoji: null,
        );
        await _repository.saveImportedContactPoints(
          scope,
          ownerId: ownerId,
          id: id,
          email: row.email,
          keptPhone: row.keptPhone,
        );
        final email = row.email;
        final check = email == null
            ? null
            : await _contactChecks.checkNormalizedEmail(
                ownerId,
                email.normalized,
              );
        if (check?.reachedDailyLimit == true) reachedDailyLimit = true;
        created.add((id: id, alreadyOnTentura: check?.alreadyOnTentura));
      }
      if (created.isNotEmpty) {
        await _peopleTags.addImportedPhantoms(
          scope,
          ownerId: ownerId,
          phantomIds: [for (final row in created) row.id],
        );
      }
      if (clientOpId != null) {
        await _repository.recordImportedChunk(
          scope,
          ownerId,
          clientOpId,
          chunkIndex,
          created,
        );
      }
      return (created: created, reachedDailyLimit: reachedDailyLimit);
    });
    if (result.reachedDailyLimit) _contactChecks.logDailyLimit(ownerId);
    return result.created;
  }

  Future<bool> update({
    required String ownerId,
    required String id,
    required String name,
    String? emoji,
  }) {
    final displayName = ContactCase.normalizeName(name);
    _validateEmoji(emoji);
    return _ownerGraph.run({ownerId}, ownerId, (scope) async {
      final found = await _repository.update(
        scope,
        ownerId: ownerId,
        id: id,
        name: displayName,
        emoji: emoji,
      );
      if (!found) throw IdNotFoundException(id: id);
      return true;
    });
  }

  Future<String> saveInvite({
    required String ownerId,
    required String id,
    required bool rotate,
  }) => _withInviteLocks(
    ownerId,
    id,
    (scope) => _saveInvite(scope, ownerId: ownerId, id: id, rotate: rotate),
  );

  Future<String> _saveInvite(
    OwnerGraphScope scope, {
    required String ownerId,
    required String id,
    required bool rotate,
  }) async {
    final inviteId = await _repository.saveInvite(
      scope,
      ownerId: ownerId,
      id: id,
      rotate: rotate,
    );
    if (inviteId == null) throw IdNotFoundException(id: id);
    return inviteId;
  }

  Future<
    List<
      ({
        String id,
        String phantomId,
        String senderId,
        String beaconId,
        String displayName,
        PhantomPendingForwardState state,
      })
    >
  >
  pendingForRequest({
    required String senderId,
    required String beaconId,
  }) async {
    final rows = await _pendingForwards.listForRequest(
      senderId: senderId,
      beaconId: beaconId,
    );
    if (rows.isEmpty) return const [];
    final stillForwardable =
        rows.any((row) => row.state == PhantomPendingForwardState.pending) &&
        await _forwardCase.canForwardRequestNow(
          beaconId: beaconId,
          senderId: senderId,
        );
    return [
      for (final row in rows)
        (
          id: row.id,
          phantomId: row.phantomId,
          senderId: senderId,
          beaconId: beaconId,
          displayName: row.displayName,
          state: stillForwardable
              ? row.state
              : PhantomPendingForwardState.lapsed,
        ),
    ];
  }

  /// Records a pending Request forward and returns the person's invite code.
  Future<String> forwardRequest({
    required String ownerId,
    required String phantomId,
    required String beaconId,
    required String note,
  }) {
    final id = generateId('PF');
    return _withInviteLocks(
      ownerId,
      phantomId,
      (scope) async {
        final parentEdgeId = await _forwardCase.checkPhantomForward(
          beaconId: beaconId,
          senderId: ownerId,
        );
        final code = await _saveInvite(
          scope,
          ownerId: ownerId,
          id: phantomId,
          rotate: false,
        );
        await _pendingForwards.record(
          scope,
          id: id,
          phantomId: phantomId,
          senderId: ownerId,
          beaconId: beaconId,
          parentForwardEdgeId: parentEdgeId,
          note: note,
        );
        return code;
      },
      forwardBeaconId: beaconId,
    );
  }

  Future<bool> delete({required String ownerId, required String id}) =>
      _withInviteLocks(ownerId, id, (scope) async {
        if (!await _repository.delete(scope, ownerId: ownerId, id: id)) {
          throw IdNotFoundException(id: id);
        }
        return true;
      });

  Future<T> _withInviteLocks<T>(
    String ownerId,
    String id,
    Future<T> Function(OwnerGraphScope scope) action, {
    String? forwardBeaconId,
  }) async {
    // A worker can still be linking this entry while its last committed
    // state is queued. Reject the action before waiting on that worker.
    final joining = await _repository.findJoiningName(
      ownerId: ownerId,
      id: id,
    );
    if (joining != null) throw PhantomJoiningException(joining);

    return _ownerGraph.run({ownerId}, ownerId, (scope) async {
      if (forwardBeaconId != null) {
        await _postLock.lockForPostMutation(forwardBeaconId);
      }
      final name = await _repository.lockInvitesAndFindJoiningName(
        scope,
        ownerId: ownerId,
        id: id,
      );
      if (name != null) throw PhantomJoiningException(name);
      return action(scope);
    });
  }

  Future<bool> dismissLinkHint({
    required String ownerId,
    required String phantomId,
    required String userId,
  }) => _ownerGraph.run({ownerId}, ownerId, (scope) async {
    final found = await _repository.dismissLinkHint(
      scope,
      ownerId: ownerId,
      phantomId: phantomId,
      userId: userId,
    );
    if (!found) throw IdNotFoundException(id: phantomId);
    return true;
  });

  static void _validateEmoji(String? emoji) {
    if (emoji != null && emoji.runes.length > 8) {
      throw const IdWrongException(
        description: 'Emoji must be at most 8 characters long',
      );
    }
  }
}
