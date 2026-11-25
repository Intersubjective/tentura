enum PersonNoteSubjectKind { user, phantom }

final class PersonNoteSubject {
  const PersonNoteSubject.user(this.id) : kind = PersonNoteSubjectKind.user;
  const PersonNoteSubject.phantom(this.id)
    : kind = PersonNoteSubjectKind.phantom;

  final String id;
  final PersonNoteSubjectKind kind;
}

typedef PersonNoteSection = ({
  String body,
  ({String id, String name})? phantom,
});
