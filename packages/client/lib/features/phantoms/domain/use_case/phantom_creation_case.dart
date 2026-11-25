import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../port/phantom_repository_port.dart';

/// One add-person sheet owns this case and serializes its actions. Keep the
/// acknowledged id so retrying tags, copying, or sharing reuses the same entry.
final class PhantomCreationCase {
  PhantomCreationCase(this._phantoms, this._peopleTags);

  final PhantomRepositoryPort _phantoms;
  final PeopleTagsCase _peopleTags;

  Future<String>? _createRequest;
  String? _createdId;

  bool get hasStarted => _createRequest != null;
  bool get hasCreatedPerson => _createdId != null;

  List<PersonTag> get tags => _peopleTags.tags;
  Future<void> loadTags() => _peopleTags.ensureLoaded();

  Future<String> save({
    required String name,
    required ConstellationAnchorPosition position,
    required Set<String> tagIds,
    String? emoji,
  }) async {
    // A lost create response can follow a committed write. The operation
    // has no replay key, so this sheet sends it only once.
    final id = _createdId ??= await (_createRequest ??= _phantoms.create(
      name: name,
      emoji: emoji,
      position: position,
    ));
    if (tagIds.isNotEmpty) {
      await _peopleTags.applyMembership([
        for (final tagId in tagIds)
          PersonTagMemberOp(tagId: tagId, personId: id, add: true),
      ]);
    }
    return id;
  }

  Future<String> ensureInvite(String id) => _phantoms.inviteEnsure(id: id);
}
