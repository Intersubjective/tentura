import 'package:tentura_server/domain/entity/person_note.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/person_note_case.dart';

import 'custom_types.dart';
import 'gql_nodel_base.dart';
import 'input/_input_types.dart';

final class PersonNoteFields extends GqlNodeBase {
  const PersonNoteFields();

  PersonNoteCase get _case => GetIt.I<PersonNoteCase>();

  static final _userId = InputFieldString(fieldName: 'subjectUserId');
  static final _phantomId = InputFieldString(fieldName: 'subjectPhantomId');
  static final _body = InputFieldString(fieldName: 'body');
  static final _query = InputFieldString(fieldName: 'q');
  static final _subjectArgs = [_userId.fieldNullable, _phantomId.fieldNullable];

  GraphQLObjectField<dynamic, dynamic> get read => GraphQLObjectField(
    'personNote',
    GraphQLListType(gqlTypePersonNoteSection.nonNullable()),
    arguments: _subjectArgs,
    resolve: (_, args) async => [
      for (final note in await _case.read(
        getCredentials(args).sub,
        _subject(args),
      ))
        {
          'body': note.body,
          'subjectPhantomId': note.phantom?.id,
          'phantomName': note.phantom?.name,
        },
    ],
  );

  GraphQLObjectField<dynamic, dynamic> get search => GraphQLObjectField(
    'personNoteSearch',
    GraphQLListType(gqlTypePersonNoteSubject.nonNullable()).nonNullable(),
    arguments: [_query.field],
    resolve: (_, args) async => [
      for (final subject in await _case.search(
        getCredentials(args).sub,
        _query.fromArgsNonNullable(args),
      ))
        switch (subject.kind) {
          PersonNoteSubjectKind.user => {'subjectUserId': subject.id},
          PersonNoteSubjectKind.phantom => {'subjectPhantomId': subject.id},
        },
    ],
  );

  GraphQLObjectField<dynamic, dynamic> get upsert => GraphQLObjectField(
    'personNoteUpsert',
    graphQLBoolean.nonNullable(),
    arguments: [..._subjectArgs, _body.field],
    resolve: (_, args) => _case.upsert(
      getCredentials(args).sub,
      _subject(args),
      _body.fromArgsNonNullable(args),
    ),
  );

  GraphQLObjectField<dynamic, dynamic> get delete => GraphQLObjectField(
    'personNoteDelete',
    graphQLBoolean.nonNullable(),
    arguments: _subjectArgs,
    resolve: (_, args) =>
        _case.delete(getCredentials(args).sub, _subject(args)),
  );

  static PersonNoteSubject _subject(Map<String, dynamic> args) {
    final subject = switch ((
      _userId.fromArgs(args),
      _phantomId.fromArgs(args),
    )) {
      (final String id, null) => PersonNoteSubject.user(id),
      (null, final String id) => PersonNoteSubject.phantom(id),
      _ => throw const IdWrongException(
        description: 'Choose one person for the note',
      ),
    };
    if (subject.id.isEmpty || subject.id.contains('\u0000')) {
      throw const IdWrongException(description: 'Invalid person for the note');
    }
    return subject;
  }
}
