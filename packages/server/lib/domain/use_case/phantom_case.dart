import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/port/owner_graph_transaction_port.dart';
import 'package:tentura_server/domain/port/phantom_repository_port.dart';
import 'package:tentura_server/utils/id.dart';

import 'contact_case.dart';

@lazySingleton
final class PhantomCase {
  const PhantomCase(this._ownerGraph, this._repository, this._anchors);

  final OwnerGraphTransactionPort _ownerGraph;
  final PhantomRepositoryPort _repository;
  final ScopedConstellationAnchorRepositoryPort _anchors;

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
  }) => _withInviteLocks(ownerId, id, (scope) async {
    final inviteId = await _repository.saveInvite(
      scope,
      ownerId: ownerId,
      id: id,
      rotate: rotate,
    );
    if (inviteId == null) throw IdNotFoundException(id: id);
    return inviteId;
  });

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
    Future<T> Function(OwnerGraphScope scope) action,
  ) => _ownerGraph.run({ownerId}, ownerId, (scope) async {
    final name = await _repository.lockInvitesAndFindJoiningName(
      scope,
      ownerId: ownerId,
      id: id,
    );
    if (name != null) throw PhantomJoiningException(name);
    return action(scope);
  });

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
