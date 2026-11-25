import 'package:tentura_server/domain/entity/person_subject.dart';
import 'package:tentura_server/domain/use_case/person_note_case.dart';

import 'custom_types.dart';
import 'gql_nodel_base.dart';
import 'input/_input_types.dart';
import 'input/person_subject_input.dart';

final class PersonNoteFields extends GqlNodeBase {
  const PersonNoteFields();

  PersonNoteCase get _case => GetIt.I<PersonNoteCase>();

  static final _body = InputFieldString(fieldName: 'body');
  static final _query = InputFieldString(fieldName: 'q');

  GraphQLObjectField<dynamic, dynamic> get read => GraphQLObjectField(
    'personNote',
    GraphQLListType(gqlTypePersonNoteSection.nonNullable()),
    arguments: PersonSubjectInput.arguments,
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
          PersonSubjectKind.user => {'subjectUserId': subject.id},
          PersonSubjectKind.phantom => {'subjectPhantomId': subject.id},
        },
    ],
  );

  GraphQLObjectField<dynamic, dynamic> get upsert => GraphQLObjectField(
    'personNoteUpsert',
    graphQLBoolean.nonNullable(),
    arguments: [...PersonSubjectInput.arguments, _body.field],
    resolve: (_, args) => _case.upsert(
      getCredentials(args).sub,
      _subject(args),
      _body.fromArgsNonNullable(args),
    ),
  );

  GraphQLObjectField<dynamic, dynamic> get delete => GraphQLObjectField(
    'personNoteDelete',
    graphQLBoolean.nonNullable(),
    arguments: PersonSubjectInput.arguments,
    resolve: (_, args) =>
        _case.delete(getCredentials(args).sub, _subject(args)),
  );

  static PersonSubject _subject(Map<String, dynamic> args) =>
      PersonSubjectInput.fromArgs(args, purpose: 'the note');
}
