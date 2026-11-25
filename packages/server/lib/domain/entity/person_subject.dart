enum PersonSubjectKind { user, phantom }

final class PersonSubject {
  const PersonSubject.user(this.id) : kind = PersonSubjectKind.user;
  const PersonSubject.phantom(this.id) : kind = PersonSubjectKind.phantom;

  final String id;
  final PersonSubjectKind kind;

  String? get userId => kind == PersonSubjectKind.user ? id : null;
  String? get phantomId => kind == PersonSubjectKind.phantom ? id : null;
}
