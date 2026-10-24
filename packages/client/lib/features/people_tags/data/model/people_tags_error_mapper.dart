import '../../domain/people_tags_exception.dart';

/// Throws the matching [PeopleTagsException] for a recognized people-tags
/// GraphQL error [code]. Returns normally for any other code so the caller can
/// fall through to generic mapping.
void throwIfPeopleTagsError(int? code) {
  switch (code) {
    case PeopleTagsNameTakenException.codeNumber:
      throw const PeopleTagsNameTakenException();
  }
}
