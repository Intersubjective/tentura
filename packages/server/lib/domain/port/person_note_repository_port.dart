import '../entity/person_note.dart';
import '../entity/person_subject.dart';
import 'owner_graph_transaction_port.dart';

abstract interface class PersonNoteRepositoryPort {
  Future<List<PersonNoteSection>> read(
    String ownerId,
    PersonSubject subject,
  );

  Future<List<PersonSubject>> search(String ownerId, String query);

  Future<bool> upsert(
    OwnerGraphScope scope,
    String ownerId,
    PersonSubject subject,
    String body,
  );

  Future<bool> delete(
    OwnerGraphScope scope,
    String ownerId,
    PersonSubject subject,
  );
}
