part of '_input_types.dart';

/// §21 telemetry: lets the client tag which recipients were selected from
/// the forward band (and at what tier/slot) so the server can log
/// conversion counts. Optional and additive — omitting it changes nothing.
abstract class InputFieldForwardRecipientBandProvenance {
  static final field = GraphQLFieldInput(
    _fieldKey,
    GraphQLListType(type),
    defaultsToNull: true,
  );

  static final type = GraphQLInputObjectType(
    'ForwardRecipientBandProvenanceInput',
    inputFields: [
      GraphQLInputObjectField('recipientId', graphQLString.nonNullable()),
      GraphQLInputObjectField('tier', graphQLString),
      GraphQLInputObjectField('isExploration', graphQLBoolean),
    ],
  );

  static List<({String recipientId, String? tier, bool isExploration})>?
  fromArgs(Map<String, dynamic> args) {
    final raw = args[_fieldKey];
    if (raw == null) return null;
    return (raw as List)
        .map(
          (e) {
            final m = e as Map<dynamic, dynamic>;
            return (
              recipientId: m['recipientId'] as String,
              tier: m['tier'] as String?,
              isExploration: m['isExploration'] as bool? ?? false,
            );
          },
        )
        .toList();
  }

  static const _fieldKey = 'recipientBandProvenance';
}
