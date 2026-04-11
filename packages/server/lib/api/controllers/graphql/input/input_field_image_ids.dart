part of '_input_types.dart';

abstract class InputFieldImageIds {
  static final field = GraphQLFieldInput(
    _fieldKey,
    GraphQLListType(graphQLString.nonNullable()),
  );

  static List<String> fromArgs(Map<String, dynamic> args) =>
      List<String>.from(args[_fieldKey]! as List);

  static const _fieldKey = 'imageIds';
}
