import 'package:tentura_server/domain/entity/person_subject.dart';
import 'package:tentura_server/domain/exception.dart';

import '_input_types.dart';

abstract final class PersonSubjectInput {
  static final _userId = InputFieldString(fieldName: 'subjectUserId');
  static final _phantomId = InputFieldString(fieldName: 'subjectPhantomId');

  static final arguments = [_userId.fieldNullable, _phantomId.fieldNullable];

  static PersonSubject fromArgs(
    Map<String, dynamic> args, {
    required String purpose,
  }) {
    final subject = switch ((
      _userId.fromArgs(args),
      _phantomId.fromArgs(args),
    )) {
      (final String id, null) => PersonSubject.user(id),
      (null, final String id) => PersonSubject.phantom(id),
      _ => throw IdWrongException(
        description: 'Choose one person for $purpose',
      ),
    };
    if (subject.id.isEmpty || subject.id.contains('\u0000')) {
      throw IdWrongException(description: 'Invalid person for $purpose');
    }
    return subject;
  }
}
