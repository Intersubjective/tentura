import 'package:injectable/injectable.dart';

import '../entity/person_note.dart';
import '../exception.dart';
import '../port/owner_graph_transaction_port.dart';
import '../port/person_note_repository_port.dart';

@lazySingleton
final class PersonNoteCase {
  const PersonNoteCase(this._ownerGraph, this._repository);

  static const _maxBodyLength = 4000;
  final OwnerGraphTransactionPort _ownerGraph;
  final PersonNoteRepositoryPort _repository;

  Future<List<PersonNoteSection>> read(
    String ownerId,
    PersonNoteSubject subject,
  ) => _repository.read(ownerId, subject);

  Future<List<PersonNoteSubject>> search(String ownerId, String query) async {
    if (query.trim().isEmpty) return const [];
    if (query.contains('\u0000')) {
      throw const IdWrongException(
        description: 'The search query contains an invalid character',
      );
    }
    return _repository.search(ownerId, query);
  }

  Future<bool> upsert(String ownerId, PersonNoteSubject subject, String body) {
    if (subject.kind == PersonNoteSubjectKind.user && subject.id == ownerId) {
      throw const IdWrongException(
        description: 'Cannot add a note about yourself',
      );
    }
    if (body.runes.length > _maxBodyLength) {
      throw const PayloadTooLargeException(
        description: 'A note must be at most $_maxBodyLength characters long',
      );
    }
    if (body.contains('\u0000')) {
      throw const IdWrongException(
        description: 'The note contains an invalid character',
      );
    }
    return _ownerGraph.run(
      {ownerId},
      ownerId,
      (scope) => _repository.upsert(scope, ownerId, subject, body),
    );
  }

  Future<bool> delete(String ownerId, PersonNoteSubject subject) =>
      _ownerGraph.run(
        {ownerId},
        ownerId,
        (scope) => _repository.delete(scope, ownerId, subject),
      );
}
