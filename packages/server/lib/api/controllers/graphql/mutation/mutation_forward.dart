import 'dart:convert' show json;

import 'package:tentura_server/domain/use_case/forward_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationForward extends GqlNodeBase {
  MutationForward({ForwardCase? forwardCase})
    : _forwardCase = forwardCase ?? GetIt.I<ForwardCase>();

  final ForwardCase _forwardCase;

  final _note = InputFieldString(fieldName: 'note');
  final _context = InputFieldString(fieldName: 'context');
  final _parentEdgeId = InputFieldString(fieldName: 'parentEdgeId');
  final _perRecipientNotes = InputFieldString(fieldName: 'perRecipientNotes');

  static final _reasons = GraphQLFieldInput(
    'reasons',
    GraphQLListType(graphQLString.nonNullable()),
    defaultsToNull: true,
  );

  static List<String>? _reasonsFromArgs(Map<String, dynamic> args) {
    final raw = args['reasons'];
    if (raw == null) return null;
    return List<String>.from(raw as List);
  }

  List<GraphQLObjectField<dynamic, dynamic>> get all => [forward];

  GraphQLObjectField<dynamic, dynamic> get forward => GraphQLObjectField(
    'beaconForward',
    graphQLString.nonNullable(),
    arguments: [
      InputFieldId.field,
      InputFieldRecipientIds.field,
      _note.fieldNullable,
      _perRecipientNotes.fieldNullable,
      _context.fieldNullable,
      _parentEdgeId.fieldNullable,
      _reasons,
      InputFieldForwardRecipientReasons.field,
    ],
    resolve: (_, args) {
      final recipientReasonsList =
          InputFieldForwardRecipientReasons.fromArgs(args);
      final perRecipientReasonSlugs =
          recipientReasonsList == null
              ? null
              : {
                  for (final r in recipientReasonsList)
                    r.recipientId: r.slugs,
                };
      return _forwardCase.forward(
        senderId: getCredentials(args).sub,
        beaconId: InputFieldId.fromArgsNonNullable(args),
        recipientIds: InputFieldRecipientIds.fromArgs(args),
        sharedNote: _note.fromArgs(args) ?? '',
        context: _context.fromArgs(args),
        parentEdgeId: _parentEdgeId.fromArgs(args),
        sharedReasonSlugs: _reasonsFromArgs(args),
        perRecipientReasonSlugs: perRecipientReasonSlugs,
        perRecipientNotes: switch (_perRecipientNotes.fromArgs(args)) {
          final String s when s.isNotEmpty => Map<String, String>.from(
            (json.decode(s) as Map).map(
              (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
            ),
          ),
          _ => null,
        },
      );
    },
  );
}
