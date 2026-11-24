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

  static const _activeCap = 200;

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
      if (await _repository.countActive(scope, ownerId) >= _activeCap) {
        throw const PhantomCapReachedException();
      }
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

  Future<bool> delete({required String ownerId, required String id}) =>
      _ownerGraph.run({ownerId}, ownerId, (scope) async {
        if (!await _repository.delete(scope, ownerId: ownerId, id: id)) {
          throw IdNotFoundException(id: id);
        }
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
