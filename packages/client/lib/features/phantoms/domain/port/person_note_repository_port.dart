import '../entity/person_note.dart';

abstract interface class PersonNoteRepositoryPort {
  Future<List<PersonNoteSection>> read(PersonNoteSubject subject);

  Future<void> save(PersonNoteSubject subject, String body);

  Future<List<PersonNoteSubject>> search(String query);
}
