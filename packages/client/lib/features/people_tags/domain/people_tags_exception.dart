import 'package:tentura_root/domain/entity/localizable.dart';

/// Typed people-tags failures mapped from GraphQL `extensions.code`
/// (code space 1900).
sealed class PeopleTagsException extends LocalizableException {
  const PeopleTagsException();
}

/// The viewer already has a tag with this name.
final class PeopleTagsNameTakenException extends PeopleTagsException {
  const PeopleTagsNameTakenException();

  static const codeNumber = 1900;

  @override
  String get toEn => 'You already have this tag';

  @override
  String get toRu => 'Такой тег уже есть';
}
