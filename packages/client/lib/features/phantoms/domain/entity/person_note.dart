const kPersonNoteMaxLength = 4000;

sealed class PersonNoteSubject {
  const PersonNoteSubject(this.id);

  final String id;
}

final class UserNoteSubject extends PersonNoteSubject {
  const UserNoteSubject(super.id);
}

final class PhantomNoteSubject extends PersonNoteSubject {
  const PhantomNoteSubject(super.id);
}

/// A direct note uses the panel's subject. Merged sections retain the
/// original subject so editing one writes back to its own row.
typedef PersonNoteSection = ({
  String body,
  ({PhantomNoteSubject subject, String name})? mergedFrom,
});
