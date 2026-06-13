import 'package:tentura_server/domain/entity/lineage_memory_fact.dart';
import 'package:tentura_server/domain/use_case/beacon_lineage_suggestions_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryLineageSuggestions extends GqlNodeBase {
  QueryLineageSuggestions({BeaconLineageSuggestionsCase? suggestionsCase})
    : _suggestionsCase =
          suggestionsCase ?? GetIt.I<BeaconLineageSuggestionsCase>();

  final BeaconLineageSuggestionsCase _suggestionsCase;

  List<GraphQLObjectField<dynamic, dynamic>> get all =>
      [beaconLineageForwardSuggestions];

  GraphQLObjectField<dynamic, dynamic> get beaconLineageForwardSuggestions =>
      GraphQLObjectField(
        'beaconLineageForwardSuggestions',
        gqlTypeBeaconLineageForwardSuggestions.nonNullable(),
        arguments: [InputFieldId.field],
        resolve: (_, args) async {
          final creds = getCredentials(args);
          final result = await _suggestionsCase.load(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            userId: creds.sub,
          );
          return _toJson(result);
        },
      );

  Map<String, Object?> _toJson(LineageForwardSuggestions value) => {
    'sourceBeaconId': value.sourceBeaconId,
    'rootBeaconId': value.rootBeaconId,
    'suggestedNote': value.suggestedNote,
    'suggestions': [
      for (final s in value.suggestions)
        {
          'userId': s.userId,
          'group': s.group.wireSlug,
          'reasonCode': s.reasonCode,
          'reasonArg': s.reasonArg,
          'autoSelect': s.autoSelect,
        },
    ],
  };
}
