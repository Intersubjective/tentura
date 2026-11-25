import '../entity/person_note.dart';
import 'owner_graph_transaction_port.dart';

abstract interface class PersonNoteRepositoryPort {
  Future<List<PersonNoteSection>> read(
    String ownerId,
    PersonNoteSubject subject,
  );

  Future<bool> upsert(
    OwnerGraphScope scope,
    String ownerId,
    PersonNoteSubject subject,
    String body,
  );

  Future<bool> delete(
    OwnerGraphScope scope,
    String ownerId,
    PersonNoteSubject subject,
  );
}
